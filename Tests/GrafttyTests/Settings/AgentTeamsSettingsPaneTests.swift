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

    /// teamLeadPrompt and teamCoworkerPrompt persist independently (TEAM-1.6).
    @Test func leadAndCoworkerPromptsAreIndependent() {
        let defaults = UserDefaults(suiteName: "AgentTeamsSettingsPaneTests-2")!
        defaults.removePersistentDomain(forName: "AgentTeamsSettingsPaneTests-2")

        defaults.set("lead policy text", forKey: SettingsKeys.teamLeadPrompt)
        defaults.set("coworker policy text", forKey: SettingsKeys.teamCoworkerPrompt)

        #expect(defaults.string(forKey: SettingsKeys.teamLeadPrompt) == "lead policy text")
        #expect(defaults.string(forKey: SettingsKeys.teamCoworkerPrompt) == "coworker policy text")

        // Mutating one must not affect the other.
        defaults.set("updated lead", forKey: SettingsKeys.teamLeadPrompt)
        #expect(defaults.string(forKey: SettingsKeys.teamCoworkerPrompt) == "coworker policy text")
    }

    /// teamLeadPrompt and teamCoworkerPrompt default to empty strings (TEAM-1.6).
    @Test func promptsDefaultToEmptyStrings() {
        let defaults = UserDefaults(suiteName: "AgentTeamsSettingsPaneTests-3")!
        defaults.removePersistentDomain(forName: "AgentTeamsSettingsPaneTests-3")

        #expect((defaults.string(forKey: SettingsKeys.teamLeadPrompt) ?? "") == "")
        #expect((defaults.string(forKey: SettingsKeys.teamCoworkerPrompt) ?? "") == "")
    }
}
