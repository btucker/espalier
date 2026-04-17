import Foundation

/// Resolves Ghostty apprt action names to chords. Built once at app
/// launch from `ghostty_config_trigger` via the resolver closure the
/// app target provides.
///
/// Pure value type — no GhosttyKit, no SwiftUI. The app target wraps
/// the raw libghostty call in a closure of shape
/// `(actionName) -> ShortcutChord?` and hands it to the init.
public struct GhosttyKeybindBridge: Sendable {
    public typealias Resolver = @Sendable (String) -> ShortcutChord?

    private let chords: [GhosttyAction: ShortcutChord]

    public init(resolver: Resolver) {
        var map: [GhosttyAction: ShortcutChord] = [:]
        for action in GhosttyAction.allCases {
            map[action] = resolver(action.rawValue)
        }
        self.chords = map
    }

    public subscript(action: GhosttyAction) -> ShortcutChord? {
        chords[action]
    }
}
