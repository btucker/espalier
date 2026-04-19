import Foundation

/// Banner line prepended to a rebuilt pane's `initial_input` so the
/// user sees a marker that the underlying zmx session was replaced
/// (ZMX-7.3).
///
/// Uses `printf` (not `echo -e`) because its behavior is identical
/// across bash, zsh, and fish. The timestamp is embedded as a
/// Swift-formatted literal — `$(date …)` substitution syntax differs
/// across those shells, so we avoid it entirely.
public func sessionRestartBanner(at date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm"
    let stamp = formatter.string(from: date)
    return "printf '\\n\\033[2m— session restarted at \(stamp) —\\033[0m\\n'\n"
}
