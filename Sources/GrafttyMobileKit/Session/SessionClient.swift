#if canImport(UIKit)
import Foundation
import GhosttyTerminal
import GrafttyProtocol

/// Owns one WebSocket + one libghostty InMemoryTerminalSession. Wires
/// terminal-input → binary WS out; binary WS in → terminal.receive;
/// resize events → JSON text WS out.
@MainActor
public final class SessionClient {

    public let sessionName: String
    public let session: InMemoryTerminalSession

    private let ws: WebSocketClient
    private var receiveTask: Task<Void, Never>?
    private var stopped = false
    /// Last dimensions libghostty reported for this client's viewport.
    /// Tracked so `reassertSize()` can re-send them on demand — tapping
    /// the terminal on iOS should make this client the size-leader
    /// against zmx, which rewraps the shared session to match.
    private var lastViewport: (cols: UInt16, rows: UInt16)?

    public init(sessionName: String, webSocket: WebSocketClient) {
        self.sessionName = sessionName
        self.ws = webSocket

        // Indirection box lets the `write`/`resize` callbacks reach back
        // into `self` after it is fully initialized.
        final class Box { var onBytes: (@Sendable (Data) -> Void)?
                          var onResize: (@Sendable (InMemoryTerminalViewport) -> Void)? }
        let box = Box()
        self.session = InMemoryTerminalSession(
            write: { data in box.onBytes?(data) },
            resize: { viewport in box.onResize?(viewport) }
        )
        // These callbacks are declared @Sendable by libghostty-spm so
        // they can be invoked from any actor — the MainActor hop has
        // to happen here. For `onBytes` the payload is just pushed
        // onto the WebSocket which is itself async-to-anywhere, so we
        // skip the hop and capture `ws` directly: zero per-keystroke
        // main-actor work.
        box.onBytes = { [ws] data in
            Task { try? await ws.send(.binary(data)) }
        }
        box.onResize = { [weak self] viewport in
            Task { @MainActor [weak self] in
                guard let self, !self.stopped else { return }
                self.sendResize(
                    cols: max(1, viewport.columns),
                    rows: max(1, viewport.rows)
                )
            }
        }
    }

    public func start() {
        receiveTask = Task { @MainActor [weak self] in
            while let self, !self.stopped {
                do {
                    let frame = try await self.ws.receive()
                    switch frame {
                    case .binary(let data):
                        self.session.receive(data)
                    case .text:
                        break
                    }
                } catch {
                    break
                }
            }
        }
    }

    public func stop() {
        guard !stopped else { return }
        stopped = true
        receiveTask?.cancel()
        receiveTask = nil
        ws.close()
    }

    public func sendResize(cols: UInt16, rows: UInt16) {
        lastViewport = (cols, rows)
        enqueueSend(.text(WebControlEnvelope.resize(cols: cols, rows: rows).encoded()))
    }

    /// Re-send the most recent viewport dimensions. zmx treats every
    /// resize as "this client wants the terminal at these dimensions",
    /// so calling this makes iOS the size-leader: other attached
    /// clients (the Mac pane) get rewrapped down to the iOS width.
    /// Debounced to at most one send per second because taps can fire
    /// rapidly (every tap during cursor-positioning, selection, etc.)
    /// and each un-debounced call is a full Tailscale round-trip.
    public func reassertSize() {
        guard let v = lastViewport else { return }
        let now = Date()
        if let last = lastReassertAt, now.timeIntervalSince(last) < 1.0 {
            return
        }
        lastReassertAt = now
        sendResize(cols: v.cols, rows: v.rows)
    }

    private var lastReassertAt: Date?

    /// Fire-and-forget async send. Used from sync callbacks that run on
    /// MainActor (libghostty's write/resize callbacks) so we don't wrap
    /// every single keystroke in an extra `Task { @MainActor }`.
    private func enqueueSend(_ frame: WebSocketFrame) {
        Task { [ws] in
            try? await ws.send(frame)
        }
    }
}
#endif
