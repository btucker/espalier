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

    /// Upper bound for `clearAfter` on the server side. Mirrors
    /// `NotifyInputValidation.clearAfterMaxSeconds` (Int). Expressed as
    /// `TimeInterval` for ergonomics at the DispatchQueue site.
    public static let clearAfterMaxSeconds: TimeInterval = 86_400

    /// Normalizes a requested `clearAfter` to what the server actually
    /// schedules:
    /// - nil or ≤0 → nil (STATE-2.8: no auto-clear timer)
    /// - in (0, max] → pass through unchanged
    /// - > max → clamped to `clearAfterMaxSeconds` (STATE-2.9): a
    ///   runaway value from a non-CLI socket client can't leak a
    ///   multi-year Dispatch work item into the main queue.
    public static func effectiveClearAfter(_ clearAfter: TimeInterval?) -> TimeInterval? {
        guard let c = clearAfter, c > 0 else { return nil }
        return min(c, clearAfterMaxSeconds)
    }
}
