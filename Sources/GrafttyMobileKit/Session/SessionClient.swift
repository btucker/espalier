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
        box.onBytes = { [weak self] data in
            Task { @MainActor [weak self] in
                guard let self, !self.stopped else { return }
                try? await self.ws.send(.binary(data))
            }
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
        let payload = WebControlEnvelope.resize(cols: cols, rows: rows).encoded()
        Task { @MainActor [weak self] in
            guard let self, !self.stopped else { return }
            try? await self.ws.send(.text(payload))
        }
    }

    /// Re-send the most recent viewport dimensions. zmx treats every
    /// resize as "this client wants the terminal at these dimensions",
    /// so calling this makes iOS the size-leader: other attached
    /// clients (the Mac pane) get rewrapped down to the iOS width.
    /// No-op before any resize has landed (i.e. before the terminal
    /// has laid out once).
    public func reassertSize() {
        guard let v = lastViewport else { return }
        sendResize(cols: v.cols, rows: v.rows)
    }
}
#endif
