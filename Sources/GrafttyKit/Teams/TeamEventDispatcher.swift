import Foundation
import GrafttyProtocol

/// Phase 1 of the channels-to-inbox migration: writes routable team events
/// (`team_message`, PR/CI matrix events, membership join/leave) directly to
/// `TeamInbox` instead of going through the legacy channel router.
///
/// The dispatcher is purely additive in Phase 1 — no producer is wired to
/// it yet. Phase 2 wires producers; Phase 4 retires the channel router.
public final class TeamEventDispatcher {
    private let inbox: TeamInbox
    private let preferencesProvider: () -> TeamEventRoutingPreferences
    private let templateProvider: () -> String

    public init(
        inbox: TeamInbox,
        preferencesProvider: @escaping () -> TeamEventRoutingPreferences,
        templateProvider: @escaping () -> String
    ) {
        self.inbox = inbox
        self.preferencesProvider = preferencesProvider
        self.templateProvider = templateProvider
    }

    // MARK: - team_message (TEAM-5.1)

    /// Writes a single `team_message` row addressed to the named recipient.
    /// No-ops (silently) when teams are disabled, the sender's worktree is
    /// not in a team, or the recipient is not a teammate.
    @discardableResult
    public func dispatchTeamMessage(
        from sender: String,
        to recipient: String,
        text: String,
        priority: TeamInboxPriority,
        repos: [RepoEntry],
        teamsEnabled: Bool
    ) throws -> TeamInboxMessage? {
        guard teamsEnabled else { return nil }
        guard let senderMember = TeamLookup.member(named: sender, in: repos) else { return nil }
        guard let team = TeamLookup.team(for: senderMember.worktreePath, in: repos) else { return nil }
        guard let recipientMember = team.memberNamed(recipient) else { return nil }

        let body = renderBody(
            type: TeamChannelEvents.EventType.message,
            attrs: ["team": team.repoDisplayName, "from": sender],
            originalBody: text,
            recipientWorktreePath: recipientMember.worktreePath,
            subjectWorktreePath: senderMember.worktreePath,
            repos: repos
        )

        return try inbox.appendMessage(
            teamID: TeamLookup.id(of: team),
            teamName: team.repoDisplayName,
            repoPath: team.repoPath,
            from: TeamInboxEndpoint(
                member: senderMember.name,
                worktree: senderMember.worktreePath,
                runtime: nil
            ),
            to: TeamInboxEndpoint(
                member: recipientMember.name,
                worktree: recipientMember.worktreePath,
                runtime: nil
            ),
            priority: priority,
            kind: TeamChannelEvents.EventType.message,
            body: body
        )
    }

    // MARK: - Body rendering

    /// Renders the user's `teamPrompt` template against the per-recipient
    /// agent context. When the template is empty the original body is
    /// returned unchanged, matching the legacy channel-path behavior.
    private func renderBody(
        type: String,
        attrs: [String: String],
        originalBody: String,
        recipientWorktreePath: String,
        subjectWorktreePath: String?,
        repos: [RepoEntry]
    ) -> String {
        let template = templateProvider()
        guard !template.isEmpty else { return originalBody }
        let synthetic = ChannelServerMessage.event(type: type, attrs: attrs, body: originalBody)
        let rendered = EventBodyRenderer.body(
            for: synthetic,
            recipientWorktreePath: recipientWorktreePath,
            subjectWorktreePath: subjectWorktreePath,
            repos: repos,
            templateString: template
        )
        if case let .event(_, _, body) = rendered { return body }
        return originalBody
    }
}
