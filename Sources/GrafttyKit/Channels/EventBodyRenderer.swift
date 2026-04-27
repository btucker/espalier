import Foundation
import os
import Stencil

/// Renders the user's `teamPrompt` Stencil template against the per-delivery
/// `agent` context and returns a `ChannelServerMessage` with the rendered text
/// prepended to the body. On empty template, empty render, or render failure,
/// returns the original event unchanged. Implements TEAM-3.3.
public enum EventBodyRenderer {

    private static let logger = Logger(subsystem: "com.btucker.graftty", category: "EventBodyRenderer")

    public static func body(
        for event: ChannelServerMessage,
        recipientWorktreePath: String,
        subjectWorktreePath: String?,
        repos: [RepoEntry],
        templateString: String
    ) -> ChannelServerMessage {
        // Empty template = passthrough.
        guard !templateString.isEmpty else { return event }
        guard case let .event(type, attrs, originalBody) = event else { return event }

        // Compute the agent context for this delivery.
        let recipientRepo = repos.first { repo in
            repo.worktrees.contains(where: { $0.path == recipientWorktreePath })
        }
        let recipient = recipientRepo?.worktrees.first(where: { $0.path == recipientWorktreePath })

        let isLead = (recipientRepo?.path == recipientWorktreePath)
        let isThisWorktree: Bool = {
            guard let subject = subjectWorktreePath else { return false }
            return subject == recipientWorktreePath
        }()
        let isOtherWorktree: Bool = {
            guard let subject = subjectWorktreePath else { return false }
            return subject != recipientWorktreePath
        }()

        let context: [String: Any] = [
            "agent": [
                "branch": recipient?.branch ?? "",
                "lead": isLead,
                "this_worktree": isThisWorktree,
                "other_worktree": isOtherWorktree,
            ]
        ]

        // Render. Stencil throws on parse / runtime errors; on failure, return
        // the original event so the agent still receives it (just without the
        // user-contributed prefix).
        let rendered: String
        do {
            rendered = try Environment().renderTemplate(string: templateString, context: context)
        } catch {
            logger.error("teamPrompt render failed: \(error.localizedDescription, privacy: .public)")
            return event
        }

        let trimmed = rendered.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return event }

        return .event(type: type, attrs: attrs, body: "\(trimmed)\n\n\(originalBody)")
    }
}
