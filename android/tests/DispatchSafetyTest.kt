import drone.test.core.*
fun main() {
    val fixture = Telemetry(aircraftModel="PHANTOM_4_PRO", linked=true, homePointSet=true, satellites=10, batteryPercent=80,
        latitude=-25.0, longitude=28.0, homeLatitude=-25.0, homeLongitude=28.0,
        flightStateAtMs=9900L, batteryStateAtMs=9900L, remoteStateAtMs=9900L)
    fun gate(t: Telemetry = fixture, can: Boolean = true, link: UavLinkState = UavLinkState.LINKED, now: Long = 10000L, started: Long = 9500L, remaining: Long = 10000L) = DispatchSafety.reason(t,can,link,now,started,remaining)
    check(gate() == null)
    check(gate(fixture.copy(demo=true)) != null)
    check(gate(can=false) != null)
    check(gate(link=UavLinkState.STANDBY) != null)
    check(gate(fixture.copy(aircraftModel="DJI Mini 2")) != null)
    check(gate(fixture.copy(flightStateAtMs=0)) != null)
    check(gate(fixture.copy(batteryStateAtMs=0)) != null)
    check(gate(fixture.copy(remoteStateAtMs=0)) != null)
    check(gate(fixture.copy(isFlying=true)) != null)
    check(gate(fixture.copy(isFailsafe=true)) != null)
    check(gate(fixture.copy(virtualStickOn=true)) != null)
    check(gate(fixture.copy(batteryPercent=29)) != null)
    check(gate(fixture.copy(satellites=7)) != null)
    check(gate(fixture.copy(homePointSet=false)) != null)
    check(gate(fixture.copy(homeLatitude=Double.NaN)) != null)
    check(gate(fixture.copy(warning="BATTERY LOW")) != null)
    check(gate(started=0) != null)
    check(gate(remaining=1200) != null)
    println("DispatchSafety: 18 checks passed")
}
