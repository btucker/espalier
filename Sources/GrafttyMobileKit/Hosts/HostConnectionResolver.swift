#if canImport(UIKit)
import Foundation

public protocol RunningSSHTunnel: Sendable {
    var localBaseURL: URL { get }
    func close() async
}

public protocol SSHTunnelStarting: Sendable {
    func startTunnel(for config: SSHHostConfig) async throws -> any RunningSSHTunnel
}

public final class ResolvedHostConnection: Sendable, Hashable, Identifiable {
    public let id: UUID
    public let host: Host
    public let baseURL: URL
    private let tunnel: (any RunningSSHTunnel)?

    public init(host: Host, baseURL: URL, tunnel: (any RunningSSHTunnel)? = nil) {
        self.id = host.id
        self.host = host
        self.baseURL = baseURL
        self.tunnel = tunnel
    }

    public func close() async {
        await tunnel?.close()
    }

    public static func == (lhs: ResolvedHostConnection, rhs: ResolvedHostConnection) -> Bool {
        lhs.id == rhs.id && lhs.baseURL == rhs.baseURL
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(baseURL)
    }
}

public struct HostConnectionResolver: Sendable {
    private let tunnelStarter: any SSHTunnelStarting

    public init(tunnelStarter: any SSHTunnelStarting = NIOSSHForwardingTunnelStarter()) {
        self.tunnelStarter = tunnelStarter
    }

    public func resolve(_ host: Host) async throws -> ResolvedHostConnection {
        switch host.transport {
        case .directHTTP(let baseURL):
            return ResolvedHostConnection(host: host, baseURL: baseURL)
        case .sshTunnel(let config):
            let tunnel = try await tunnelStarter.startTunnel(for: config)
            return ResolvedHostConnection(host: host, baseURL: tunnel.localBaseURL, tunnel: tunnel)
        }
    }
}
#endif
