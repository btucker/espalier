import ArgumentParser
import Foundation
import GrafttyKit

struct MCPChannel: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mcp-channel",
        abstract: "MCP channel bridge — invoked by Claude Code, not directly by humans."
    )

    func run() throws {
        // Resolve our worktree (fails cleanly if not inside a tracked one).
        let worktreePath: String
        do {
            worktreePath = try WorktreeResolver.resolve()
        } catch {
            emitOneShotError("Not inside a tracked Graftty worktree")
            throw ExitCode(1)
        }

        // Connect to Graftty's channels socket.
        let socketPath = SocketPathResolver.resolveChannels()
        let client: ChannelSocketClient
        do {
            client = try ChannelSocketClient.connect(path: socketPath)
        } catch {
            emitOneShotError("Graftty channel socket unreachable: \(error)")
            throw ExitCode(1)
        }

        // Subscribe so Graftty starts routing events for this worktree to us.
        do {
            try client.sendSubscribe(worktree: worktreePath)
        } catch {
            emitOneShotError("Failed to subscribe: \(error)")
            throw ExitCode(1)
        }

        // Stand up the MCP stdio server. Its output writes to real stdout.
        let stdout = FileHandle.standardOutput
        let mcp = MCPStdioServer(
            name: "graftty-channel",
            version: "0.1.0",
            instructions: """
            Events from this channel arrive as <channel source="graftty-channel" type="..."> \
            tags. Your operative behavioral guidance is delivered within the channel stream \
            as events with type="instructions"; the most recent such event's body supersedes \
            earlier ones. If no instructions event has arrived yet, act conservatively and wait.
            """,
            output: { stdout.write($0) }
        )

        // Socket → MCP pump in a background thread. On socket failure it emits
        // one channel_error MCP notification and exits the whole process.
        let socketThread = Thread {
            while true {
                do {
                    let message = try client.readServerMessage()
                    if case let .event(type, attrs, body) = message {
                        var meta = attrs
                        meta["type"] = type
                        mcp.emitChannelNotification(content: body, meta: meta)
                    }
                } catch {
                    mcp.emitChannelNotification(
                        content: "Graftty channel disconnected; exiting.",
                        meta: ["type": ChannelEventType.channelError]
                    )
                    Darwin.exit(0)
                }
            }
        }
        socketThread.start()

        // Stdin → MCP pump on the main thread. Blocks on FileHandle.availableData
        // until Claude Code writes (or closes our stdin on shutdown).
        let stdin = FileHandle.standardInput
        var buffer = Data()
        while true {
            let chunk = stdin.availableData
            if chunk.isEmpty { break }  // EOF — parent process closed stdin
            buffer.append(chunk)
            while let nl = buffer.firstIndex(of: 0x0A) {
                let line = String(data: buffer[..<nl], encoding: .utf8) ?? ""
                buffer.removeSubrange(...nl)
                mcp.handleLine(line)
            }
        }
    }

    /// Emit a one-shot channel_error notification and prepare to exit.
    private func emitOneShotError(_ text: String) {
        let mcp = MCPStdioServer(
            name: "graftty-channel", version: "0.1.0", instructions: "",
            output: { FileHandle.standardOutput.write($0) }
        )
        mcp.emitChannelNotification(
            content: text,
            meta: ["type": ChannelEventType.channelError]
        )
    }
}
