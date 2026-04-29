import Darwin
import Foundation

public enum SSHLocalForwardError: Error, Equatable {
    case sshExited(Int32)
    case localPortUnavailable
}

public struct SSHLocalForwardCommand: Sendable, Equatable {
    public static func arguments(config: SSHHostConfig, localPort: Int) -> [String] {
        var args = [
            "-N",
            "-L", "127.0.0.1:\(localPort):127.0.0.1:\(config.remoteGrafttyPort)",
            "-o", "ExitOnForwardFailure=yes",
            "-o", "ServerAliveInterval=30"
        ]
        if config.sshPort != 22 {
            args += ["-p", "\(config.sshPort)"]
        }
        let destination = config.sshUsername.map { "\($0)@\(config.sshHost)" } ?? config.sshHost
        args.append(destination)
        return args
    }

    public static func shellCommand(config: SSHHostConfig, localPort: Int) -> String {
        (["ssh"] + arguments(config: config, localPort: localPort))
            .map(shellQuoted)
            .joined(separator: " ")
    }

    private static func shellQuoted(_ value: String) -> String {
        guard value.rangeOfCharacter(from: .whitespacesAndNewlines) != nil else {
            return value
        }
        return "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}

public enum LocalPortAllocator {
    public static func ephemeralLoopbackPort() throws -> Int {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { throw SSHLocalForwardError.localPortUnavailable }
        defer { close(fd) }

        var reuse = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(0).bigEndian
        addr.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

        let bindResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else { throw SSHLocalForwardError.localPortUnavailable }

        var bound = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let nameResult = withUnsafeMutablePointer(to: &bound) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(fd, $0, &length)
            }
        }
        guard nameResult == 0 else { throw SSHLocalForwardError.localPortUnavailable }
        return Int(UInt16(bigEndian: bound.sin_port))
    }
}

public protocol SSHLocalForwardProcess: Sendable {
    var localPort: Int { get }
    func stop()
}

public protocol SSHLocalForwarding: Sendable {
    func start(config: SSHHostConfig) async throws -> any SSHLocalForwardProcess
}

public final class SystemSSHLocalForwarder: SSHLocalForwarding, @unchecked Sendable {
    public init() {}

    public func start(config: SSHHostConfig) async throws -> any SSHLocalForwardProcess {
        let port = try LocalPortAllocator.ephemeralLoopbackPort()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        process.arguments = SSHLocalForwardCommand.arguments(config: config, localPort: port)
        try process.run()
        try await Task.sleep(nanoseconds: 250_000_000)
        if !process.isRunning {
            throw SSHLocalForwardError.sshExited(process.terminationStatus)
        }
        return RunningSystemSSHLocalForward(process: process, localPort: port)
    }
}

public final class RunningSystemSSHLocalForward: SSHLocalForwardProcess, @unchecked Sendable {
    private let process: Process
    public let localPort: Int

    init(process: Process, localPort: Int) {
        self.process = process
        self.localPort = localPort
    }

    public func stop() {
        guard process.isRunning else { return }
        process.terminate()
    }
}
