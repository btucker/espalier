import Foundation
import Darwin

/// Loop-and-retry write helper for file descriptors: loops on partial
/// writes, retries on EINTR, throws on other errors.
public enum SocketIO {

    public enum WriteError: Error, Equatable {
        case writeFailed(errno: Int32)
    }

    public static func writeAll(
        fd: Int32,
        bytes: UnsafePointer<UInt8>,
        count: Int
    ) throws {
        var offset = 0
        while offset < count {
            let n = Darwin.write(fd, bytes.advanced(by: offset), count - offset)
            if n < 0 {
                if errno == EINTR { continue }
                throw WriteError.writeFailed(errno: errno)
            }
            if n == 0 {
                // Zero without an error is unusual on sockets, but
                // treat as EPIPE-equivalent rather than spinning
                // indefinitely.
                throw WriteError.writeFailed(errno: EPIPE)
            }
            offset += n
        }
    }

    /// Convenience wrapper that writes the UTF-8 bytes of a `String`
    /// (without a trailing terminator).
    public static func writeAll(fd: Int32, string: String) throws {
        let bytes = Array(string.utf8)
        try bytes.withUnsafeBufferPointer { buf in
            guard let base = buf.baseAddress else { return }
            try writeAll(fd: fd, bytes: base, count: buf.count)
        }
    }
}
