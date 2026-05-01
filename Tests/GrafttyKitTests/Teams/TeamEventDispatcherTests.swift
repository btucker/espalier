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
}
