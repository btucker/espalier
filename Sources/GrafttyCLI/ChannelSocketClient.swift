import Foundation
import GrafttyKit

/// Client-side of the channels socket, used by `graftty mcp-channel`.
/// Blocking reads and writes; one line at a time.
final class ChannelSocketClient {
    private let fd: Int32
    private init(fd: Int32) { self.fd = fd }

    static func connect(path: String) throws -> ChannelSocketClient {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw CLIError.socketError("socket() failed") }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        path.withCString { ptr in
            withUnsafeMutablePointer(to: &addr.sun_path) { p in
                p.withMemoryRebound(to: CChar.self, capacity: 104) {
                    _ = strlcpy($0, ptr, 104)
                }
            }
        }
        let res = withUnsafePointer(to: &addr) { p in
            p.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        if res != 0 {
            close(fd)
            throw CLIError.appNotRunning
        }
        return ChannelSocketClient(fd: fd)
    }

    func sendSubscribe(worktree: String) throws {
        let msg = ChannelClientMessage.subscribe(worktree: worktree, version: 1)
        var data = try JSONEncoder().encode(msg)
        data.append(0x0A)
        try data.withUnsafeBytes { buf in
            guard let base = buf.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
            try SocketIO.writeAll(fd: fd, bytes: base, count: buf.count)
        }
    }

    /// Read one newline-delimited JSON message from the socket. Blocks.
    /// Throws on EOF or decode failure.
    func readServerMessage() throws -> ChannelServerMessage {
        var line = Data()
        var ch: UInt8 = 0
        while true {
            let n = Darwin.read(fd, &ch, 1)
            if n <= 0 { throw CLIError.socketError("channel socket EOF") }
            if ch == 0x0A { break }
            line.append(ch)
        }
        return try JSONDecoder().decode(ChannelServerMessage.self, from: line)
    }

    deinit { if fd >= 0 { close(fd) } }
}
