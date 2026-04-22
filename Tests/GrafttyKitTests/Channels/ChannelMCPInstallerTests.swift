import XCTest
@testable import GrafttyKit

final class ChannelMCPInstallerTests: XCTestCase {
    private func makeTempDir() -> URL {
        let tmp = URL(fileURLWithPath: "/tmp/GrafttyChannelMCPTest-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        return tmp
    }

    private func readJSON(_ url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        let parsed = try JSONSerialization.jsonObject(with: data)
        return parsed as? [String: Any] ?? [:]
    }

    func testInstallCreatesFileWithServerEntry() throws {
        let tmp = makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let target = tmp.appendingPathComponent(".claude/.mcp.json")

        try ChannelMCPInstaller.install(mcpConfigPath: target, cliPath: "/opt/graftty")

        let root = try readJSON(target)
        let servers = try XCTUnwrap(root["mcpServers"] as? [String: Any])
        let entry = try XCTUnwrap(servers["graftty-channel"] as? [String: Any])
        XCTAssertEqual(entry["command"] as? String, "/opt/graftty")
        XCTAssertEqual(entry["args"] as? [String], ["mcp-channel"])
    }

    func testInstallIsIdempotent() throws {
        let tmp = makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let target = tmp.appendingPathComponent(".claude/.mcp.json")

        try ChannelMCPInstaller.install(mcpConfigPath: target, cliPath: "/opt/graftty")
        let first = try Data(contentsOf: target)
        try ChannelMCPInstaller.install(mcpConfigPath: target, cliPath: "/opt/graftty")
        let second = try Data(contentsOf: target)

        XCTAssertEqual(first, second)
    }

    func testInstallOverwritesOnCliPathChange() throws {
        let tmp = makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let target = tmp.appendingPathComponent(".claude/.mcp.json")

        try ChannelMCPInstaller.install(mcpConfigPath: target, cliPath: "/old/graftty")
        try ChannelMCPInstaller.install(mcpConfigPath: target, cliPath: "/new/graftty")

        let root = try readJSON(target)
        let servers = try XCTUnwrap(root["mcpServers"] as? [String: Any])
        let entry = try XCTUnwrap(servers["graftty-channel"] as? [String: Any])
        XCTAssertEqual(entry["command"] as? String, "/new/graftty")
    }

    func testInstallPreservesOtherServers() throws {
        let tmp = makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let target = tmp.appendingPathComponent(".claude/.mcp.json")
        try FileManager.default.createDirectory(
            at: target.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let existing: [String: Any] = [
            "mcpServers": [
                "other-tool": ["command": "/opt/other", "args": ["serve"]],
            ],
            "unrelatedKey": "keep-me",
        ]
        let existingData = try JSONSerialization.data(withJSONObject: existing)
        try existingData.write(to: target)

        try ChannelMCPInstaller.install(mcpConfigPath: target, cliPath: "/opt/graftty")

        let root = try readJSON(target)
        XCTAssertEqual(root["unrelatedKey"] as? String, "keep-me")
        let servers = try XCTUnwrap(root["mcpServers"] as? [String: Any])
        XCTAssertNotNil(servers["graftty-channel"])
        let other = try XCTUnwrap(servers["other-tool"] as? [String: Any])
        XCTAssertEqual(other["command"] as? String, "/opt/other")
    }

    func testInstallThrowsOnUnparseableExistingFile() throws {
        let tmp = makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let target = tmp.appendingPathComponent(".claude/.mcp.json")
        try FileManager.default.createDirectory(
            at: target.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "not json at all".write(to: target, atomically: true, encoding: .utf8)

        XCTAssertThrowsError(
            try ChannelMCPInstaller.install(mcpConfigPath: target, cliPath: "/opt/graftty")
        ) { error in
            guard case ChannelMCPInstaller.Error.existingFileUnparseable = error else {
                XCTFail("expected existingFileUnparseable, got \(error)")
                return
            }
        }
        // Preserve the user's file byte-for-byte when we refuse.
        let still = try String(contentsOf: target, encoding: .utf8)
        XCTAssertEqual(still, "not json at all")
    }

    func testInstallThrowsWhenMcpServersIsNotAnObject() throws {
        let tmp = makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let target = tmp.appendingPathComponent(".claude/.mcp.json")
        try FileManager.default.createDirectory(
            at: target.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let bad: [String: Any] = ["mcpServers": "oops"]
        let data = try JSONSerialization.data(withJSONObject: bad)
        try data.write(to: target)

        XCTAssertThrowsError(
            try ChannelMCPInstaller.install(mcpConfigPath: target, cliPath: "/opt/graftty")
        ) { error in
            XCTAssertEqual(error as? ChannelMCPInstaller.Error, .mcpServersNotAnObject)
        }
    }

    func testRemoveLegacyPluginDirectoryRemovesItWhenPresent() throws {
        let tmp = makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let pluginsRoot = tmp.appendingPathComponent("plugins")
        let dir = pluginsRoot.appendingPathComponent("graftty-channel")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try "{}".write(
            to: dir.appendingPathComponent("plugin.json"),
            atomically: true, encoding: .utf8
        )

        ChannelMCPInstaller.removeLegacyPluginDirectory(pluginsRoot: pluginsRoot)

        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.path))
    }

    func testRemoveLegacyPluginDirectoryIsNoOpWhenAbsent() {
        let tmp = makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }
        // Should not throw; nothing to assert beyond "no crash / exception".
        ChannelMCPInstaller.removeLegacyPluginDirectory(
            pluginsRoot: tmp.appendingPathComponent("nonexistent")
        )
    }
}
