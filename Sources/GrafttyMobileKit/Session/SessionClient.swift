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

    public init(sessionName: String, webSocket: WebSocketClient) {
        self.sessionName = sessionName
        self.ws = webSocket

        // We can't reference self inside the closures passed to
        // InMemoryTerminalSession.init (self isn't fully initialized
        // yet), so we use indirection: the closures read from mutable
        // ivars that we assign *after* super-init-equivalent.
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
        receiveTask = Task { [weak self] in
            guard let self else { return }
            while true {
                let stopped = await MainActor.run { self.stopped }
                if stopped { break }
                do {
                    let frame = try await self.ws.receive()
                    await MainActor.run {
                        switch frame {
                        case .binary(let data):
                            self.session.receive(data)
                        case .text:
                            // Server may send sessionEnded/error as text — a
                            // higher-level HostController will surface it.
                            // Ignored at this layer for now.
                            break
                        }
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
        let payload = #"{"type":"resize","cols":\#(cols),"rows":\#(rows)}"#
        Task { @MainActor [weak self] in
            guard let self, !self.stopped else { return }
            try? await self.ws.send(.text(payload))
        }
    }
}
#endif
