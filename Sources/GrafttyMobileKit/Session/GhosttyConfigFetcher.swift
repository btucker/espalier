#if canImport(UIKit)
import Foundation

/// Pulls the Mac server's resolved Ghostty config text from
/// `GET <baseURL>/ghostty-config` so TerminalController can render with
/// the same fonts/colors as the desktop app.
public enum GhosttyConfigFetcher {

    public static func fetch(
        baseURL: URL,
        session: URLSession = .shared
    ) async -> String? {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        let base = components?.path ?? ""
        components?.path = base.hasSuffix("/") ? base + "ghostty-config" : base + "/ghostty-config"
        guard let url = components?.url else { return nil }

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("text/plain", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await session.data(for: req)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return nil
            }
            let text = String(decoding: data, as: UTF8.self)
            return text.isEmpty ? nil : text
        } catch {
            return nil
        }
    }
}
#endif
