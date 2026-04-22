import Foundation
import NIOSSL

/// Lock-guarded box around the live `NIOSSLContext`. The per-channel
/// initializer in `WebServer` reads `current()` on each new inbound
/// connection; the cert-renewal scheduler calls `swap(_:)` when
/// Tailscale hands back freshly-renewed PEM bytes. Swaps do not touch
/// connections already past the handshake — NIO's TLS handler holds
/// its own context reference for the life of the connection. WEB-8.3.
public final class WebTLSContextProvider: @unchecked Sendable {
    private let lock = NSLock()
    private var context: NIOSSLContext

    public init(initial: NIOSSLContext) {
        self.context = initial
    }

    public func current() -> NIOSSLContext {
        lock.lock()
        defer { lock.unlock() }
        return context
    }

    public func swap(_ new: NIOSSLContext) {
        lock.lock()
        context = new
        lock.unlock()
    }
}
