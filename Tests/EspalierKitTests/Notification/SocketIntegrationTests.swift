import Testing
import Foundation
@testable import EspalierKit

@Suite("Socket Integration Tests")
struct SocketIntegrationTests {
    @Test func serverReceivesMessage() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("espalier-sock-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let socketPath = dir.appendingPathComponent("test.sock").path
        let received = MutableBox<NotificationMessage?>(nil)

        let server = SocketServer(socketPath: socketPath)
        server.onMessage = { msg in received.value = msg }
        try server.start()
        try await Task.sleep(for: .milliseconds(100))

        // Connect as client
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        #expect(fd >= 0)
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        socketPath.withCString { ptr in
            withUnsafeMutablePointer(to: &addr.sun_path) { pathPtr in
                pathPtr.withMemoryRebound(to: CChar.self, capacity: 104) { dest in _ = strlcpy(dest, ptr, 104) }
            }
        }
        let connectResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in Darwin.connect(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        #expect(connectResult == 0)
        let msg = #"{"type":"notify","path":"/tmp/wt","text":"test"}"# + "\n"
        msg.withCString { ptr in _ = Darwin.write(fd, ptr, strlen(ptr)) }
        close(fd)

        try await Task.sleep(for: .milliseconds(200))
        server.stop()

        #expect(received.value != nil)
        if case .notify(let path, let text, _) = received.value {
            #expect(path == "/tmp/wt")
            #expect(text == "test")
        } else { Issue.record("Expected .notify message") }
    }
}

final class MutableBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: T
    init(_ value: T) { _value = value }
    var value: T {
        get { lock.withLock { _value } }
        set { lock.withLock { _value = newValue } }
    }
}
