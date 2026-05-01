import Foundation

/// Phase 1 shim: alias the existing `ChannelRoutingPreferences` under the
/// team-event-oriented name so callers in the new `TeamEventDispatcher`
/// pipeline don't reach into the legacy `Channels/` namespace.
///
/// Phase 5 of the channels-to-inbox migration renames the underlying
/// type properly; until then this typealias keeps the migration purely
/// additive.
public typealias TeamEventRoutingPreferences = ChannelRoutingPreferences
