import Testing
import Foundation
@testable import EspalierKit

@Suite("TailscaleLocalAPI — parsing")
struct TailscaleLocalAPIParsingTests {

    private func fixture(_ name: String) throws -> Data {
        let url = try #require(
            Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"),
            "fixture \(name).json missing"
        )
        return try Data(contentsOf: url)
    }

    @Test func parseStatus_extractsOwnerAndIPs() throws {
        let data = try fixture("tailscale-status")
        let status = try TailscaleLocalAPI.parseStatus(data)
        #expect(status.loginName == "ben@example.com")
        #expect(status.tailscaleIPs.count == 2)
        #expect(status.tailscaleIPs.contains("100.64.0.5"))
        #expect(status.tailscaleIPs.contains("fd7a:115c:a1e0::5"))
    }

    @Test func parseWhois_ownerLoginName() throws {
        let data = try fixture("tailscale-whois-owner")
        let whois = try TailscaleLocalAPI.parseWhois(data)
        #expect(whois.loginName == "ben@example.com")
    }

    @Test func parseWhois_peerLoginName() throws {
        let data = try fixture("tailscale-whois-peer")
        let whois = try TailscaleLocalAPI.parseWhois(data)
        #expect(whois.loginName == "someone-else@example.com")
    }

    @Test func parseStatus_malformedReturnsNil() throws {
        let data = Data("{ not valid json".utf8)
        #expect(throws: DecodingError.self) {
            _ = try TailscaleLocalAPI.parseStatus(data)
        }
    }
}

@Suite("TailscaleLocalAPI — autoDetected transport selection")
struct TailscaleLocalAPIAutoDetectTests {

    private func makeTempDir() throws -> String {
        let dir = NSTemporaryDirectory() + "tsapi-" + UUID().uuidString
        try FileManager.default.createDirectory(
            atPath: dir, withIntermediateDirectories: true
        )
        return dir
    }

    @Test func prefersUnixSocketWhenPresent() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: tmp) }
        // A plain file at the candidate path is enough for the existence probe.
        let fakeSocket = tmp + "/tailscaled.socket"
        FileManager.default.createFile(atPath: fakeSocket, contents: nil)
        // A macsys layout present too; socket should still win.
        try "9999".write(toFile: tmp + "/ipnport", atomically: true, encoding: .utf8)
        try "secret".write(toFile: tmp + "/sameuserproof-9999", atomically: true, encoding: .utf8)

        let api = try TailscaleLocalAPI.autoDetected(
            socketPaths: [fakeSocket],
            macsysSupportDir: tmp
        )
        #expect(api.transport == .unixSocket(path: fakeSocket))
    }

    @Test func fallsBackToMacsysTCPWhenSocketsAbsent() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: tmp) }
        try "49161".write(toFile: tmp + "/ipnport", atomically: true, encoding: .utf8)
        try "token-abc-123".write(
            toFile: tmp + "/sameuserproof-49161", atomically: true, encoding: .utf8
        )

        let api = try TailscaleLocalAPI.autoDetected(
            socketPaths: ["/does/not/exist/tailscaled.socket"],
            macsysSupportDir: tmp
        )
        #expect(api.transport == .tcpLocalhost(port: 49161, authToken: "token-abc-123"))
    }

    @Test func readsPortFromIpnportSymlink() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: tmp) }
        // macsys writes ipnport as a symlink whose target is the port number.
        try FileManager.default.createSymbolicLink(
            atPath: tmp + "/ipnport", withDestinationPath: "49161"
        )
        try "token-xyz".write(
            toFile: tmp + "/sameuserproof-49161", atomically: true, encoding: .utf8
        )

        let api = try TailscaleLocalAPI.autoDetected(
            socketPaths: ["/does/not/exist/tailscaled.socket"],
            macsysSupportDir: tmp
        )
        #expect(api.transport == .tcpLocalhost(port: 49161, authToken: "token-xyz"))
    }

    @Test func trimsWhitespaceFromTokenAndPort() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: tmp) }
        try "  49161\n".write(toFile: tmp + "/ipnport", atomically: true, encoding: .utf8)
        try "token-xyz\n".write(
            toFile: tmp + "/sameuserproof-49161", atomically: true, encoding: .utf8
        )
        let api = try TailscaleLocalAPI.autoDetected(
            socketPaths: ["/does/not/exist/tailscaled.socket"],
            macsysSupportDir: tmp
        )
        #expect(api.transport == .tcpLocalhost(port: 49161, authToken: "token-xyz"))
    }

    @Test func throwsSocketUnreachableWhenNothingPresent() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: tmp) }
        #expect(throws: TailscaleLocalAPI.Error.socketUnreachable) {
            _ = try TailscaleLocalAPI.autoDetected(
                socketPaths: ["/does/not/exist/tailscaled.socket"],
                macsysSupportDir: tmp
            )
        }
    }

    @Test func missingTokenFileIsNotDetected() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: tmp) }
        try "49161".write(toFile: tmp + "/ipnport", atomically: true, encoding: .utf8)
        // Intentionally no sameuserproof-49161 file.
        #expect(throws: TailscaleLocalAPI.Error.socketUnreachable) {
            _ = try TailscaleLocalAPI.autoDetected(
                socketPaths: ["/does/not/exist/tailscaled.socket"],
                macsysSupportDir: tmp
            )
        }
    }

    @Test func emptyTokenIsNotDetected() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: tmp) }
        try "49161".write(toFile: tmp + "/ipnport", atomically: true, encoding: .utf8)
        try "   \n".write(
            toFile: tmp + "/sameuserproof-49161", atomically: true, encoding: .utf8
        )
        #expect(throws: TailscaleLocalAPI.Error.socketUnreachable) {
            _ = try TailscaleLocalAPI.autoDetected(
                socketPaths: ["/does/not/exist/tailscaled.socket"],
                macsysSupportDir: tmp
            )
        }
    }
}
