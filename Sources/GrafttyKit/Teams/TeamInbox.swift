import Foundation

public enum TeamInboxPriority: String, Codable, Sendable, Equatable {
    case normal
    case urgent
}

public struct TeamInboxEndpoint: Codable, Sendable, Equatable, Hashable {
    public let member: String
    public let worktree: String
    public let runtime: String?

    public init(member: String, worktree: String, runtime: String?) {
        self.member = member
        self.worktree = worktree
        self.runtime = runtime
    }
}

public struct TeamInboxMessage: Codable, Sendable, Equatable {
    public let id: String
    public let batchID: String?
    public let createdAt: Date
    public let team: String
    public let repoPath: String
    public let from: TeamInboxEndpoint
    public let to: TeamInboxEndpoint
    public let priority: TeamInboxPriority
    public let kind: String
    public let body: String

    enum CodingKeys: String, CodingKey {
        case id
        case batchID = "batch_id"
        case createdAt = "created_at"
        case team
        case repoPath = "repo_path"
        case from, to, priority, kind, body
    }

    public init(
        id: String,
        batchID: String?,
        createdAt: Date,
        team: String,
        repoPath: String,
        from: TeamInboxEndpoint,
        to: TeamInboxEndpoint,
        priority: TeamInboxPriority,
        kind: String = "team_message",
        body: String
    ) {
        self.id = id
        self.batchID = batchID
        self.createdAt = createdAt
        self.team = team
        self.repoPath = repoPath
        self.from = from
        self.to = to
        self.priority = priority
        self.kind = kind
        self.body = body
    }
}

public struct TeamInboxCursor: Codable, Sendable, Equatable {
    public let sessionID: String
    public let worktree: String
    public let runtime: String
    public let lastSeenID: String?

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case worktree
        case runtime
        case lastSeenID = "last_seen_id"
    }

    public init(sessionID: String, worktree: String, runtime: String, lastSeenID: String?) {
        self.sessionID = sessionID
        self.worktree = worktree
        self.runtime = runtime
        self.lastSeenID = lastSeenID
    }
}

public struct TeamInboxWorktreeWatermark: Codable, Sendable, Equatable {
    public let worktree: String
    public let lastDeliveredToAnySessionID: String?

    enum CodingKeys: String, CodingKey {
        case worktree
        case lastDeliveredToAnySessionID = "last_delivered_to_any_session_id"
    }

    public init(worktree: String, lastDeliveredToAnySessionID: String?) {
        self.worktree = worktree
        self.lastDeliveredToAnySessionID = lastDeliveredToAnySessionID
    }
}

public final class TeamInbox {
    private let rootDirectory: URL
    private let idGenerator: () -> String
    private let now: () -> Date
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(
        rootDirectory: URL,
        idGenerator: @escaping () -> String = TeamInbox.defaultID,
        now: @escaping () -> Date = { Date() }
    ) {
        self.rootDirectory = rootDirectory
        self.idGenerator = idGenerator
        self.now = now
        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
    }

    @discardableResult
    public func appendMessage(
        teamID: String,
        teamName: String,
        repoPath: String,
        from: TeamInboxEndpoint,
        to: TeamInboxEndpoint,
        priority: TeamInboxPriority,
        body: String
    ) throws -> TeamInboxMessage {
        let message = TeamInboxMessage(
            id: idGenerator(),
            batchID: nil,
            createdAt: now(),
            team: teamName,
            repoPath: repoPath,
            from: from,
            to: to,
            priority: priority,
            body: body
        )
        try append(message, teamID: teamID)
        return message
    }

    @discardableResult
    public func appendBroadcast(
        teamID: String,
        teamName: String,
        repoPath: String,
        from: TeamInboxEndpoint,
        recipients: [TeamInboxEndpoint],
        priority: TeamInboxPriority,
        body: String
    ) throws -> [TeamInboxMessage] {
        let batchID = idGenerator()
        let messages = recipients.map { recipient in
            TeamInboxMessage(
                id: idGenerator(),
                batchID: batchID,
                createdAt: now(),
                team: teamName,
                repoPath: repoPath,
                from: from,
                to: recipient,
                priority: priority,
                body: body
            )
        }
        for message in messages {
            try append(message, teamID: teamID)
        }
        return messages
    }

