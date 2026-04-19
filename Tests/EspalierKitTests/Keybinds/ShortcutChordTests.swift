import Testing
@testable import EspalierKit

@Suite("ShortcutChord")
struct ShortcutChordTests {
    @Test func modifiersOptionSetCombines() {
        let m: ShortcutModifiers = [.command, .shift]
        #expect(m.contains(.command))
        #expect(m.contains(.shift))
        #expect(!m.contains(.option))
    }

    @Test func chordEqualityIgnoresNothing() {
        let a = ShortcutChord(key: "d", modifiers: [.command])
        let b = ShortcutChord(key: "d", modifiers: [.command])
        let c = ShortcutChord(key: "d", modifiers: [.command, .shift])
        #expect(a == b)
        #expect(a != c)
    }
}
