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
    @ObservationIgnored private var subscribers: [String: ChannelSocketServer.Connection] = [:]

    public private(set) var subscriberCount: Int = 0

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
        subscriberCount = 0
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
        for (worktree, conn) in subscribers {
            writeOrPrune(conn: conn, message: message, worktreePath: worktree)
        }
    }

    // MARK: private

    private func onSubscribe(message: ChannelClientMessage, conn: ChannelSocketServer.Connection) {
        guard case let .subscribe(worktree, _) = message else { return }
        subscribers[worktree] = conn
        subscriberCount = subscribers.count
        // The initial `instructions` event was already written synchronously
        // from the server's connection thread in the init closure.
    }

    private func onDisconnect(conn: ChannelSocketServer.Connection) {
        subscribers = subscribers.filter { $0.value !== conn }
        subscriberCount = subscribers.count
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
            subscriberCount = subscribers.count
        }
    }
}
