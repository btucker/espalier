import Testing
import Foundation
import Darwin
@testable import EspalierKit

@Suite("PtyProcess — PTY allocation + fork/exec")
struct PtyProcessTests {

    @Test func spawns_childEchoAndExit() throws {
        let spawn = try PtyProcess.spawn(
            argv: ["/bin/sh", "-c", "printf hello; exit 0"],
            env: [:]
        )
        defer { close(spawn.masterFD) }

        // Read until EOF or "hello".
        var collected = Data()
        var buf = [UInt8](repeating: 0, count: 256)
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            let n = buf.withUnsafeMutableBufferPointer { Darwin.read(spawn.masterFD, $0.baseAddress, $0.count) }
            if n <= 0 { break }
            collected.append(contentsOf: buf[0..<n])
            if String(data: collected, encoding: .utf8)?.contains("hello") == true { break }
        }
        #expect(String(data: collected, encoding: .utf8)?.contains("hello") == true)

        // Reap.
        var status: Int32 = 0
        _ = waitpid(spawn.pid, &status, 0)
    }

    @Test func childHasControllingTerminal() throws {
        // `tty -s` exits 0 iff stdin is a terminal. If our PTY setup is
        // correct, the child should report success.
        let spawn = try PtyProcess.spawn(
            argv: ["/usr/bin/tty", "-s"],
            env: [:]
        )
        defer { close(spawn.masterFD) }
        var status: Int32 = 0
        _ = waitpid(spawn.pid, &status, 0)
        let exitCode = (status >> 8) & 0xFF
        #expect(exitCode == 0)
    }

    @Test func resize_ioctlAppliesDimensions() throws {
        let spawn = try PtyProcess.spawn(
            argv: ["/bin/sh", "-c", "stty size; exit 0"],
            env: [:]
        )
        defer { close(spawn.masterFD) }
        try PtyProcess.resize(masterFD: spawn.masterFD, cols: 42, rows: 13)

        var collected = Data()
        var buf = [UInt8](repeating: 0, count: 256)
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            let n = buf.withUnsafeMutableBufferPointer { Darwin.read(spawn.masterFD, $0.baseAddress, $0.count) }
            if n <= 0 { break }
            collected.append(contentsOf: buf[0..<n])
            if String(data: collected, encoding: .utf8)?.contains("13 42") == true { break }
        }
        var status: Int32 = 0
        _ = waitpid(spawn.pid, &status, 0)
        #expect(String(data: collected, encoding: .utf8)?.contains("13 42") == true)
    }
}
