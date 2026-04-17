import Foundation
import Darwin

/// Per-WebSocket bridge between the client and a single `zmx attach`
/// child. Decoupled from NIO so `WebServer` owns the NIO plumbing
/// and `WebSession` stays testable over any byte-pipe.
///
/// The session spawns the child on init (`start()`), spawns a reader
/// thread that blocks on `read(masterFD)`, and exposes `write(_:)`
/// (for binary frames from the client) and `resize(cols:rows:)`
/// (for control frames). On `close()`, sends SIGTERM to the child
/// and closes the master fd.
public final class WebSession {

    public struct Config {
        public let zmxExecutable: URL
        public let zmxDir: URL
        public let sessionName: String
        public let baseEnv: [String: String]
        public init(zmxExecutable: URL, zmxDir: URL, sessionName: String, baseEnv: [String: String] = ProcessInfo.processInfo.environment) {
            self.zmxExecutable = zmxExecutable
            self.zmxDir = zmxDir
            self.sessionName = sessionName
            self.baseEnv = baseEnv
        }
    }

    public enum Error: Swift.Error {
        case notStarted
        case alreadyStarted
        case spawnFailed(Swift.Error)
    }

    /// Called on each chunk read from the PTY. Invoked off the caller's
    /// thread (from the reader thread). Caller is responsible for thread
    /// safety in the callback (e.g., dispatching onto NIO's event loop).
    public var onPTYData: ((Data) -> Void)?

    /// Called when the PTY reader observes EOF or an error, signaling
    /// that the zmx attach child exited (shell exit, session ended,
    /// or error). The caller should initiate WS close.
    public var onExit: (() -> Void)?

    private let config: Config
    private var spawned: PtyProcess.Spawned?
    private var readerThread: Thread?
    private let stateLock = NSLock()
    private var isClosed = false

    public init(config: Config) {
        self.config = config
    }

    public func start() throws {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard spawned == nil else { throw Error.alreadyStarted }

        var env = config.baseEnv
        env["ZMX_DIR"] = config.zmxDir.path

        let argv = [config.zmxExecutable.path, "attach", config.sessionName, "$SHELL"]
        do {
            spawned = try PtyProcess.spawn(argv: argv, env: env)
        } catch {
            throw Error.spawnFailed(error)
        }
        startReaderThread()
    }

    public func write(_ data: Data) {
        guard let fd = spawned?.masterFD, !data.isEmpty else { return }
        data.withUnsafeBytes { buf in
            guard let base = buf.baseAddress else { return }
            var offset = 0
            while offset < buf.count {
                let n = Darwin.write(fd, base.advanced(by: offset), buf.count - offset)
                if n < 0 { break }
                offset += n
            }
        }
    }

    public func resize(cols: UInt16, rows: UInt16) {
        guard let fd = spawned?.masterFD else { return }
        try? PtyProcess.resize(masterFD: fd, cols: cols, rows: rows)
    }

    public func close() {
        stateLock.lock()
        if isClosed { stateLock.unlock(); return }
        isClosed = true
        let spawned = self.spawned
        stateLock.unlock()

        if let spawned {
            _ = kill(spawned.pid, SIGTERM)
            // Brief wait, then force.
            var status: Int32 = 0
            for _ in 0..<10 {
                let rc = waitpid(spawned.pid, &status, WNOHANG)
                if rc != 0 { break }
                usleep(50_000)
            }
            _ = kill(spawned.pid, SIGKILL)
            _ = waitpid(spawned.pid, &status, 0)
            Darwin.close(spawned.masterFD)
        }
    }

    private func startReaderThread() {
        guard let fd = spawned?.masterFD else { return }
        let thread = Thread { [weak self] in
            var buf = [UInt8](repeating: 0, count: 8192)
            while true {
                let n = buf.withUnsafeMutableBufferPointer { Darwin.read(fd, $0.baseAddress, $0.count) }
                if n <= 0 { break }
                let chunk = Data(buf[0..<n])
                self?.onPTYData?(chunk)
            }
            self?.onExit?()
        }
        thread.name = "WebSession.reader(\(config.sessionName))"
        thread.start()
        readerThread = thread
    }
}
