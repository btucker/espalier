import Foundation
import Darwin

/// Swift's Darwin overlay marks `fork()` as `unavailable` with a message
/// steering callers toward `posix_spawn`. That's the right default advice,
/// but here we deliberately need a real `fork` so the child can `setsid`,
/// `ioctl(TIOCSCTTY)`, and become the controlling process of the PTY
/// before it `execve`s. Bind directly to the C symbol.
@_silgen_name("fork") private func _fork() -> pid_t

/// Open a PTY pair, fork, and exec a program with the PTY slave as
/// its controlling terminal and as fd 0/1/2. The parent retains the
/// master fd; the caller reads/writes it directly.
///
/// This is the narrow complement to Phase 1's `ZmxRunner`. `ZmxRunner`
/// is for short-lived subprocesses that communicate over pipes
/// (`kill`, `list`). `PtyProcess` is for long-lived subprocesses that
/// need a real TTY (`zmx attach`).
///
/// Not a class — the result struct carries everything needed to
/// interact with the child. The caller is responsible for closing
/// the master fd and reaping the child (`waitpid`).
public enum PtyProcess {

    public struct Spawned {
        public let masterFD: Int32
        public let pid: pid_t
    }

    public enum Error: Swift.Error {
        case openptFailed(errno: Int32)
        case grantptFailed(errno: Int32)
        case unlockptFailed(errno: Int32)
        case ptsnameFailed
        case forkFailed(errno: Int32)
        case execFailed(errno: Int32)
    }

