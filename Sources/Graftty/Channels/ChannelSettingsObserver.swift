import Foundation
import Combine
import GrafttyKit

/// Observes `channelPrompt` and `channelsEnabled` UserDefaults keys and
/// reacts:
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

    init(router: ChannelRouter, onEnable: @escaping @MainActor () -> Void = {}) {
        self.router = router
        self.onEnable = onEnable
        // Initial isEnabled from current defaults — covers the case where
        // the observer is constructed AFTER the app's launch-time start()
        // and the user has already changed the toggle once.
        router.isEnabled = UserDefaults.standard.bool(forKey: "channelsEnabled")

        UserDefaults.standard.publisher(for: \.channelPrompt)
            .dropFirst()  // skip the initial synchronous emit
            .sink { [weak self] _ in self?.schedulePromptBroadcast() }
            .store(in: &cancellables)

        UserDefaults.standard.publisher(for: \.channelsEnabled)
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
}

/// KVO-observable accessors on UserDefaults for the channel keys.
///
/// The Swift property names match the UserDefaults keys exactly, so KVO
/// (driven by the Objective-C property name) fires whenever anything —
/// including `@AppStorage("channelPrompt")` / `@AppStorage("channelsEnabled")`
/// — writes to those keys via `UserDefaults.standard.set(_:forKey:)`.
extension UserDefaults {
    @objc dynamic var channelPrompt: String {
        string(forKey: "channelPrompt") ?? ""
    }
    @objc dynamic var channelsEnabled: Bool {
        bool(forKey: "channelsEnabled")
    }
}