    public func messages(teamID: String) throws -> [TeamInboxMessage] {
        let url = messagesURL(teamID: teamID)
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let text = try String(contentsOf: url, encoding: .utf8)
        return text.split(separator: "\n").compactMap { line in
            guard let data = String(line).data(using: .utf8) else { return nil }
            return try? decoder.decode(TeamInboxMessage.self, from: data)
        }
    }

    public func unreadMessages(
        teamID: String,
        recipientWorktree: String,
        after lastSeenID: String?,
        priorities: Set<TeamInboxPriority>? = nil
    ) throws -> [TeamInboxMessage] {
        try messages(teamID: teamID).filter { message in
            guard message.to.worktree == recipientWorktree else { return false }
            if let lastSeenID, message.id <= lastSeenID { return false }
            if let priorities, !priorities.contains(message.priority) { return false }
            return true
        }
    }

    public func writeCursor(_ cursor: TeamInboxCursor, teamID: String) throws {
        let url = cursorURL(teamID: teamID, sessionID: cursor.sessionID)
        try ensureParentDirectory(for: url)
        let data = try encoder.encode(cursor)
        try data.write(to: url, options: .atomic)
    }

    public func cursor(teamID: String, sessionID: String) throws -> TeamInboxCursor? {
        let url = cursorURL(teamID: teamID, sessionID: sessionID)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        return try decoder.decode(TeamInboxCursor.self, from: data)
    }

    public func writeWorktreeWatermark(
        _ watermark: TeamInboxWorktreeWatermark,
        teamID: String
    ) throws {
        let url = watermarkURL(teamID: teamID, worktree: watermark.worktree)
        try ensureParentDirectory(for: url)
        let data = try encoder.encode(watermark)
        try data.write(to: url, options: .atomic)
    }

    public func worktreeWatermark(
        teamID: String,
        worktree: String
    ) throws -> TeamInboxWorktreeWatermark? {
        let url = watermarkURL(teamID: teamID, worktree: worktree)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        return try decoder.decode(TeamInboxWorktreeWatermark.self, from: data)
    }

    private func append(_ message: TeamInboxMessage, teamID: String) throws {
        let url = messagesURL(teamID: teamID)
        try ensureParentDirectory(for: url)
        let data = try encoder.encode(message)
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
        try handle.write(contentsOf: Data([0x0A]))
    }

    private func messagesURL(teamID: String) -> URL {
        teamDirectory(teamID: teamID).appendingPathComponent("messages.jsonl")
    }

    private func cursorURL(teamID: String, sessionID: String) -> URL {
        teamDirectory(teamID: teamID)
            .appendingPathComponent("cursors", isDirectory: true)
            .appendingPathComponent(Self.fileComponent(sessionID) + ".json")
    }

    private func watermarkURL(teamID: String, worktree: String) -> URL {
        teamDirectory(teamID: teamID)
            .appendingPathComponent("worktrees", isDirectory: true)
            .appendingPathComponent(Self.fileComponent(worktree) + ".json")
    }

    private func teamDirectory(teamID: String) -> URL {
        rootDirectory.appendingPathComponent(Self.fileComponent(teamID), isDirectory: true)
    }

    private func ensureParentDirectory(for url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
    }

    private static func fileComponent(_ raw: String) -> String {
        var result = ""
        for scalar in raw.unicodeScalars {
            switch scalar {
            case "A"..."Z", "a"..."z", "0"..."9", ".", "_", "-":
                result.unicodeScalars.append(scalar)
            default:
                result.append("_")
            }
        }
        return result.isEmpty ? "_" : result
    }

    public static func defaultID() -> String {
        let micros = Int64(Date().timeIntervalSince1970 * 1_000_000)
        return "\(String(format: "%016lld", micros))-\(UUID().uuidString)"
    }
}
