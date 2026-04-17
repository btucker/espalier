import Testing
import Foundation
@testable import EspalierKit

@Suite("WebServer — integration (requires vendored zmx)")
struct WebServerIntegrationTests {

    /// Allocate an isolated ZMX_DIR under `/tmp` (see
    /// `ZmxSurvivalIntegrationTests.withScopedZmxDir` for why `/tmp` rather
    /// than `NSTemporaryDirectory()` — the 104-byte Unix-socket path limit).
    private static func scopedZmxDir() throws -> URL {
        let dir = URL(fileURLWithPath: "/tmp")
            .appendingPathComponent("zmx-web-it-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test func wsEchoRoundTrip() async throws {
        let zmx = try #require(
            ZmxSurvivalIntegrationTests.vendoredZmx(),
            "zmx binary not vendored — run scripts/bump-zmx.sh"
        )
        let zmxDir = try Self.scopedZmxDir()
        defer { try? FileManager.default.removeItem(at: zmxDir) }

        let server = WebServer(
            config: WebServer.Config(port: 0, zmxExecutable: zmx, zmxDir: zmxDir),
            auth: WebServer.AuthPolicy(isAllowed: { _ in true }),
            bindAddresses: ["127.0.0.1"]
        )
        try server.start()
        defer { server.stop() }
        guard case let .listening(_, port) = server.status else {
            Issue.record("server not listening"); return
        }

        let sessionName = "espalier-it\(UUID().uuidString.prefix(6).lowercased())"
        let url = URL(string: "ws://127.0.0.1:\(port)/ws?session=\(sessionName)")!
        let wsTask = URLSession.shared.webSocketTask(with: url)
        wsTask.resume()

        try await wsTask.send(.string(#"{"type":"resize","cols":80,"rows":24}"#))
        try await wsTask.send(.data(Data("echo HELLO_INTEG\n".utf8)))

        var collected = Data()
        let deadline = Date().addingTimeInterval(8)
        while Date() < deadline {
            let msg = try await wsTask.receive()
            switch msg {
            case .data(let d): collected.append(d)
            case .string(let s): collected.append(Data(s.utf8))
            @unknown default: break
            }
            if let s = String(data: collected, encoding: .utf8), s.contains("HELLO_INTEG") { break }
        }
        let text = String(data: collected, encoding: .utf8) ?? ""
        #expect(text.contains("HELLO_INTEG"))

        wsTask.cancel(with: .goingAway, reason: nil)

        // Best-effort clean up the session.
        let launcher = ZmxLauncher(executable: zmx, zmxDir: zmxDir)
        launcher.kill(sessionName: sessionName)
    }
}
