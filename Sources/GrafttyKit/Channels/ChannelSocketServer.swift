import Foundation

/// Long-lived-connection Unix socket server for the channels transport.
/// Each connection is expected to send one `ChannelClientMessage.subscribe`
/// line, then stays open for server-pushed `ChannelServerMessage` events.
public final class ChannelSocketServer: @unchecked Sendable {
    public final class Connection: @unchecked Sendable {
        fileprivate let fd: Int32
        public internal(set) var worktree: String = ""

        fileprivate init(fd: Int32) {
            self.fd = fd
        }

        public func write(_ message: ChannelServerMessage) throws {
            let data = try JSONEncoder().encode(message)
            var payload = data
            payload.append(0x0A)  // newline
            try payload.withUnsafeBytes { buf in
                guard let base = buf.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
                try SocketIO.writeAll(fd: fd, bytes: base, count: buf.count)
            }
        }

        fileprivate func close_() {
            Darwin.close(fd)
        }
    }

    private let socketPath: String
    private var listenFD: Int32 = -1
    private var source: DispatchSourceRead?
    private let queue = DispatchQueue(label: "com.graftty.channels-server", attributes: .concurrent)
    private let connLock = NSLock()
    private var connections: [ObjectIdentifier: Connection] = [:]

    public var onSubscribe: ((ChannelClientMessage, Connection) -> Void)?
    public var onDisconnect: ((Connection) -> Void)?

    public init(socketPath: String) { self.socketPath = socketPath }
    deinit { stop() }

    public func start() throws {
        let pathBytes = socketPath.utf8.count
        guard pathBytes <= SocketServer.maxPathBytes else {
            throw SocketServerError.socketPathTooLong(bytes: pathBytes, maxBytes: SocketServer.maxPathBytes)
        }
        unlink(socketPath)
        listenFD = socket(AF_UNIX, SOCK_STREAM, 0)
        guard listenFD >= 0 else { throw SocketServerError.socketCreationFailed }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        socketPath.withCString { ptr in
            withUnsafeMutablePointer(to: &addr.sun_path) { pathPtr in
                pathPtr.withMemoryRebound(to: CChar.self, capacity: 104) { _ = strlcpy($0, ptr, 104) }
            }
        }
        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(listenFD, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard bindResult == 0 else { close(listenFD); throw SocketServerError.bindFailed(errno: errno) }
        guard Darwin.listen(listenFD, 64) == 0 else { close(listenFD); throw SocketServerError.listenFailed(errno: errno) }

        let src = DispatchSource.makeReadSource(fileDescriptor: listenFD, queue: queue)
        src.setEventHandler { [weak self] in self?.accept() }
        src.setCancelHandler { [weak self] in if let fd = self?.listenFD, fd >= 0 { close(fd) } }
        src.resume()
        self.source = src
    }

    public func stop() {
        source?.cancel(); source = nil
        connLock.lock()
        for conn in connections.values { conn.close_() }
        connections.removeAll()
        connLock.unlock()
        if listenFD >= 0 { close(listenFD); listenFD = -1 }
        unlink(socketPath)
    }

    public func allConnections() -> [Connection] {
        connLock.lock(); defer { connLock.unlock() }
        return Array(connections.values)
    }

    private func accept() {
        let clientFD = Darwin.accept(listenFD, nil, nil)
        guard clientFD >= 0 else { return }
        let conn = Connection(fd: clientFD)
        connLock.lock(); connections[ObjectIdentifier(conn)] = conn; connLock.unlock()
        queue.async { [weak self] in self?.handle(conn) }
    }

    private func handle(_ conn: Connection) {
        defer {
            conn.close_()
            connLock.lock()
            connections.removeValue(forKey: ObjectIdentifier(conn))
            connLock.unlock()
            if let cb = onDisconnect {
                DispatchQueue.main.async { cb(conn) }
            }
        }

        guard let firstLine = readLine(fd: conn.fd) else { return }
        guard let data = firstLine.data(using: .utf8),
              let message = try? JSONDecoder().decode(ChannelClientMessage.self, from: data) else {
            return
        }
        if case let .subscribe(worktree, _) = message {
            conn.worktree = worktree
        }
        if let cb = onSubscribe {
            DispatchQueue.main.async { cb(message, conn) }
        }

        // Keep the connection open until the peer closes.
        var buf = [UInt8](repeating: 0, count: 256)
        while true {
            let n = Darwin.read(conn.fd, &buf, buf.count)
            if n <= 0 { return }
        }
    }

    private func readLine(fd: Int32) -> String? {
        var line = Data()
        var ch: UInt8 = 0
        while true {
            let n = Darwin.read(fd, &ch, 1)
            if n <= 0 { return line.isEmpty ? nil : String(data: line, encoding: .utf8) }
            if ch == 0x0A { return String(data: line, encoding: .utf8) }
            line.append(ch)
        }
    }
}
