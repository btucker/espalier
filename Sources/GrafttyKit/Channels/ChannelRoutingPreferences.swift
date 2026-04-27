import Foundation

/// Set of recipient classes for a single matrix row, encoded as bit flags so
/// each row's value is one of 0–7 (any combination of root / worktree / others).
public struct RecipientSet: OptionSet, Codable, Equatable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    /// The repo's root worktree (the team's lead).
    public static let root           = RecipientSet(rawValue: 1 << 0)
    /// The worktree the event is *about*.
    public static let worktree       = RecipientSet(rawValue: 1 << 1)
    /// All other coworkers in the same repo.
    public static let otherWorktrees = RecipientSet(rawValue: 1 << 2)
}

/// User-configurable routing matrix for the four routable channel events
/// (TEAM-1.8). Each field is a `RecipientSet` controlling which recipient
/// classes the corresponding event type fans out to.
public struct ChannelRoutingPreferences: Codable, Equatable, Sendable {
    public var prStateChanged: RecipientSet
    public var prMerged: RecipientSet
    public var ciConclusionChanged: RecipientSet
    public var mergabilityChanged: RecipientSet

    public init(
        prStateChanged: RecipientSet = .worktree,
        prMerged: RecipientSet = .root,
        ciConclusionChanged: RecipientSet = .worktree,
        mergabilityChanged: RecipientSet = .worktree
    ) {
        self.prStateChanged = prStateChanged
        self.prMerged = prMerged
        self.ciConclusionChanged = ciConclusionChanged
        self.mergabilityChanged = mergabilityChanged
    }
}

// MARK: - @AppStorage adapter

/// `@AppStorage` accepts `RawRepresentable` whose raw type is `String`, `Int`,
/// etc. This adapter wraps the JSON encoding so the struct can be persisted
/// directly: `@AppStorage("channelRoutingPreferences") var prefs = ChannelRoutingPreferences()`.
extension ChannelRoutingPreferences: RawRepresentable {
    public init?(rawValue: String) {
        guard let data = rawValue.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(ChannelRoutingPreferences.self, from: data)
        else { return nil }
        self = decoded
    }

    public var rawValue: String {
        guard let data = try? JSONEncoder().encode(self),
              let string = String(data: data, encoding: .utf8)
        else { return "{}" }
        return string
    }
}
