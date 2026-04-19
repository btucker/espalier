import Testing
@testable import EspalierKit

// Mirrors `NotifyInputValidationTests` so CLI-side and server-side
// validation stay in sync. If the CLI drifts, the server is the
// backstop — and vice versa.
@Suite("Attention.isValidText")
struct AttentionTextValidationTests {
    @Test func nonEmptyIsValid() {
        #expect(Attention.isValidText("Build failed"))
        #expect(Attention.isValidText("·"))
        #expect(Attention.isValidText("🔔"))
    }

    @Test func emptyIsInvalid() {
        #expect(!Attention.isValidText(""))
    }

    @Test func whitespaceOnlyIsInvalid() {
        for ws in ["   ", "\t", "\n", "  \t\n "] {
            #expect(!Attention.isValidText(ws), "expected invalid for \(ws.debugDescription)")
        }
    }

    @Test func leadingTrailingWhitespaceOnContentIsValid() {
        // The helper only rejects pure whitespace. Content with padding
        // still makes it through — the UI doesn't strip it, but that's
        // a rendering choice rather than an input-hygiene policy.
        #expect(Attention.isValidText("  build done  "))
    }
}
