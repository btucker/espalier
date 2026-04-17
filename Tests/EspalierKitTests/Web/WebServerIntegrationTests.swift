import Testing
import Foundation
@testable import EspalierKit

@Suite("WebServer — integration (requires zmx on PATH)")
struct WebServerIntegrationTests {

    private static func requireZmx() throws -> URL {
        let which = Process()
        which.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        which.arguments = ["zmx"]
        let pipe = Pipe()
        which.standardOutput = pipe
        try which.run()
        which.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        try #require(!path.isEmpty, "zmx binary not on PATH; skipping integration")
        return URL(fileURLWithPath: path)
    }

    private static func scopedZmxDir() throws -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("espalier-web-it-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test func wsEchoRoundTrip() async throws {
        let zmx = try Self.requireZmx()
        let zmxDir = try Self.scopedZmxDir()
        defer { try? FileManager.default.removeItem(at: zmxDir) }

        var assets: [String: WebStaticResources.Asset] = [:]
        for p in ["/", "/xterm.min.js", "/xterm.min.css", "/xterm-addon-fit.min.js"] {
            assets[p] = try WebStaticResources.asset(for: p)
        }
        let server = WebServer(
            config: WebServer.Config(port: 0, allowedPaths: assets, zmxExecutable: zmx, zmxDir: zmxDir),
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

        let kill = Process()
        kill.executableURL = zmx
        kill.arguments = ["kill", "--force", sessionName]
        kill.environment = ["ZMX_DIR": zmxDir.path]
        try? kill.run()
        kill.waitUntilExit()
    }
}
