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

    // MARK: - Routable matrix events (TEAM-5.5, TEAM-5.6)

    /// Fans a routable `ChannelServerMessage.event(...)` out to one inbox row
    /// per recipient resolved by `TeamEventRouter`. No-ops for events outside
    /// the matrix (`team_message`, `team_member_*`, etc.) and for subject
    /// worktrees that aren't part of a team.
    public func dispatchRoutableEvent(
        _ event: ChannelServerMessage,
        subjectWorktreePath: String,
        repos: [RepoEntry]
    ) throws {
        guard case let .event(type, attrs, originalBody) = event else { return }
        guard let routable = RoutableEvent(channelEventType: type, attrs: attrs) else { return }
        guard let team = TeamLookup.team(for: subjectWorktreePath, in: repos) else { return }

        let recipients = TeamEventRouter.recipients(
            event: routable,
            subjectWorktreePath: subjectWorktreePath,
            repos: repos,
            preferences: preferencesProvider()
        )
        guard !recipients.isEmpty else { return }

        for recipientPath in recipients {
            let body = renderBody(
                type: type,
                attrs: attrs,
                originalBody: originalBody,
                recipientWorktreePath: recipientPath,
                subjectWorktreePath: subjectWorktreePath,
                repos: repos
            )
            let recipientMember = team.members.first(where: { $0.worktreePath == recipientPath })
            try inbox.appendMessage(
                teamID: TeamLookup.id(of: team),
                teamName: team.repoDisplayName,
                repoPath: team.repoPath,
                from: .system(repoPath: team.repoPath),
                to: TeamInboxEndpoint(
                    member: recipientMember?.name ?? "",
                    worktree: recipientPath,
                    runtime: nil
                ),
                priority: .normal,
                kind: type,
                body: body
            )
        }
    }

    // MARK: - Membership events (TEAM-5.7, TEAM-5.8)

    /// Writes one `team_member_joined` row addressed to the team lead.
    /// Same suppression rules as `TeamMembershipEvents.fireJoined`:
    /// - team has fewer than two worktrees
    /// - the joiner isn't found in the repo
    /// - the joiner *is* the lead (nobody else to notify)
    public func dispatchMemberJoined(
        joinerWorktreePath: String,
        repos: [RepoEntry]
    ) throws {
        guard let team = TeamLookup.team(for: joinerWorktreePath, in: repos) else { return }
        guard let joiner = team.members.first(where: { $0.worktreePath == joinerWorktreePath }) else { return }
        guard joiner.role != .lead else { return }

        let event = TeamChannelEvents.memberJoined(
            team: team.repoDisplayName,
            member: joiner.name,
            branch: joiner.branch,
            worktree: joiner.worktreePath
        )
        guard case let .event(type, attrs, originalBody) = event else { return }

        let lead = team.lead
        let body = renderBody(
            type: type,
            attrs: attrs,
            originalBody: originalBody,
            recipientWorktreePath: lead.worktreePath,
            subjectWorktreePath: joiner.worktreePath,
            repos: repos
        )
        try inbox.appendMessage(
            teamID: TeamLookup.id(of: team),
            teamName: team.repoDisplayName,
            repoPath: team.repoPath,
            from: .system(repoPath: team.repoPath),
            to: TeamInboxEndpoint(
                member: lead.name,
                worktree: lead.worktreePath,
                runtime: nil
            ),
            priority: .normal,
            kind: type,
            body: body
        )
    }

    /// Writes one `team_member_left` row addressed to the team lead.
    /// The team may have collapsed to one worktree by the time this is
    /// called (so `TeamLookup.team(for:)` returns nil) — we still emit
    /// the row, deriving the team ID from the repo path. Suppression
    /// rules match `TeamMembershipEvents.fireLeft`:
    /// - the lead is no longer present in the repo
    /// - the leaver was the lead itself
    public func dispatchMemberLeft(
        leaverBranch: String,
        leaverWorktreePath: String,
        reason: TeamChannelEvents.LeaveReason,
        repos: [RepoEntry]
    ) throws {
        // Find the repo by checking which one contains a worktree at the
        // leaver's repo root. The leaver is gone from the repo, so we
        // walk all repos and pick the one whose root path is a prefix of
        // the leaver's path (covers both `path == repo.path` and the
        // typical `<repo>/.worktrees/<name>` layout).
        guard let repo = repos.first(where: { repo in
            leaverWorktreePath == repo.path || leaverWorktreePath.hasPrefix(repo.path + "/")
        }) else { return }
        // Lead must still be present and the leaver must not have been the lead.
        guard repo.worktrees.contains(where: { $0.path == repo.path }) else { return }
        guard leaverWorktreePath != repo.path else { return }

        let leaverName = WorktreeNameSanitizer.sanitize(leaverBranch)
        let event = TeamChannelEvents.memberLeft(
            team: repo.displayName,
            member: leaverName,
            reason: reason
        )
        guard case let .event(type, attrs, originalBody) = event else { return }

        let body = renderBody(
            type: type,
            attrs: attrs,
            originalBody: originalBody,
            recipientWorktreePath: repo.path,
            subjectWorktreePath: leaverWorktreePath,
            repos: repos
        )
        try inbox.appendMessage(
            teamID: TeamLookup.id(forRepoPath: repo.path),
            teamName: repo.displayName,
            repoPath: repo.path,
            from: .system(repoPath: repo.path),
            to: TeamInboxEndpoint(
                member: WorktreeNameSanitizer.sanitize(
                    repo.worktrees.first(where: { $0.path == repo.path })?.branch ?? ""
                ),
                worktree: repo.path,
                runtime: nil
            ),
            priority: .normal,
            kind: type,
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
