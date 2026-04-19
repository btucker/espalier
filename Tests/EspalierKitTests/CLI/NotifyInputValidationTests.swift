import Testing
@testable import EspalierKit

@Suite("NotifyInputValidation")
struct NotifyInputValidationTests {

    @Test func textOnlyIsValid() {
        let r = NotifyInputValidation.validate(text: "Build failed", clear: false)
        #expect(r == .valid)
        #expect(r.message == nil)
    }

    @Test func clearOnlyIsValid() {
        let r = NotifyInputValidation.validate(text: nil, clear: true)
        #expect(r == .valid)
    }

    @Test func neitherIsMissing() {
        let r = NotifyInputValidation.validate(text: nil, clear: false)
        #expect(r == .missingTextAndClear)
        #expect(r.message?.contains("--clear") == true)
    }

    @Test func bothIsConflict() {
        // The bug that triggered this: `espalier notify "Build failed" --clear`
        // previously exited 0. The text was dropped and the server received
        // just a clear. Andy's ambiguous input should error instead so he
        // notices the stale `--clear` in shell history.
        let r = NotifyInputValidation.validate(text: "Build failed", clear: true)
        #expect(r == .bothTextAndClear)
        #expect(r.message?.contains("Cannot combine") == true)
    }

    @Test func emptyStringCountsAsText() {
        // ArgumentParser already rejects truly missing positional args, so
        // `notify ""` arrives as `text = Optional.some("")`. We treat it as
        // text (not nil) — the server will store an empty capsule, but
        // that's a UI-level concern outside this validator's job. What
        // matters here is: "" + --clear still conflicts.
        let r = NotifyInputValidation.validate(text: "", clear: true)
        #expect(r == .bothTextAndClear)
    }
}