    /// Spawn `argv[0]` with `argv[1...]` as arguments and `env` as
    /// the environment. The child's stdin/stdout/stderr are the PTY
    /// slave; the master fd is returned for the parent to use.
    ///
    /// `initialSize` (optional) applies a starting winsize to the PTY
    /// *before* the child execs, so the child's first `TIOCGWINSZ`
    /// read sees it. `zmx attach` uses that initial size to populate
    /// its `Init` IPC; if callers want deterministic startup sizing
    /// (tests, or propagating the host-side known viewport), pass it
    /// here rather than race an initial TIOCSWINSZ against the child's
    /// startup path. On macOS the ioctl is applied after the parent
    /// has opened the slave — winsize storage is slave-backed and
    /// returns ENOTTY until at least one slave open has occurred.
    public static func spawn(
        argv: [String],
        env: [String: String],
        initialSize: (cols: UInt16, rows: UInt16)? = nil
    ) throws -> Spawned {
        precondition(!argv.isEmpty, "argv must not be empty")

        let master = posix_openpt(O_RDWR | O_NOCTTY)
        if master < 0 { throw Error.openptFailed(errno: errno) }

        if grantpt(master) != 0 {
            let err = errno
            close(master)
            throw Error.grantptFailed(errno: err)
        }
        if unlockpt(master) != 0 {
            let err = errno
            close(master)
            throw Error.unlockptFailed(errno: err)
        }

        guard let slaveNameCStr = ptsname(master) else {
            close(master)
            throw Error.ptsnameFailed
        }
        let slavePath = String(cString: slaveNameCStr)

        // Keep the parent's slave fd open across fork. On macOS, when the
        // slave ref count crosses zero the PTY enters an EOF state on the
        // master, and subsequent reads return -1/EIO even after the child
        // opens a fresh slave fd. Holding one fd here until after fork
        // avoids that zero-crossing.
        let parentSlaveFD = Darwin.open(slavePath, O_RDWR | O_NOCTTY)
        if parentSlaveFD < 0 {
            close(master)
            throw Error.ptsnameFailed
        }

        if let size = initialSize {
            var ws = winsize(
                ws_row: size.rows,
                ws_col: size.cols,
                ws_xpixel: 0,
                ws_ypixel: 0
            )
            _ = ioctl(master, UInt(TIOCSWINSZ), &ws)
        }

        // After fork the child inherits and execs; the C strings' lifetime
        // is owned by the parent until the child's execve replaces its
        // address space (or execve fails, in which case the child _exits).
        let argvCStrings = argv.map { strdup($0) }
        var argvPointers: [UnsafeMutablePointer<CChar>?] = argvCStrings + [nil]

        let mergedEnv = env.isEmpty ? ProcessInfo.processInfo.environment : env
        let envStrings = mergedEnv.map { "\($0)=\($1)" }
        let envCStrings = envStrings.map { strdup($0) }
        var envPointers: [UnsafeMutablePointer<CChar>?] = envCStrings + [nil]

        let pid = _fork()
        if pid < 0 {
            let err = errno
            close(parentSlaveFD)
            close(master)
            for ptr in argvCStrings { free(ptr) }
            for ptr in envCStrings { free(ptr) }
            throw Error.forkFailed(errno: err)
        }
        if pid == 0 {
            _ = setsid()
            let slave = Darwin.open(slavePath, O_RDWR)
            if slave < 0 { _exit(127) }
            // Non-fatal on some kernels; continue regardless of rc.
            _ = ioctl(slave, UInt(TIOCSCTTY), 0)
            _ = dup2(slave, 0)
            _ = dup2(slave, 1)
            _ = dup2(slave, 2)
            if slave > 2 { close(slave) }
            close(master)
            // Close every OTHER inherited fd before execve. Without this,
            // any parent-opened file or socket without FD_CLOEXEC leaks
            // into the zmx child, which still holds them after Graftty
            // quits. Observed live: the `WebServer` listen socket leaked
            // into zmx-attach children, so after Graftty died the port
            // stayed bound to an orphan zmx process and the next Graftty
            // launch couldn't rebind.
            //
            // `getdtablesize()` returns the per-process fd table ceiling
            // (currently open OR available) — NOT `RLIMIT_NOFILE.rlim_cur`
            // which can be `RLIM_INFINITY` (effectively Int32.max → 2-billion
            // close() calls, which hung our tests indefinitely on the first
            // attempt). The dtable size is typically ≤10k, closing 3..that
            // is a few ms of syscalls.
            let maxFd = getdtablesize()
            var fd: Int32 = 3
            while fd < maxFd {
                close(fd)
                fd += 1
            }
            // Launch via posix_spawn with POSIX_SPAWN_SETEXEC +
            // POSIX_SPAWN_SETSIGMASK (+ signal-defaults) instead of
            // `execve`. The setsigmask guarantees the child process
            // starts with an *empty* signal mask — a plain execve
            // carries the forked parent's mask across, and when that
            // parent is a Swift app the mask typically has signals
            // blocked that GCD/Dispatch intercepts on its service
            // threads. `zmx attach` relies on SIGWINCH delivery to
            // learn about PTY resizes; with the mask left in place the
            // kernel sets SIGWINCH pending but never delivers it to
            // zmx's handler, so the resize never propagates (see
            // `Tests/GrafttyKitTests/Zmx/ZmxResizePropagationTests`).
            //
            // Why posix_spawn and not `sigprocmask(SIG_SETMASK, empty)`
            // directly: the explicit sigprocmask-in-fork-child approach
            // was attempted and the tests continued to fail — the mask
            // reset didn't take effect in the exec'd image for reasons
            // that look like libsystem-internal state leaking through.
            // POSIX_SPAWN_SETSIGMASK is the kernel-level, documented
            // way to pin the new image's initial mask.
            //
            // POSIX_SPAWN_SETEXEC makes this call replace the current
            // process image (like execve) rather than fork+exec. We
            // needed our own fork above for `setsid()` + `TIOCSCTTY`,
            // since those aren't expressible via spawnattr_t.
            var spawnAttrs: posix_spawnattr_t?
            guard posix_spawnattr_init(&spawnAttrs) == 0 else { _exit(127) }
            defer { posix_spawnattr_destroy(&spawnAttrs) }

            var emptyMask = sigset_t()
            sigemptyset(&emptyMask)
            var allMask = sigset_t()
            sigfillset(&allMask)
            _ = posix_spawnattr_setsigmask(&spawnAttrs, &emptyMask)
            // Also defensively request SIG_DFL for every signal — this
            // guards against any inherited `SIG_IGN` action that might
            // carry over despite execve's action-reset semantics.
            _ = posix_spawnattr_setsigdefault(&spawnAttrs, &allMask)
            _ = posix_spawnattr_setflags(
                &spawnAttrs,
                Int16(POSIX_SPAWN_SETEXEC | POSIX_SPAWN_SETSIGMASK | POSIX_SPAWN_SETSIGDEF)
            )

            var spawnedPid: pid_t = 0
            _ = argvPointers.withUnsafeMutableBufferPointer { argvBuf in
                envPointers.withUnsafeMutableBufferPointer { envBuf in
                    posix_spawn(
                        &spawnedPid,
                        argvBuf.baseAddress![0],
                        nil,
                        &spawnAttrs,
                        argvBuf.baseAddress,
                        envBuf.baseAddress
                    )
                }
            }
            // POSIX_SPAWN_SETEXEC means posix_spawn only returns on
            // failure — success replaces the image and we never get
            // here. So reaching this point is a spawn failure.
            _exit(127)
        }

        close(parentSlaveFD)
        for ptr in argvCStrings { free(ptr) }
        for ptr in envCStrings { free(ptr) }
        return Spawned(masterFD: master, pid: pid)
    }

    /// Apply a terminal size change to the PTY. The shell on the slave
    /// side will receive SIGWINCH.
    public static func resize(masterFD: Int32, cols: UInt16, rows: UInt16) throws {
        var ws = winsize(ws_row: rows, ws_col: cols, ws_xpixel: 0, ws_ypixel: 0)
        let rc = ioctl(masterFD, UInt(TIOCSWINSZ), &ws)
        if rc != 0 {
            throw Error.execFailed(errno: errno)  // repurposing; cleaner to add a dedicated case if this becomes common
        }
    }
}
