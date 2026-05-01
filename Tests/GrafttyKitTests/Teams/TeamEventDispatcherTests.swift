import Foundation
import Testing
@testable import GrafttyKit

@Suite("TeamEventDispatcher")
struct TeamEventDispatcherTests {
    static func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("teamEventDispatcherTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("@spec TEAM-5.1: When team_message is dispatched, the application shall append exactly one inbox row addressed to the named recipient.")
    func teamMessageWritesOneRowToRecipient() throws {
        let root = try Self.temporaryDirectory()
        let repo = TeamTestFixtures.makeRepo(path: "/repo", displayName: "repo", branches: ["main", "alice"])
        let inbox = TeamInbox(rootDirectory: root)
        let dispatcher = TeamEventDispatcher(
            inbox: inbox,
            preferencesProvider: { TeamEventRoutingPreferences() },
            templateProvider: { "" }
        )

        try dispatcher.dispatchTeamMessage(
            from: "alice",
            to: "main",
            text: "ping",
            priority: .normal,
            repos: [repo],
            teamsEnabled: true
        )

        let team = TeamLookup.team(for: "/repo/.worktrees/alice", in: [repo])!
        let messages = try inbox.messages(teamID: TeamLookup.id(of: team))
        #expect(messages.count == 1)
        #expect(messages.first?.from.member == "alice")
        #expect(messages.first?.to.member == "main")
        #expect(messages.first?.body == "ping")
        #expect(messages.first?.kind == "team_message")
    }

    @Test("@spec TEAM-5.5: When PRStatusStore fires pr_state_changed (non-merged), the dispatcher shall write one inbox row per recipient resolved via the prStateChanged matrix row.")
    func prStateChangedFansOutPerMatrix() throws {
        let root = try Self.temporaryDirectory()
        let repo = TeamTestFixtures.makeRepo(path: "/repo", displayName: "repo", branches: ["main", "alice", "bob"])
        let inbox = TeamInbox(rootDirectory: root)
        let prefs = TeamEventRoutingPreferences(
            prStateChanged: [.worktree, .otherWorktrees],
            prMerged: [.root],
            ciConclusionChanged: [.worktree],
            mergabilityChanged: [.worktree]
        )
        let dispatcher = TeamEventDispatcher(
            inbox: inbox,
            preferencesProvider: { prefs },
            templateProvider: { "" }
        )

        let event = ChannelServerMessage.event(
            type: ChannelEventType.prStateChanged,
            attrs: ["worktree": "/repo/.worktrees/alice", "to": "open", "from": "draft", "pr_number": "42", "pr_url": "https://x", "provider": "github", "repo": "x/y"],
            body: "PR #42 state changed: draft → open"
        )

        try dispatcher.dispatchRoutableEvent(
            event,
            subjectWorktreePath: "/repo/.worktrees/alice",
            repos: [repo]
        )

        let team = TeamLookup.team(for: "/repo/.worktrees/alice", in: [repo])!
        let messages = try inbox.messages(teamID: TeamLookup.id(of: team))
        #expect(messages.count == 2)
        let recipientPaths = Set(messages.map { $0.to.worktree })
        #expect(recipientPaths == ["/repo/.worktrees/alice", "/repo/.worktrees/bob"])
        #expect(messages.allSatisfy { $0.kind == "pr_state_changed" })
        #expect(messages.allSatisfy { $0.from.member == "system" })
    }

    @Test("@spec TEAM-5.6: When pr_state_changed has attrs.to == 'merged', the dispatcher shall use the prMerged matrix row.")
    func prMergedUsesMergedRow() throws {
        let root = try Self.temporaryDirectory()
        let repo = TeamTestFixtures.makeRepo(path: "/repo", displayName: "repo", branches: ["main", "alice"])
        let inbox = TeamInbox(rootDirectory: root)
        let prefs = TeamEventRoutingPreferences(
            prStateChanged: [],
            prMerged: [.root],
            ciConclusionChanged: [],
            mergabilityChanged: []
        )
        let dispatcher = TeamEventDispatcher(
            inbox: inbox,
            preferencesProvider: { prefs },
            templateProvider: { "" }
        )

        let event = ChannelServerMessage.event(
            type: ChannelEventType.prStateChanged,
            attrs: ["worktree": "/repo/.worktrees/alice", "to": "merged", "from": "open", "pr_number": "42", "pr_url": "https://x", "provider": "github", "repo": "x/y"],
            body: "PR #42 state changed: open → merged"
        )

        try dispatcher.dispatchRoutableEvent(
            event,
            subjectWorktreePath: "/repo/.worktrees/alice",
            repos: [repo]
        )

        let team = TeamLookup.team(for: "/repo/.worktrees/alice", in: [repo])!
        let messages = try inbox.messages(teamID: TeamLookup.id(of: team))
        #expect(messages.count == 1)
        #expect(messages.first?.to.worktree == "/repo")
    }
}
