import Foundation

/// Phase 1 shim that mirrors `ChannelEventRouter.recipients(...)` under the
/// team-event-oriented name. Phase 4 retires `ChannelEventRouter` and inlines
/// the implementation here; until then this forwards so callers in the new
/// `TeamEventDispatcher` pipeline don't reach into the legacy `Channels/`
/// namespace.
public enum TeamEventRouter {
    public static func recipients(
        event: RoutableEvent,
        subjectWorktreePath: String,
        repos: [RepoEntry],
        preferences: TeamEventRoutingPreferences
    ) -> [String] {
        ChannelEventRouter.recipients(
            event: event,
            subjectWorktreePath: subjectWorktreePath,
            repos: repos,
            preferences: preferences
        )
    }
}
