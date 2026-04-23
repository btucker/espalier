import Testing
import Foundation
@testable import GrafttyKit

@Suite("UpdaterController state")
@MainActor
struct UpdaterControllerStateTests {

    // The Sparkle wiring is skipped in tests (`forTesting()` constructs a
    // controller without an `SPUUpdater`). Tests drive the published
    // state directly via the internal `notify…` hooks that the real
    // delegate methods call in the live path. This verifies the contract
    // the UI depends on: badge visibility and advertised version.

    @Test func startsWithNoUpdate() {
        let c = UpdaterController.forTesting()
        #expect(c.updateAvailable == false)
        #expect(c.availableVersion == nil)
    }

    @Test func scheduledDiscoveryMakesBadgeVisible() {
        let c = UpdaterController.forTesting()
        c.notifyPendingUpdateDiscovered(version: "0.3.0")
        #expect(c.updateAvailable == true)
        #expect(c.availableVersion == "0.3.0")
    }

    @Test func clearResetsState() {
        let c = UpdaterController.forTesting()
        c.notifyPendingUpdateDiscovered(version: "0.3.0")
        c.notifyPendingUpdateCleared()
        #expect(c.updateAvailable == false)
        #expect(c.availableVersion == nil)
    }

    @Test func secondScheduledDiscoveryReplacesVersion() {
        let c = UpdaterController.forTesting()
        c.notifyPendingUpdateDiscovered(version: "0.3.0")
        c.notifyPendingUpdateDiscovered(version: "0.3.1")
        #expect(c.availableVersion == "0.3.1")
    }
}
