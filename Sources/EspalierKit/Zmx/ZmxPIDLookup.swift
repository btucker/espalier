import Foundation

/// Resolves the PID of the inner shell running inside a zmx session by
/// reading the daemon's log file.
///
/// Backing the `PWD-1.3` fallback: when Ghostty's zsh shell integration
/// doesn't load inside a zmx session (pre-`ZMX-6.3` sessions, non-zsh
/// shells, user `.zshrc` that overrides chpwd, …), OSC 7 never fires
/// and Espalier has no way to track cwd changes from the shell side.
/// The zmx daemon writes one line per spawn of the form
///
///     [<ts>] [info] (default): pty spawned session=<name> pid=<N>
///
/// to `<ZMX_DIR>/logs/<session>.log`. Taking the last such line gives
/// us the currently-living shell PID, which Espalier then polls via
/// `proc_pidinfo` to detect cwd changes.
public enum ZmxPIDLookup {

    /// Parse an in-memory log string and return the most recent shell
    /// PID for `sessionName`. Returns nil if the log contains no
    /// matching `pty spawned … pid=<N>` line, or if the pid value
    /// can't be parsed as a positive 32-bit int.
    public static func shellPID(
        fromLogContents contents: String,
        sessionName: String
    ) -> Int32? {
        // Walk lines in reverse so we can bail on the first match
        // (the *most recent* spawn wins). Splitting is cheap — these
        // logs stay under a few MB in practice.
        for line in contents.split(separator: "\n", omittingEmptySubsequences: true).reversed() {
            guard line.contains("pty spawned"),
                  line.contains("session=\(sessionName)")
            else { continue }
            guard let pid = parsePID(from: line) else { continue }
            return pid
        }
        return nil
    }

    /// Same as `shellPID(fromLogContents:)` but reads the log from
    /// disk. Returns nil if the file is missing or unreadable — the
    /// caller treats that as "unknown PID, skip this poll."
    public static func shellPID(logFile: URL, sessionName: String) -> Int32? {
        guard let contents = try? String(contentsOf: logFile, encoding: .utf8) else {
            return nil
        }
        return shellPID(fromLogContents: contents, sessionName: sessionName)
    }

    /// Extract the integer after `pid=` on a log line. Returns nil
    /// if the marker is absent or the value isn't a positive int32.
    private static func parsePID<S: StringProtocol>(from line: S) -> Int32? {
        guard let range = line.range(of: "pid=") else { return nil }
        // The pid is whitespace-terminated (or end-of-line). Slice
        // everything after `pid=` and take the leading digit run.
        let tail = line[range.upperBound...]
        let digits = tail.prefix(while: \.isNumber)
        guard !digits.isEmpty, let value = Int32(digits) else { return nil }
        return value
    }
}
