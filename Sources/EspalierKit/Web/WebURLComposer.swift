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
    /// if no IPv4 is present. `nil` when the input is empty.
    public static func chooseHost(from ips: [String]) -> String? {
        if let v4 = ips.first(where: { !$0.contains(":") }) { return v4 }
        return ips.first
    }
}
