import XCTest
@testable import GrafttyKit

final class ChannelSocketServerTests: XCTestCase {
    var socketPath: String!

    override func setUp() {
        super.setUp()
        socketPath = "/tmp/graftty-test-channels-\(UUID().uuidString).sock"
    }

    override func tearDown() {
        unlink(socketPath)
        super.tearDown()
    }

    func testSubscribeDeliversSubscribeMessageToHandler() throws {
        let server = ChannelSocketServer(socketPath: socketPath)
        let expectation = self.expectation(description: "subscribe received")
        server.onSubscribe = { message, _ in
            if case let .subscribe(worktree, _) = message {
                XCTAssertEqual(worktree, "/wt/a")
                expectation.fulfill()
            }
        }
        try server.start()
        defer { server.stop() }

        let client = try ChannelTestClient.connect(path: socketPath)
        try client.send(#"{"type":"subscribe","worktree":"/wt/a","version":1}\#n"#)

        wait(for: [expectation], timeout: 2.0)
    }

    func testServerPushEventReachesClient() throws {
        let server = ChannelSocketServer(socketPath: socketPath)
        var capturedConn: ChannelSocketServer.Connection?
        let subscribed = self.expectation(description: "subscribed")
        server.onSubscribe = { _, conn in
            capturedConn = conn
            subscribed.fulfill()
        }
        try server.start()
        defer { server.stop() }

        let client = try ChannelTestClient.connect(path: socketPath)
        try client.send(#"{"type":"subscribe","worktree":"/wt/a","version":1}\#n"#)
        wait(for: [subscribed], timeout: 2.0)

        let event = ChannelServerMessage.event(type: "ping", attrs: [:], body: "hi")
        try capturedConn?.write(event)

        let received = try client.readLine(timeout: 2.0)
        XCTAssertTrue(received.contains("\"type\":\"ping\""))
    }

    func testClientDisconnectRemovesConnection() throws {
        let server = ChannelSocketServer(socketPath: socketPath)
        let subscribed = self.expectation(description: "subscribed")
        let disconnected = self.expectation(description: "disconnected")
        server.onSubscribe = { _, _ in subscribed.fulfill() }
        server.onDisconnect = { _ in disconnected.fulfill() }
        try server.start()
        defer { server.stop() }

        var client: ChannelTestClient? = try ChannelTestClient.connect(path: socketPath)
        try client!.send(#"{"type":"subscribe","worktree":"/wt/a","version":1}\#n"#)
        wait(for: [subscribed], timeout: 2.0)

        client = nil  // drop the client — underlying fd closed by deinit
        wait(for: [disconnected], timeout: 2.0)
    }
}

/// Minimal Unix-socket test client for channel tests only.
final class ChannelTestClient {
    private let fd: Int32
    private init(fd: Int32) { self.fd = fd }
    deinit { close(fd) }

    static func connect(path: String) throws -> ChannelTestClient {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
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
        if res != 0 { close(fd); throw NSError(domain: "ChannelTestClient", code: Int(errno)) }
        return ChannelTestClient(fd: fd)
    }

    func send(_ line: String) throws {
        try line.withCString { ptr in
            let len = strlen(ptr)
            let written = Darwin.write(fd, ptr, len)
            if written != len {
                throw NSError(domain: "ChannelTestClient", code: Int(errno))
            }
        }
    }

    func readLine(timeout: TimeInterval) throws -> String {
        var tv = timeval(tv_sec: Int(timeout), tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        var buf = [UInt8](repeating: 0, count: 4096)
        let n = Darwin.read(fd, &buf, buf.count)
        if n <= 0 { throw NSError(domain: "ChannelTestClient", code: Int(errno)) }
        return String(decoding: buf[0..<n], as: UTF8.self)
    }
}
