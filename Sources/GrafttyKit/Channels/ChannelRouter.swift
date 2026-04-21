import Foundation
import Observation

/// Owns the channels socket server and the worktreePath → Connection map.
/// Fans out transition events to the matching subscriber; broadcasts
/// prompt updates (type=instructions) to all.
@MainActor
@Observable
public final class ChannelRouter {
    @ObservationIgnored private let server: ChannelSocketServer
    @ObservationIgnored private nonisolated(unsafe) let promptProvider: () -> String
    private var subscribers: [String: ChannelSocketServer.Connection] = [:]

    public var subscriberCount: Int { subscribers.count }

    /// When false, `dispatch` and `broadcastInstructions` become no-ops.
    /// Subscribers remain connected. Mirrors the Settings enable toggle.
    public var isEnabled: Bool = true

    public init(socketPath: String, promptProvider: @escaping () -> String) {
        self.server = ChannelSocketServer(socketPath: socketPath)
        self.promptProvider = promptProvider

        server.onSubscribe = { [weak self] message, conn in
            guard let self = self else { return }
            // ChannelSocketServer now calls us on its connection thread, so
            // we can (a) send the initial instructions immediately without
            // waiting for main-actor availability and (b) hop to the main
            // actor for the subscribers-map mutation where router state lives.
            let initial = ChannelServerMessage.event(
                type: ChannelEventType.instructions,
                attrs: [:],
                body: self.promptProvider()
            )
            try? conn.write(initial)
            Task { @MainActor [weak self] in self?.onSubscribe(message: message, conn: conn) }
        }
        server.onDisconnect = { [weak self] conn in
            Task { @MainActor [weak self] in self?.onDisconnect(conn: conn) }
        }
    }

    public func start() throws { try server.start() }
    public func stop() {
        server.stop()
        subscribers.removeAll()
    }

    /// Route a transition event to the matching subscriber, if any.
    public func dispatch(worktreePath: String, message: ChannelServerMessage) {
        guard isEnabled else { return }
        guard let conn = subscribers[worktreePath] else { return }
        writeOrPrune(conn: conn, message: message, worktreePath: worktreePath)
    }

    /// Fan out the current prompt as a type=instructions event to every
    /// subscriber. Called after the Settings prompt-edit debounce fires.
    public func broadcastInstructions() {
        guard isEnabled else { return }
        let body = promptProvider()
        let message = ChannelServerMessage.event(
            type: ChannelEventType.instructions, attrs: [:], body: body
        )
        // Encode once; write raw bytes to every subscriber.
        guard let encoded = try? JSONEncoder().encode(message) else { return }
        var payload = encoded
        payload.append(0x0A)

        // Collect dead subscribers and prune after iteration — Swift
        // dictionary iteration is snapshot-based so removing mid-loop
        // wouldn't crash, but two-phase is more explicit and robust to
        // future refactors that change iteration semantics.
        var dead: [String] = []
        for (worktree, conn) in subscribers {
            do {
                try conn.writeRaw(payload)
            } catch {
                dead.append(worktree)
            }
        }
        for worktree in dead {
            subscribers.removeValue(forKey: worktree)
        }
    }

    // MARK: private

    private func onSubscribe(message: ChannelClientMessage, conn: ChannelSocketServer.Connection) {
        guard case let .subscribe(worktree, _) = message else { return }
        subscribers[worktree] = conn
        // The initial `instructions` event was already written synchronously
        // from the server's connection thread in the init closure.
    }

    private func onDisconnect(conn: ChannelSocketServer.Connection) {
        subscribers = subscribers.filter { $0.value !== conn }
    }

    private func writeOrPrune(
        conn: ChannelSocketServer.Connection,
        message: ChannelServerMessage,
        worktreePath: String
    ) {
        do {
            try conn.write(message)
        } catch {
            subscribers.removeValue(forKey: worktreePath)
        }
    }
}
