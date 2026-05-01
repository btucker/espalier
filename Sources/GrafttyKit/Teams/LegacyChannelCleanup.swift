import Foundation
import os

/// One-shot cleanup of the legacy `graftty-channel` MCP integration that
/// was retired in the channels-to-inbox migration. Runs idempotently on
/// every app launch for ~3 release versions; subsequently deleted.
public enum LegacyChannelCleanup {
    private static let logger = Logger(
        subsystem: "com.btucker.graftty",
        category: "LegacyChannelCleanup"
    )
    static let serverName = "graftty-channel"

    /// Run the three side-effecting cleanup steps in sequence (the
    /// `defaultCommand` scrub lives separately so the caller can present
    /// the resulting alert on the main actor). Logs failures, never
    /// throws.
    public static func run(executor: CLIExecutor = CLIRunner()) async {
        await unregisterMCPServer(executor: executor)
        removeLegacyMCPConfigFile(at: defaultLegacyMCPConfigPath())
        removeLegacyPluginDirectory(pluginsRoot: defaultLegacyPluginsRoot())
    }

    /// Best-effort `claude mcp remove graftty-channel`. Tolerates missing
    /// `claude` CLI and non-zero exit codes (e.g. server not registered).
    static func unregisterMCPServer(executor: CLIExecutor) async {
        do {
            _ = try await executor.capture(
                command: "claude",
                args: ["mcp", "remove", serverName],
                at: "/"
            )
        } catch {
            logger.info("legacy MCP unregister skipped: \(String(describing: error), privacy: .public)")
        }
    }

    /// `~/.claude/.mcp.json` — the hand-rolled MCP config the previous
    /// installer wrote. Claude Code never actually reads from this path,
    /// but it lingers on disk from prior versions.
    static func defaultLegacyMCPConfigPath() -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".claude").appendingPathComponent(".mcp.json")
    }

    /// `~/.claude/plugins/` — root for the plugin-shape installer used in
    /// even earlier versions.
    static func defaultLegacyPluginsRoot() -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".claude").appendingPathComponent("plugins")
    }

    /// Delete `~/.claude/.mcp.json` if and only if its contents are
    /// exactly `{ "mcpServers": { "graftty-channel": ... } }`. If the
    /// user has repurposed the file for any other server (or any other
    /// root key), leave it alone.
    static func removeLegacyMCPConfigFile(at path: URL) {
        guard FileManager.default.fileExists(atPath: path.path),
              let data = try? Data(contentsOf: path),
              let parsed = try? JSONSerialization.jsonObject(with: data),
              let root = parsed as? [String: Any],
              root.count == 1,
              let servers = root["mcpServers"] as? [String: Any],
              servers.count == 1,
              servers[serverName] != nil
        else { return }
        try? FileManager.default.removeItem(at: path)
    }

    /// Delete `~/.claude/plugins/graftty-channel/` if present. No-op
    /// when absent.
    static func removeLegacyPluginDirectory(pluginsRoot: URL) {
        let dir = pluginsRoot.appendingPathComponent("graftty-channel")
        if FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.removeItem(at: dir)
        }
    }
}
