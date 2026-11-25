package drone.test.core

import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

/** Foreground-only, one-alert-per-arm connection to the existing DJI backend. */
class MotionDispatch(private val stateChanged: (String) -> Unit) {
    companion object {
        private const val BASE = "https://ujssojzmydxcnfummtwu.supabase.co"
        private const val KEY = "sb_publishable__qNms45omAau_DJRZyVBZQ_DdHABOmk"
        private val worker = Executors.newSingleThreadExecutor()
    }

    private val main = Handler(Looper.getMainLooper())
    @Volatile private var generation = 0
    @Volatile var active = false
        private set
    @Volatile private var sessionId: String? = null
    @Volatile private var token: String? = null
    @Volatile private var telemetryGeneration = 0
    private var takeoffIssued = false
    val hasConnection: Boolean get() = sessionId != null

    private fun state(message: String) {
        LogBus.info("dispatch: $message")
        stateChanged(message)
    }

    /** Called on the main thread after the operator has confirmed the area. */
    fun arm(email: String, password: String) {
        if (active) return
        if (sessionId != null) { state("stop the current link before re-arming"); return }
        if (takeoffIssued) { state("restart the control screen after the flight before re-arming"); return }
        val now = SystemClock.elapsedRealtime()
        val reason = DispatchSafety.reason(TelemetryStore.current, Backend.uav.canFly, Backend.uav.link(), now, now, 20000L)
        if (reason != null) { state("not armed: $reason"); return }
        generation += 1
        val current = generation
        active = true
        state("signing in")
        worker.execute {
            try {
                val login = request("/auth/v1/token?grant_type=password", null, JSONObject().put("email", email).put("password", password))
                val access = JSONObject(login).getString("access_token")
                if (!valid(current)) return@execute
                val result = JSONObject(request("/rest/v1/rpc/drone_arm_controller", access, JSONObject()))
                val session = result.getString("id")
                main.post {
                    if (!valid(current)) {
                        worker.execute { runCatching { rpc("drone_disarm_controller", access, JSONObject().put("p_session", session)) } }
                    } else {
                        token = access
                        sessionId = session
                        telemetryGeneration += 1
                        state("armed for one fresh alert; expires in 10 minutes")
                        sendTelemetry(session, access, telemetryGeneration)
                        poll(current)
                    }
                }
            } catch (error: Exception) {
                main.post { if (valid(current)) { active = false; state("not armed: ${safeError(error)}") } }
            }
        }
    }

    /** Main-thread stop: immediately invalidates pending callbacks. */
    fun disarm() {
        if (!active && sessionId == null) return
        active = false
        generation += 1
        telemetryGeneration += 1
        val session = sessionId
        val access = token
        sessionId = null
        token = null
        state("disarmed")
        if (session != null && access != null) worker.execute {
            runCatching { rpc("drone_disarm_controller", access, JSONObject().put("p_session", session)) }
                .onFailure { LogBus.warn("dispatch disarm was not acknowledged; server lease expires automatically") }
        }
    }

    private fun valid(current: Int) = active && generation == current

