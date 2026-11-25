package drone.test.core

/** Fail closed before an automatic takeoff. All clocks are monotonic. */
object DispatchSafety {
    fun reason(
        t: Telemetry,
        canFly: Boolean,
        link: UavLinkState,
        nowMs: Long,
        requestStartedMs: Long,
        remainingMs: Long
    ): String? {
        if (!canFly || t.demo) return "Real aircraft backend is not available"
        if (link != UavLinkState.LINKED || !t.linked) return "Aircraft is not linked"
        val model = t.aircraftModel.toUpperCase(java.util.Locale.US).filter { it.isLetterOrDigit() }
        if (!model.contains("PHANTOM4PRO")) return "Aircraft is not the configured Phantom 4 Pro"
        fun fresh(stamp: Long, maxAge: Long) = stamp > 0L && nowMs >= stamp && nowMs - stamp <= maxAge
        if (!fresh(t.flightStateAtMs, 5000L)) return "Flight telemetry is stale"
        if (!fresh(t.batteryStateAtMs, 15000L)) return "Battery telemetry is stale"
        if (!fresh(t.remoteStateAtMs, 10000L)) return "Remote controller telemetry is stale"
        if (t.isFlying || t.isGoingHome || t.isFailsafe || t.virtualStickOn) return "Aircraft is not in a safe ground state"
        if (t.batteryPercent < 30) return "Battery is below 30 percent or unknown"
        if (t.satellites < 8 || !t.homePointSet) return "GPS or home point is not ready"
        if (!t.latitude.isFinite() || !t.longitude.isFinite() || !t.homeLatitude.isFinite() || !t.homeLongitude.isFinite()) return "Position or home coordinates are unavailable"
        if (t.warning != null) return "Aircraft warning: ${t.warning}"
        val elapsed = nowMs - requestStartedMs
        if (elapsed < 0L || elapsed > 5000L || remainingMs <= elapsed + 1000L) return "Alert expired or network response was too slow"
        return null
    }
}
