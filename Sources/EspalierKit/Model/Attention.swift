import Foundation

public struct Attention: Codable, Sendable, Equatable {
    public let text: String
    public let timestamp: Date
    public let clearAfter: TimeInterval?

    public init(text: String, timestamp: Date, clearAfter: TimeInterval? = nil) {
        self.text = text
        self.timestamp = timestamp
        self.clearAfter = clearAfter
    }

    /// Whether `text` is acceptable as the body of an attention overlay.
    /// Mirrors `NotifyInputValidation.emptyText` so the server can refuse
    /// empty / whitespace-only text from non-CLI socket clients
    /// (raw `nc -U`, the web surface, custom scripts), keeping the
    /// ATTN-1.7 contract from slipping past the CLI's front door.
    public static func isValidText(_ text: String) -> Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
