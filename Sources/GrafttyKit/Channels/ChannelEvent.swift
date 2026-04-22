import Foundation

/// Messages sent BY channel subscribers (subprocess) TO the router.
public enum ChannelClientMessage: Codable, Equatable, Sendable {
    case subscribe(worktree: String, version: Int)

    private enum CodingKeys: String, CodingKey {
        case type, worktree, version
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .subscribe(worktree, version):
            try c.encode("subscribe", forKey: .type)
            try c.encode(worktree, forKey: .worktree)
            try c.encode(version, forKey: .version)
        }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(String.self, forKey: .type)
        switch type {
        case "subscribe":
            self = .subscribe(
                worktree: try c.decode(String.self, forKey: .worktree),
                version: try c.decode(Int.self, forKey: .version)
            )
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type, in: c,
                debugDescription: "Unknown ChannelClientMessage type: \(type)"
            )
        }
    }
}

/// Messages sent BY the router TO channel subscribers.
public enum ChannelServerMessage: Codable, Equatable, Sendable {
    case event(type: String, attrs: [String: String], body: String)

    private enum CodingKeys: String, CodingKey {
        case type, attrs, body
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .event(type, attrs, body):
            try c.encode(type, forKey: .type)
            try c.encode(attrs, forKey: .attrs)
            try c.encode(body, forKey: .body)
        }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(String.self, forKey: .type)
        let attrs = try c.decodeIfPresent([String: String].self, forKey: .attrs) ?? [:]
        let body = try c.decode(String.self, forKey: .body)
        self = .event(type: type, attrs: attrs, body: body)
    }
}

/// Well-known event type names. Constants rather than an enum so the router
/// and subprocess can round-trip unknown types (forward-compat for v2).
public enum ChannelEventType {
    public static let prStateChanged = "pr_state_changed"
    public static let ciConclusionChanged = "ci_conclusion_changed"
    public static let mergeStateChanged = "merge_state_changed"  // v2: requires merge-state polling in PRInfo
    public static let instructions = "instructions"
    public static let channelError = "channel_error"
}
