import Testing
import Foundation
@testable import EspalierKit

@Suite("WebServer — auth gate")
struct WebServerAuthTests {

    private func resources() throws -> [String: WebStaticResources.Asset] {
        var out: [String: WebStaticResources.Asset] = [:]
        for path in ["/", "/xterm.min.js", "/xterm.min.css", "/xterm-addon-fit.min.js"] {
            out[path] = try WebStaticResources.asset(for: path)
        }
        return out
    }

    @Test func deniedRequestReturns403() async throws {
        let config = WebServer.Config(
            port: 0,  // ephemeral
            allowedPaths: try resources(),
            zmxExecutable: URL(fileURLWithPath: "/dev/null"),
            zmxDir: URL(fileURLWithPath: "/tmp")
        )
        let server = WebServer(
            config: config,
            auth: WebServer.AuthPolicy(isAllowed: { _ in false }),
            bindAddresses: ["127.0.0.1"]
        )
        try server.start()
        defer { server.stop() }
        guard case let .listening(_, port) = server.status else {
            Issue.record("server not listening"); return
        }
        let (_, response) = try await URLSession.shared.data(from: URL(string: "http://127.0.0.1:\(port)/")!)
        let http = response as! HTTPURLResponse
        #expect(http.statusCode == 403)
    }

    @Test func allowedRequestServesHTML() async throws {
        let config = WebServer.Config(
            port: 0,
            allowedPaths: try resources(),
            zmxExecutable: URL(fileURLWithPath: "/dev/null"),
            zmxDir: URL(fileURLWithPath: "/tmp")
        )
        let server = WebServer(
            config: config,
            auth: WebServer.AuthPolicy(isAllowed: { _ in true }),
            bindAddresses: ["127.0.0.1"]
        )
        try server.start()
        defer { server.stop() }
        guard case let .listening(_, port) = server.status else {
            Issue.record("server not listening"); return
        }
        let (data, response) = try await URLSession.shared.data(from: URL(string: "http://127.0.0.1:\(port)/")!)
        let http = response as! HTTPURLResponse
        #expect(http.statusCode == 200)
        #expect(http.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("text/html") == true)
        let html = String(data: data, encoding: .utf8) ?? ""
        #expect(html.contains("xterm.min.js"))
    }
}
