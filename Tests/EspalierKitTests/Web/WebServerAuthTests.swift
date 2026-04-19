import Testing
import Foundation
@testable import EspalierKit

@Suite("WebServer — auth gate")
struct WebServerAuthTests {

    private static func makeConfig(port: Int = 0) -> WebServer.Config {
        WebServer.Config(
            port: port,
            zmxExecutable: URL(fileURLWithPath: "/dev/null"),
            zmxDir: URL(fileURLWithPath: "/tmp")
        )
    }

    @Test func deniedRequestReturns403() async throws {
        let server = WebServer(
            config: Self.makeConfig(),
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
        let server = WebServer(
            config: Self.makeConfig(),
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
        #expect(html.contains("<div id=\"root\">"))
    }

    @Test func spaFallbackServesIndexForUnknownPath() async throws {
        let server = WebServer(
            config: Self.makeConfig(),
            auth: WebServer.AuthPolicy(isAllowed: { _ in true }),
            bindAddresses: ["127.0.0.1"]
        )
        try server.start()
        defer { server.stop() }
        guard case let .listening(_, port) = server.status else {
            Issue.record("server not listening"); return
        }
        let (data, response) = try await URLSession.shared.data(
            from: URL(string: "http://127.0.0.1:\(port)/session/whatever")!
        )
        let http = response as! HTTPURLResponse
        #expect(http.statusCode == 200)
        #expect(http.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("text/html") == true)
        let body = String(data: data, encoding: .utf8) ?? ""
        #expect(body.contains("<div id=\"root\">"), "SPA fallback should serve index.html body")
    }

    @Test func wsPathReturns404WithoutUpgradeHeader() async throws {
        let server = WebServer(
            config: Self.makeConfig(),
            auth: WebServer.AuthPolicy(isAllowed: { _ in true }),
            bindAddresses: ["127.0.0.1"]
        )
        try server.start()
        defer { server.stop() }
        guard case let .listening(_, port) = server.status else {
            Issue.record("server not listening"); return
        }
        let (_, response) = try await URLSession.shared.data(
            from: URL(string: "http://127.0.0.1:\(port)/ws")!
        )
        let http = response as! HTTPURLResponse
        #expect(http.statusCode == 404, "/ws without Upgrade must NOT fall through to index.html")
    }

    @Test func servesAppJS() async throws {
        let server = WebServer(
            config: Self.makeConfig(),
            auth: WebServer.AuthPolicy(isAllowed: { _ in true }),
            bindAddresses: ["127.0.0.1"]
        )
        try server.start()
        defer { server.stop() }
        guard case let .listening(_, port) = server.status else {
            Issue.record("server not listening"); return
        }
        let (data, response) = try await URLSession.shared.data(
            from: URL(string: "http://127.0.0.1:\(port)/app.js")!
        )
        let http = response as! HTTPURLResponse
        #expect(http.statusCode == 200)
        #expect(http.value(forHTTPHeaderField: "Content-Type") == "application/javascript; charset=utf-8")
        #expect(data.count > 100)
    }
}
