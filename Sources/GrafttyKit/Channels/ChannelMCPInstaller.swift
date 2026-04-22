import Foundation

/// Installs the `graftty-channel` MCP server into the user-scope
/// `~/.claude/.mcp.json`. The server is addressed at launch time as
/// `--dangerously-load-development-channels server:graftty-channel` — the
/// `server:` form (vs. `plugin:<name>@<marketplace>`) is what Claude Code
/// accepts for manually-configured MCP servers, and avoids the local-
/// marketplace registration that the plugin-wrapper shape would require.
///
/// Pure JSON merge: preserves any other `mcpServers` entries the user has
/// configured, and overwrites only the `graftty-channel` key. If the
/// target file exists but is unparseable JSON, the install is skipped
/// rather than clobbering the user's config — a malformed file is almost
/// certainly a user edit mid-flight, and a silent overwrite would lose
/// their work.
public enum ChannelMCPInstaller {
    public static let serverName = "graftty-channel"
    public static let mcpArgs: [String] = ["mcp-channel"]

    public enum Error: Swift.Error, Equatable {
        /// The target `.mcp.json` exists but its contents are not valid
        /// JSON. Caller should log and skip rather than overwrite.
        case existingFileUnparseable(String)
        /// The existing file parses as JSON but its `mcpServers` key is
        /// present and is not an object (e.g. the user wrote `"mcpServers":
        /// "oops"`). Same reasoning — we refuse to overwrite.
        case mcpServersNotAnObject
    }

    /// Merge the `graftty-channel` server entry into `mcpConfigPath`.
    /// Creates the parent directory and the file if either is missing.
    /// Idempotent — calling twice with the same `cliPath` leaves the file
    /// byte-identical to a single call.
    ///
    /// - Parameters:
    ///   - mcpConfigPath: Absolute path to the target `.mcp.json` (typically
    ///     `~/.claude/.mcp.json`).
    ///   - cliPath: Absolute path to the `graftty` CLI binary.
    public static func install(mcpConfigPath: URL, cliPath: String) throws {
        let parent = mcpConfigPath.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)

        var root: [String: Any] = [:]
        if FileManager.default.fileExists(atPath: mcpConfigPath.path) {
            let data = try Data(contentsOf: mcpConfigPath)
            if !data.isEmpty {
                guard let parsed = try? JSONSerialization.jsonObject(with: data),
                      let obj = parsed as? [String: Any] else {
                    let raw = String(data: data, encoding: .utf8) ?? "<binary>"
                    throw Error.existingFileUnparseable(raw)
                }
                root = obj
            }
        }

        var servers: [String: Any]
        if let existing = root["mcpServers"] {
            guard let asObject = existing as? [String: Any] else {
                throw Error.mcpServersNotAnObject
            }
            servers = asObject
        } else {
            servers = [:]
        }

        servers[serverName] = [
            "command": cliPath,
            "args": mcpArgs,
        ]
        root["mcpServers"] = servers

        let data = try JSONSerialization.data(
            withJSONObject: root,
            options: [.prettyPrinted, .sortedKeys]
        )
        try data.write(to: mcpConfigPath, options: .atomic)
    }

    /// Remove any leftover `~/.claude/plugins/graftty-channel/` directory
    /// from prior versions that installed a plugin wrapper. Safe to call
    /// every launch — if the directory doesn't exist, this is a no-op.
    public static func removeLegacyPluginDirectory(pluginsRoot: URL) {
        let dir = pluginsRoot.appendingPathComponent("graftty-channel")
        if FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.removeItem(at: dir)
        }
    }

    /// Default target: `~/.claude/.mcp.json`.
    public static func defaultMCPConfigPath() -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".claude").appendingPathComponent(".mcp.json")
    }

    /// Default legacy plugin root: `~/.claude/plugins/`.
    public static func defaultLegacyPluginsRoot() -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".claude").appendingPathComponent("plugins")
    }
}