    private fun poll(current: Int) {
        if (!valid(current)) return
        val now = SystemClock.elapsedRealtime()
        val reason = DispatchSafety.reason(TelemetryStore.current, Backend.uav.canFly, Backend.uav.link(), now, now, 20000L)
        if (reason != null) { state("safety check failed: $reason"); disarm(); return }
        val session = sessionId ?: return
        val access = token ?: return
        worker.execute {
            val started = SystemClock.elapsedRealtime()
            try {
                val body = rpc("drone_claim_next", access, JSONObject().put("p_session", session))
                if (body.trim() == "null" || body.isBlank()) {
                    main.postDelayed({ if (valid(current)) poll(current) }, 2000L)
                    return@execute
                }
                val claim = JSONObject(body)
                val id = claim.getLong("id")
                val remaining = claim.getLong("remaining_ms")
                main.post {
                    val checkNow = SystemClock.elapsedRealtime()
                    val failure = if (!valid(current)) "Controller was disarmed" else DispatchSafety.reason(
                        TelemetryStore.current, Backend.uav.canFly, Backend.uav.link(), checkNow, started, remaining
                    )
                    if (valid(current)) {
                        active = false
                        generation += 1
                    }
                    if (failure != null) {
                        state("request $id refused: $failure")
                        report(access, session, id, false, failure)
                    } else {
                        takeoffIssued = true
                        state("request $id: sending takeoff to DJI")
                        val reported = AtomicBoolean(false)
                        try {
                            Backend.uav.takeoffWithResult { error ->
                                if (reported.compareAndSet(false, true)) {
                                    LogBus.info(if (error == null) "dispatch $id: DJI accepted takeoff" else "dispatch $id: DJI rejected takeoff: $error")
                                    report(access, session, id, error == null, error ?: "DJI accepted takeoff; airborne status not confirmed")
                                }
                            }
                        } catch (error: Exception) {
                            if (reported.compareAndSet(false, true)) report(access, session, id, false, "DJI call failed")
                            state("DJI takeoff call failed")
                        }
                    }
                }
            } catch (error: Exception) {
                main.post { if (valid(current)) { state("connection failed: ${safeError(error)}"); disarm() } }
            }
        }
    }

    private fun report(access: String, session: String, id: Long, success: Boolean, detail: String) {
        worker.execute {
            try {
                rpc("drone_report_result", access, JSONObject().put("p_session", session).put("p_request", id).put("p_success", success).put("p_detail", detail))
                main.post { state("request $id: ${if (success) "DJI accepted; monitor the aircraft" else "refused or failed"}") }
            } catch (_: Exception) {
                LogBus.err("dispatch $id: result could not be recorded; do not retry this request")
                main.post { state("request $id: result not recorded; check the aircraft") }
            }
        }
    }

    private fun sendTelemetry(session: String, access: String, epoch: Int) {
        if (telemetryGeneration != epoch || sessionId != session) return
        val t = TelemetryStore.current
        val data = JSONObject()
            .put("linked", t.linked)
            .put("is_flying", t.isFlying)
            .put("battery_percent", t.batteryPercent)
            .put("satellites", t.satellites)
            .put("flight_mode", t.flightMode)
            .put("home_point_set", t.homePointSet)
            .put("failsafe", t.isFailsafe)
            .put("warning", t.warning)
            .put("flight_age_ms", if (t.flightStateAtMs > 0) SystemClock.elapsedRealtime() - t.flightStateAtMs else -1)
        if (t.altitudeM.isFinite()) data.put("altitude_m", t.altitudeM.toDouble())
        if (t.latitude.isFinite() && t.longitude.isFinite()) {
            data.put("latitude", t.latitude).put("longitude", t.longitude)
        }
        worker.execute {
            try { rpc("drone_report_telemetry", access, JSONObject().put("p_session", session).put("p_data", data)) }
            catch (_: Exception) { LogBus.warn("dispatch: telemetry upload failed") }
            main.postDelayed({ sendTelemetry(session, access, epoch) }, 5000L)
        }
    }

    private fun rpc(name: String, access: String, body: JSONObject) = request("/rest/v1/rpc/$name", access, body)

    private fun request(path: String, access: String?, body: JSONObject): String {
        val connection = URL(BASE + path).openConnection() as HttpURLConnection
        try {
            connection.requestMethod = "POST"
            connection.connectTimeout = 4000
            connection.readTimeout = 4000
            connection.doOutput = true
            connection.setRequestProperty("apikey", KEY)
            connection.setRequestProperty("Content-Type", "application/json")
            if (access != null) connection.setRequestProperty("Authorization", "Bearer $access")
            connection.outputStream.use { it.write(body.toString().toByteArray(Charsets.UTF_8)) }
            val status = connection.responseCode
            if (status !in 200..299) throw IllegalStateException("server returned HTTP $status")
            return connection.inputStream.bufferedReader(Charsets.UTF_8).use { it.readText() }
        } finally { connection.disconnect() }
    }

    private fun safeError(error: Exception): String = when (error) {
        is IllegalStateException -> error.message ?: "request failed"
        else -> "network or authentication error"
    }
}
