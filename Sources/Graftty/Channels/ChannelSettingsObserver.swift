import Foundation
import Combine
import GrafttyKit

/// Observes `teamLeadPrompt`, `teamCoworkerPrompt`, and `agentTeamsEnabled` UserDefaults
/// keys and reacts:
/// - Prompt edits → 500ms debounce → `router.broadcastInstructions()`.
///   Debouncing coalesces rapid typing into one fanout per settled edit,
///   so subscribers don't get a flood of instructions events while the
///   user is mid-sentence.
/// - Enabled toggle flips → start or set `isEnabled` on the router.
///   Disabled → router stops routing but keeps subscribers connected,
///   so re-enabling is instant. Running sessions' launch flags were
///   baked at spawn and don't change mid-session.
@MainActor
final class ChannelSettingsObserver {
    private let router: ChannelRouter
    private let onEnable: @MainActor () -> Void
    private var promptTimer: Timer?
    private var cancellables: Set<AnyCancellable> = []

    /// Provides the current `AppState` for composing per-worktree team
    /// instructions (TEAM-3.3). Set by the app after construction so
    /// that the `@State`-backed value is accessible. `nil` in tests that
    /// don't exercise team logic.
    var appStateProvider: (() -> AppState)?

    init(router: ChannelRouter, onEnable: @escaping @MainActor () -> Void = {}) {
        self.router = router
        self.onEnable = onEnable
        // Initial isEnabled from current defaults — covers the case where
        // the observer is constructed AFTER the app's launch-time start()
        // and the user has already changed the toggle once.
        router.isEnabled = UserDefaults.standard.bool(forKey: SettingsKeys.agentTeamsEnabled)

        UserDefaults.standard.publisher(for: \.teamLeadPrompt)
            .dropFirst()  // skip the initial synchronous emit
            .sink { [weak self] _ in self?.schedulePromptBroadcast() }
            .store(in: &cancellables)

        UserDefaults.standard.publisher(for: \.teamCoworkerPrompt)
            .dropFirst()
            .sink { [weak self] _ in self?.schedulePromptBroadcast() }
            .store(in: &cancellables)

        UserDefaults.standard.publisher(for: \.agentTeamsEnabled)
            .dropFirst()
            .sink { [weak self] enabled in
                Task { @MainActor [weak self] in self?.apply(enabled: enabled) }
            }
            .store(in: &cancellables)
    }

    private func schedulePromptBroadcast() {
        promptTimer?.invalidate()
        promptTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.router.broadcastInstructions() }
        }
    }

    private func apply(enabled: Bool) {
        router.isEnabled = enabled
        if enabled {
            // Install plugin config before starting — the user may have
            // toggled channels on mid-session, before ~/.claude/plugins/
            // has been populated.
            onEnable()
            do {
                try router.start()
            } catch {
                NSLog("[Graftty] ChannelRouter start failed: %@", String(describing: error))
            }
        }
    }

    /// Composes team MCP instructions + role-specific user prompt for a specific
    /// worktree (TEAM-3.3). Returns an empty string for non-team contexts.
    func composedPrompt(forWorktree worktreePath: String) -> String {
        let teamsEnabled = UserDefaults.standard.bool(forKey: SettingsKeys.agentTeamsEnabled)

        guard teamsEnabled,
              let appState = appStateProvider?(),
              let worktree = appState.worktree(forPath: worktreePath),
              let team = TeamView.team(for: worktree, in: appState.repos, teamsEnabled: true),
              let me = team.members.first(where: { $0.worktreePath == worktreePath })
        else {
            return ""
        }

        let teamInstructions = TeamInstructionsRenderer.render(team: team, viewer: me)
        let userPromptKey = me.role == .lead
            ? SettingsKeys.teamLeadPrompt
            : SettingsKeys.teamCoworkerPrompt
        let userPrompt = UserDefaults.standard.string(forKey: userPromptKey) ?? ""

        if userPrompt.isEmpty {
            return teamInstructions
        }
        return teamInstructions + "\n\n" + userPrompt
    }
}

/// KVO-observable accessors on UserDefaults for the channel keys.
///
/// The Swift property names match the UserDefaults keys exactly, so KVO
/// (driven by the Objective-C property name) fires whenever anything —
/// including `@AppStorage("teamLeadPrompt")` / `@AppStorage("teamCoworkerPrompt")`
/// / `@AppStorage("agentTeamsEnabled")` — writes to those keys via
/// `UserDefaults.standard.set(_:forKey:)`.
extension UserDefaults {
    @objc dynamic var teamLeadPrompt: String {
        string(forKey: "teamLeadPrompt") ?? ""
    }
    @objc dynamic var teamCoworkerPrompt: String {
        string(forKey: "teamCoworkerPrompt") ?? ""
    }
    @objc dynamic var agentTeamsEnabled: Bool {
        bool(forKey: "agentTeamsEnabled")
    }
}
