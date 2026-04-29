import Foundation
import Testing
@testable import GrafttyKit

@Suite(.serialized)
struct RemoteGrafttyClientTests {
    @Test
    func probeAcceptsSuccessfulResponse() async throws {
        let client = RemoteGrafttyClient(session: .mock(statusCode: 200, body: Data()))

        try await client.probe(baseURL: URL(string: "http://127.0.0.1:49152/")!)
    }

    @Test
    func probeRejectsHTTPFailure() async {
        let client = RemoteGrafttyClient(session: .mock(statusCode: 404, body: Data()))

        await #expect(throws: RemoteGrafttyClient.Error.grafttyUnavailable) {
            try await client.probe(baseURL: URL(string: "http://127.0.0.1:49152/")!)
        }
    }

    @Test
    func fetchRemoteReposMapsToRepoEntries() async throws {
        let json = """
        [{
          "path": "/Users/me/repo-a",
          "displayName": "repo-a"
        }]
        """.data(using: .utf8)!
        let client = RemoteGrafttyClient(session: .mock(statusCode: 200, body: json))

        let repos = try await client.fetchRepositorySnapshot(
            baseURL: URL(string: "http://127.0.0.1:49152/")!
        )

        #expect(repos.first?.path == "/Users/me/repo-a")
        #expect(repos.first?.displayName == "repo-a")
    }

    @Test
    func testConnectionReportsGrafttyUnavailableWhenTunnelStartsButProbeFails() async {
        let config = SSHHostConfig(sshHost: "dev-mini")
        let tunnel = FakeForwardProcess(localPort: 49152)
        let tester = AddHostConnectionTester(
            forwarder: FakeForwarder(result: .success(tunnel)),
            client: FakeRemoteGrafttyProbe(result: .failure(.grafttyUnavailable))
        )

        let result = await tester.test(config: config)

        #expect(tunnel.didStop)
        #expect(result == .grafttyUnavailable("SSH connected, but Graftty did not respond on the remote Mac. Open Graftty on dev-mini and enable SSH Tunnel mode."))
    }

    @Test
    func worktreeRouteIdentifiesRemoteWorktreeHost() {
        let remoteID = UUID()
        var state = AppState()
        state.remoteRepoCache[remoteID] = [
            RepoEntry(
                path: "/remote/repo",
                displayName: "repo",
                worktrees: [WorktreeEntry(path: "/remote/repo", branch: "main")]
            )
        ]

        let route = WorktreeRoute.resolve(path: "/remote/repo", state: state)

        #expect(route == .remote(hostID: remoteID, worktreePath: "/remote/repo"))
    }
}

private final class FakeForwardProcess: SSHLocalForwardProcess, @unchecked Sendable {
    let localPort: Int
    var didStop = false

    init(localPort: Int) {
        self.localPort = localPort
    }

    func stop() {
        didStop = true
    }
}

private struct FakeForwarder: SSHLocalForwarding {
    var result: Result<any SSHLocalForwardProcess, any Error>

    func start(config: SSHHostConfig) async throws -> any SSHLocalForwardProcess {
        try result.get()
    }
}

private struct FakeRemoteGrafttyProbe: RemoteGrafttyProbing {
    var result: Result<Void, RemoteGrafttyClient.Error>

    func probe(baseURL: URL) async throws {
        try result.get()
    }
}

private final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var statusCode = 200
    nonisolated(unsafe) static var body = Data()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: Self.statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private extension URLSession {
    static func mock(statusCode: Int, body: Data) -> URLSession {
        MockURLProtocol.statusCode = statusCode
        MockURLProtocol.body = body
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }
}
