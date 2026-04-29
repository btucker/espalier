#if canImport(UIKit)
import Foundation
import Testing
@testable import GrafttyMobileKit

@Suite
struct SSHConnectionTests {

    @Test
    func fingerprintsOpenSSHPublicKeyBlob() throws {
        let openSSHKey = try MobileSSHKeyStore(storage: InMemoryMobileSSHKeyStorage())
            .publicKey(comment: "test")

        let fingerprint = try SSHHostKeyFingerprint(openSSHPublicKey: openSSHKey)

        #expect(fingerprint.value.hasPrefix("SHA256:"))
        #expect(!fingerprint.value.contains("="))
    }

    @Test
    func hostKeyPinStoreTrustsFirstKeyAndRejectsChangedKey() throws {
        let store = InMemorySSHHostKeyPinStore()
        let host = SSHHostKeyPinTarget(host: "mac.local", port: 22)
        let first = SSHHostKeyFingerprint(rawSHA256Base64: "first")
        let changed = SSHHostKeyFingerprint(rawSHA256Base64: "changed")

        #expect(store.trustState(for: host, fingerprint: first) == .unknown(fingerprint: first))

        try store.trust(first, for: host)

        #expect(store.trustState(for: host, fingerprint: first) == .trusted)
        #expect(store.trustState(for: host, fingerprint: changed) == .changed(expected: first, actual: changed))
    }

    @Test
    func directResolverReturnsSavedBaseURL() async throws {
        let host = Host(label: "direct", baseURL: URL(string: "https://mac.ts.net:8799/")!)
        let resolver = HostConnectionResolver(tunnelStarter: FakeTunnelStarter())

        let connection = try await resolver.resolve(host)

        #expect(connection.baseURL == URL(string: "https://mac.ts.net:8799/")!)
    }

    @Test
    func sshResolverStartsTunnelAndReturnsLocalBaseURL() async throws {
        let config = SSHHostConfig(sshHost: "mac.local", sshPort: 2222, sshUsername: "me")
        let host = Host(label: "ssh", transport: .sshTunnel(config))
        let tunnel = FakeRunningTunnel(localBaseURL: URL(string: "http://127.0.0.1:54321/")!)
        let starter = FakeTunnelStarter(tunnel: tunnel)
        let resolver = HostConnectionResolver(tunnelStarter: starter)

        let connection = try await resolver.resolve(host)

        #expect(starter.startedConfigs == [config])
        #expect(connection.baseURL == tunnel.localBaseURL)
        await connection.close()
        #expect(tunnel.closeCount == 1)
    }
}

private final class FakeTunnelStarter: SSHTunnelStarting, @unchecked Sendable {
    var startedConfigs: [SSHHostConfig] = []
    private let tunnel: FakeRunningTunnel

    init(tunnel: FakeRunningTunnel = FakeRunningTunnel(localBaseURL: URL(string: "http://127.0.0.1:1/")!)) {
        self.tunnel = tunnel
    }

    func startTunnel(for config: SSHHostConfig) async throws -> any RunningSSHTunnel {
        startedConfigs.append(config)
        return tunnel
    }
}

private final class FakeRunningTunnel: RunningSSHTunnel, @unchecked Sendable {
    let localBaseURL: URL
    private(set) var closeCount = 0

    init(localBaseURL: URL) {
        self.localBaseURL = localBaseURL
    }

    func close() async {
        closeCount += 1
    }
}
#endif
