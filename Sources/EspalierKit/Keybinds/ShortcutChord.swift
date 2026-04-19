import Foundation

public struct ShortcutModifiers: OptionSet, Hashable, Sendable, Codable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let shift   = ShortcutModifiers(rawValue: 1 << 0)
    public static let control = ShortcutModifiers(rawValue: 1 << 1)
    public static let option  = ShortcutModifiers(rawValue: 1 << 2)
    public static let command = ShortcutModifiers(rawValue: 1 << 3)
}

/// A keyboard chord: the key plus the modifier set.
///
/// `key` is a short printable token identifying the physical key:
/// lowercase letters `"a"`..`"z"`; digits `"0"`..`"9"`; `"arrowleft"`,
/// `"arrowright"`, `"arrowup"`, `"arrowdown"`; `"return"`, `"tab"`,
/// `"space"`, `"escape"`, `"backspace"`, `"delete"`; `"f1"`..`"f24"`;
/// plus punctuation tokens. The app-target adapter produces these from
/// `ghostty_input_trigger_s` and the SwiftUI translator consumes them.
public struct ShortcutChord: Hashable, Sendable, Codable {
    public let key: String
    public let modifiers: ShortcutModifiers

    public init(key: String, modifiers: ShortcutModifiers) {
        self.key = key
        self.modifiers = modifiers
    }
}
