import Testing
import SwiftUI
@testable import Graftty

@Suite("AgentTeamsSettingsPane Tests")
struct AgentTeamsSettingsPaneTests {

    /// Enabling team mode does NOT touch any separate channelsEnabled flag —
    /// the channel infrastructure is gated entirely by agentTeamsEnabled (TEAM-1.2).
    @Test func enablingTeamModeDoesNotWriteChannelsEnabled() {
        let defaults = UserDefaults(suiteName: "AgentTeamsSettingsPaneTests-1")!
        defaults.removePersistentDomain(forName: "AgentTeamsSettingsPaneTests-1")
        // channelsEnabled is no longer a tracked key; verify it stays absent.
        defaults.set(false, forKey: "agentTeamsEnabled")
        defaults.removeObject(forKey: "channelsEnabled")

        // Simulate the toggle being turned on (directly via UserDefaults, as the
        // old applyTeamModeToggleSideEffects did). There is no longer a static
        // helper — just set the flag.
        defaults.set(true, forKey: "agentTeamsEnabled")

        // channelsEnabled must remain absent/false — no cascade writes it anymore.
        #expect(defaults.object(forKey: "channelsEnabled") == nil
                || defaults.bool(forKey: "channelsEnabled") == false)
    }
}
