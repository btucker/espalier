import Foundation

/// Composes the shareable URL used in the "Copy web URL" action.
/// No statefulness; pure transformation from (host, port, session).
public enum WebURLComposer {

    /// Compose the URL. Bracket-notation for IPv6 hosts; percent-encode
    /// the session name.
    public static func url(session: String, host: String, port: Int) -> String {
        let encodedSession = session.addingPercentEncoding(
            withAllowedCharacters: .urlQueryAllowed.subtracting(
                CharacterSet(charactersIn: " ")
            )
        ) ?? session
        return "\(baseURL(host: host, port: port))session/\(encodedSession)"
    }

    /// Compose the server's root URL (no session). Bracket-notation for
    /// IPv6 hosts so the Settings-pane display + sidebar "Copy web URL"
    /// don't emit malformed URIs on IPv6-only Tailscale setups. WEB-1.7.
    public static func baseURL(host: String, port: Int) -> String {
        let hostPart = host.contains(":") ? "[\(host)]" : host
        return "http://\(hostPart):\(port)/"
    }

    /// Prefer the first IPv4 address; fall back to the first IPv6 only
    /// if no IPv4 is present. `nil` when the input is empty or every
    /// entry is blank. Whitespace-only / empty entries are defensively
    /// skipped; surrounding whitespace on otherwise-valid entries is
    /// trimmed — protects against a Tailscale LocalAPI hiccup that
    /// would otherwise propagate to a malformed `http://:8799/`.
    public static func chooseHost(from ips: [String]) -> String? {
        let cleaned = ips
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if let v4 = cleaned.first(where: { !$0.contains(":") }) { return v4 }
        return cleaned.first
    }
}
