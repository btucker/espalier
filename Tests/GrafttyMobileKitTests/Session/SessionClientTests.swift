#if canImport(UIKit)
import Foundation
import Testing
@testable import GrafttyMobileKit
import GrafttyProtocol

@Suite
@MainActor
struct SessionClientTests {

    final class FakeWS: WebSocketClient, @unchecked Sendable {
        var sent: [WebSocketFrame] = []
        var closed = false
        func send(_ frame: WebSocketFrame) async throws { sent.append(frame) }
        func receive() async throws -> WebSocketFrame {
            try await Task.sleep(nanoseconds: 10_000_000_000)
            throw CancellationError()
        }
        func close() { closed = true }
    }

    @Test
    func sendingBytesFromTerminalGoesOutAsBinary() async throws {
        let ws = FakeWS()
        let client = SessionClient(sessionName: "s", webSocket: ws)
        defer { client.stop() }
        // Simulate libghostty surface emitting bytes.
        client.session.sendInput(Data([0x68, 0x69]))   // "hi"
        // Allow the spawned Task to run.
        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(ws.sent.contains(.binary(Data([0x68, 0x69]))))
    }

    /// The iOS soft keyboard's Return produces LF via `UIKeyInput.insertText`,
    /// but TUIs expect CR (what a physical terminal Return sends). Without
    /// translation, Enter inserts a literal newline in the prompt rather than
    /// submitting. IOS-6.3.
    @Test
    func softKeyboardReturnLFIsTranslatedToCR() async throws {
        let ws = FakeWS()
        let client = SessionClient(sessionName: "s", webSocket: ws)
        defer { client.stop() }
        client.session.sendInput(Data([0x0A]))
        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(ws.sent.contains(.binary(Data([0x0D]))))
        #expect(!ws.sent.contains(.binary(Data([0x0A]))))
    }

    /// The in-app "Newline" button has to send a literal LF — it exists
    /// precisely to reach the newline code that the keyboard's Return
    /// can no longer emit after IOS-6.3. IOS-6.4.
    @Test
    func insertNewlineSendsLiteralLF() async throws {
        let ws = FakeWS()
        let client = SessionClient(sessionName: "s", webSocket: ws)
        defer { client.stop() }
        client.insertNewline()
        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(ws.sent.contains(.binary(Data([0x0A]))))
    }

    /// Multi-byte paste buffers with embedded LFs must pass through
    /// unchanged — the LF→CR rule only applies to a standalone Return
    /// keystroke, not to arbitrary content that happens to contain LF.
    @Test
    func multiByteBufferWithEmbeddedLFIsNotTranslated() async throws {
        let ws = FakeWS()
        let client = SessionClient(sessionName: "s", webSocket: ws)
        defer { client.stop() }
        let paste = Data([0x68, 0x0A, 0x69])   // "h\ni"
        client.session.sendInput(paste)
        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(ws.sent.contains(.binary(paste)))
    }

    @Test
    func stopClosesWebSocket() {
        let ws = FakeWS()
        let client = SessionClient(sessionName: "s", webSocket: ws)
        client.stop()
        #expect(ws.closed)
    }
}
#endif
