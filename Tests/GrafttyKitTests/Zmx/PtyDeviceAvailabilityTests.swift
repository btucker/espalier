import Testing
@testable import GrafttyKit

@Suite("PTY device availability")
struct PtyDeviceAvailabilityTests {

    @Test func availableWhenProbeOpensAndClosesPTY() {
        var closedFD: Int32?

        let availability = PtyDeviceAvailability.probe(
            openPTY: { 42 },
            grantPTY: { _ in 0 },
            unlockPTY: { _ in 0 },
            closeFD: { closedFD = $0 }
        )

        #expect(availability == .available)
        #expect(closedFD == 42)
    }

    @Test func exhaustedWhenOpenPTYFails() {
        let availability = PtyDeviceAvailability.probe(
            openPTY: { -1 },
            grantPTY: { _ in Issue.record("should not grant an invalid fd"); return -1 },
            unlockPTY: { _ in Issue.record("should not unlock an invalid fd"); return -1 },
            closeFD: { _ in Issue.record("should not close an invalid fd") }
        )

        #expect(availability == .unavailable)
    }

    @Test func unavailableWhenGrantFailsAndClosesPTY() {
        var closedFD: Int32?

        let availability = PtyDeviceAvailability.probe(
            openPTY: { 42 },
            grantPTY: { _ in -1 },
            unlockPTY: { _ in Issue.record("should not unlock when grant failed"); return -1 },
            closeFD: { closedFD = $0 }
        )

        #expect(availability == .unavailable)
        #expect(closedFD == 42)
    }

    @Test func unavailableWhenUnlockFailsAndClosesPTY() {
        var closedFD: Int32?

        let availability = PtyDeviceAvailability.probe(
            openPTY: { 42 },
            grantPTY: { _ in 0 },
            unlockPTY: { _ in -1 },
            closeFD: { closedFD = $0 }
        )

        #expect(availability == .unavailable)
        #expect(closedFD == 42)
    }
}
