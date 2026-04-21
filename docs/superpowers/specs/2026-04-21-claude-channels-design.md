# Claude Code Channels — Design Specification

A new feature that pushes PR state changes from Graftty's existing polling into the Claude Code sessions running in tracked worktrees, using the [Claude Code channels capability](https://docs.claude.com/en/channels). A Settings tab lets the user customize the prompt that guides how Claude reacts to each event.

## Goal

After this ships, this user story works:

> I enable "GitHub/GitLab channel" in Graftty Settings and edit the prompt. I open a worktree and let `claude` launch (my default command). While I'm working in a different pane, someone merges my PR — within the next polling cycle, my Claude session silently receives a `<channel source="graftty-channel" type="pr_state_changed" to="merged" ...>` tag and responds per the prompt (e.g., offers to clean up the worktree). Later I tweak the prompt in Settings; on my next turn, Claude is already following the new guidance without restarting the session.

## Scope

**In scope (v1):**

- Three event types derived from existing `PRStatusStore` transitions: `pr_state_changed`, `ci_conclusion_changed`, `merge_state_changed`.
- GitHub and GitLab, transparently (same polling that already drives the sidebar PR badges).
- One global Settings tab with enable toggle + single editable prompt.
- One MCP plugin (`graftty-channel`) bundled inside Graftty.app, auto-installed into `~/.claude/plugins/` on enable.
- Hand-rolled MCP stdio layer in Swift as a subcommand of the existing `graftty` CLI.

**Out of scope (v2+):**

- PR comments, review events, issue comments. (Requires new polling code beyond `PRStatusStore`.)
- Per-worktree or per-repo prompt overrides.
- Arbitrary repo-level events (pushes, issues, discussions).
- Permission-prompt relay (Claude Code's `claude/channel/permission` capability).
- Publishing the plugin to the Anthropic marketplace (until channels graduate from research preview, users will see the `--dangerously-load-development-channels` flag).

## Architecture

Events flow in one direction: **GitHub/GitLab API → `PRStatusStore` → `ChannelRouter` → worktree-specific subscriber → `claude`**. Graftty's Swift side does all the routing and filtering; the MCP subprocess is a dumb forwarder whose only job is to translate Graftty's internal socket JSON into MCP notifications.

```
                        GitHub API     GitLab API
                             │              │
                             ▼              ▼
┌── Graftty.app ──────────────────────────────────────────────┐
│  ┌────────────────┐     ┌─────────────────┐    ┌──────────┐ │
│  │ PRStatusStore  │────▶│ ChannelRouter   │◀───│ Settings │ │
│  │ (existing)     │     │ (new)           │    │ Channels │ │
│  │                │     │                 │    │ tab      │ │
│  │ transitions    │     │ subscriber map: │    └──────────┘ │
│  │ callback       │     │  path → conn    │                 │
│  └────────────────┘     └────────┬────────┘                 │
└──────────────────────────────────┼──────────────────────────┘
                                   │ graftty-channels.sock
     ┌─────────────────────────────┼─────────────────────────┐
     │                             ▼                         │
     │  ┌─ worktree A ─┐   ┌─ worktree B ─┐   ┌─ worktree C ─┐
     │  │ claude       │   │ claude       │   │ claude       │
     │  │  │           │   │  │           │   │  │           │
     │  │  ▼ stdio     │   │  ▼ stdio     │   │  ▼ stdio     │
     │  │ graftty      │   │ graftty      │   │ graftty      │
     │  │ mcp-channel  │   │ mcp-channel  │   │ mcp-channel  │
     │  │ (subp #1)    │   │ (subp #2)    │   │ (subp #3)    │
     │  └──────────────┘   └──────────────┘   └──────────────┘
```

Each `claude` session spawns its own `graftty mcp-channel` subprocess — the subprocess is not shared across sessions. Graftty routes each event to exactly one subscriber (the one whose worktree path matches), so filtering happens at the source, not in the subprocess.

### Why this shape

- **Filtering where the mapping lives.** `PRStatusStore` keys all its state on `worktreePath`. The subscriber map in `ChannelRouter` uses the same key, so routing is O(1) lookup with no additional state.
- **Subprocess stays stateless.** It has no knowledge of repos, PRs, or providers — just a stdio socket on one side and a Unix socket on the other. ~150 LOC total including MCP JSON-RPC.
- **Multi-repo is a solved problem one layer up.** `PRStatusStore` already dispatches per-repo to `GitHubPRFetcher` or `GitLabPRFetcher` based on host detection. The channel sits downstream of that; it never sees the distinction.

## Components

### New files

| File                                                          | Purpose                                                                    |
| ------------------------------------------------------------- | -------------------------------------------------------------------------- |
| `Sources/GrafttyKit/Channels/ChannelRouter.swift`             | Owns the channels socket; maintains subscriber map; fans out events.       |
| `Sources/GrafttyKit/Channels/ChannelEvent.swift`              | `Codable` types for socket messages (`subscribe`, event types).            |
| `Sources/GrafttyKit/Channels/ChannelPluginInstaller.swift`    | Writes `~/.claude/plugins/graftty-channel/` from bundled resources.        |
| `Sources/GrafttyCLI/MCPChannel.swift`                         | `graftty mcp-channel` subcommand: the MCP stdio bridge.                    |
| `Sources/GrafttyCLI/MCPStdioServer.swift`                     | Hand-rolled MCP JSON-RPC 2.0 over stdin/stdout (~120 LOC).                 |
| `Sources/Graftty/Views/Settings/ChannelsSettingsPane.swift`   | SwiftUI view for the Channels Settings tab.                                |
| `Resources/plugins/graftty-channel/plugin.json`               | Plugin manifest copied into `~/.claude/plugins/` on enable.                |
| `Resources/plugins/graftty-channel/.mcp.json.template`        | MCP config template with `{{CLI_PATH}}` placeholder.                       |
| `Tests/GrafttyKitTests/Channels/ChannelRouterTests.swift`     | Unit tests for fan-out, subscriber lifecycle, dead-subscriber cleanup.     |
| `Tests/GrafttyKitTests/Channels/ChannelEventTests.swift`      | Codable round-trip tests for socket message types.                         |
| `Tests/GrafttyCLITests/MCPStdioServerTests.swift`             | MCP handshake + notification-emission tests with in-memory streams.        |

### Modified files

| File                                                          | Change                                                                                   |
| ------------------------------------------------------------- | ---------------------------------------------------------------------------------------- |
| `Sources/Graftty/Views/SettingsView.swift`                    | Add second tab: `ChannelsSettingsPane`.                                                  |
| `Sources/GrafttyKit/PRStatus/PRStatusStore.swift`             | New callback `onTransition: (_ worktreePath, _ event: ChannelEvent) -> Void`. Fires for the three v1 transition types. The existing `onPRMerged` stays (it drives the worktree-cleanup dialog) — the new callback is additive. |
| `Sources/GrafttyKit/DefaultCommandDecision.swift`             | When channels are enabled, prepend `--channels plugin:graftty-channel --dangerously-load-development-channels plugin:graftty-channel` to the `claude` launch string. |
| `Sources/GrafttyCLI/CLI.swift`                                | Register `MCPChannel` as a subcommand alongside `Notify` and `Pane`.                     |
| `Sources/GrafttyKit/Notification/SocketPathResolver.swift`    | Expose a second resolver, `resolveChannelSocket() -> String`, returning `<appsupport>/Graftty/graftty-channels.sock`. |
| `Sources/Graftty/GrafttyApp.swift`                            | Call `ChannelPluginInstaller.install()` on app launch (idempotent). Instantiate `ChannelRouter` at the same lifecycle point as the existing control socket. |
| `SPECS.md`                                                    | Add the `CHANNELS-*` section.                                                            |

## Data flow: a single PR-merged event

1. User merges PR #42 on GitHub for a branch checked out in worktree `/repos/acme-web/feature/login`.
2. `PRStatusStore`'s polling ticker fires `performFetch(worktreePath: "/repos/acme-web/feature/login", …)` on its next cadence.
3. The resulting `PRInfo` transitions from `.state = .open` to `.state = .merged`. The existing `onPRMerged` fires (drives the "delete worktree?" dialog) and the new `onTransition` fires with a `pr_state_changed` event.
4. `ChannelRouter.enqueue(event, forWorktree: "/repos/acme-web/feature/login")` looks up the subscriber for that path.
5. The event is serialized as one-line JSON and written to that subscriber's socket. Other worktrees' subscribers receive nothing.
6. The `graftty mcp-channel` subprocess in that session reads the JSON, converts `type` + `attrs` into MCP `meta` and `body` into MCP `content`, and emits `notifications/claude/channel` on stdout.
7. Claude Code reads the notification and injects `<channel source="graftty-channel" type="pr_state_changed" pr_number="42" to="merged" …>PR #42 merged by @alice</channel>` into the session context.
8. On Claude's next turn, it sees the tag and responds per the user's Settings prompt.

## Event types and schema

v1 defines three transition events, plus one control event used for the prompt.

### `pr_state_changed`

Fires when `PRInfo.state` transitions between `open`, `merged`, `closed`.

| Attribute      | Example                                    |
| -------------- | ------------------------------------------ |
| `from`         | `open`                                     |
| `to`           | `merged`, `closed`, `open`                 |
| `pr_number`    | `42`                                       |
| `pr_title`     | `Add login flow`                           |
| `pr_url`       | `https://github.com/acme/web/pull/42`      |
| `provider`     | `github` or `gitlab`                       |
| `repo`         | `acme/web`                                 |
| `worktree`     | `/repos/acme-web/feature/login`            |

Body: short human-readable (e.g., `PR #42 "Add login flow" merged by @alice`).

### `ci_conclusion_changed`

Fires when the latest check-run/pipeline conclusion flips.

| Attribute      | Values                                                         |
| -------------- | -------------------------------------------------------------- |
| `from`         | `pending`, `success`, `failure`, `neutral`, `cancelled`, `none` |
| `to`           | same set                                                        |
| (plus common set above: `pr_number`, `provider`, `repo`, `worktree`, `pr_url`) |

Body: short (e.g., `CI failed on feature/login (2 of 5 checks failing)`).

### `merge_state_changed`

Fires when mergeable state transitions.

| Attribute | Values                                              |
| --------- | --------------------------------------------------- |
| `from`    | `mergeable`, `blocked`, `dirty`, `has_conflicts`, `unknown` |
| `to`      | same set                                            |

Body: short.

### `instructions` (control event)

Sent on subscribe (initial) and on every Settings prompt edit (fan-out). Not a state transition — used to deliver the user's current prompt into Claude's context.

Attributes: none beyond `type`. Body: the literal prompt text.

### Common event envelope

All events share the same wire shape on the socket and the same `<channel>` tag attributes:

- `source="graftty-channel"` (auto-added by Claude Code from the MCP server's name)
- `type=<one of the above>`
- Type-specific attributes listed above
- Body: one or more lines of text

## Socket protocol

Newline-delimited JSON on a Unix domain socket at `<Application Support>/Graftty/graftty-channels.sock` (distinct from the control socket at `graftty.sock`). Reuses the existing `SocketIO` infrastructure for reads and writes.

### Subscribe message (subscriber → router, once at startup)

```json
{"type": "subscribe", "worktree": "/realpath/to/worktree", "version": 1}
```

`version` is the protocol version; v1 is the only value for now. Router responds by sending the initial `instructions` event, then begins routing matching transition events.

### Event message (router → subscriber, push)

```json
{
  "type": "pr_state_changed",
  "attrs": {
    "pr_number": "42",
    "from": "open",
    "to": "merged",
    "provider": "github",
    "repo": "acme/web",
    "worktree": "/realpath/to/worktree",
    "pr_url": "https://github.com/acme/web/pull/42"
  },
  "body": "PR #42 merged by @alice"
}
```

Subscriber converts `type` + `attrs` into MCP notification `meta`, and `body` into `content`.

### Disconnect

EOF on the socket from either side. Router removes the subscriber from its map; subprocess exits cleanly. No keepalive, no heartbeat.

## MCP handshake

On receiving `initialize` from Claude Code, `MCPStdioServer` responds with:

```json
{
  "protocolVersion": "2024-11-05",
  "capabilities": {
    "experimental": {"claude/channel": {}}
  },
  "serverInfo": {"name": "graftty-channel", "version": "0.1.0"},
  "instructions": "Events from this channel arrive as <channel source='graftty-channel' type='...'> tags. Your operative behavioral guidance for these events is delivered within the channel stream itself as events with type='instructions' — the most recent such event's body supersedes any earlier one. If no instructions event has arrived yet, act conservatively and wait for one."
}
```

The `instructions` field is Claude's system-level hint that actual guidance arrives in-stream. The user's editable prompt never lives in this field (the field is sent once at subprocess spawn and can't be updated). Instead, the first `instructions` event arrives immediately after subscribe, carrying the current prompt text.

## Settings UX

The `SettingsView` TabView grows a second tab, "Channels", next to the existing "General". Three regions:

```
┌─ Graftty Settings ──────────────────────────────────────┐
│  General   [Channels]                                   │
│  ─────────────────────                                  │
│                                                         │
│  Enable GitHub/GitLab channel                      [ON] │
│  Claude sessions in tracked worktrees receive events    │
│  for their PR.                                          │
│  ─────────────────────────────────────────────────────  │
│  ┌───────────────────────────────────────────────────┐  │
│  │ ⚠  Research preview — launches Claude with a      │  │
│  │    development flag                               │  │
│  │    This prepends `--dangerously-load-…-channels   │  │
│  │    plugin:graftty-channel` to your Claude launch. │  │
│  │    The flag bypasses Claude Code's channel        │  │
│  │    allowlist *only for this plugin*. Events       │  │
│  │    originate from Graftty's local polling —       │  │
│  │    no external senders.    Learn more →           │  │
│  └───────────────────────────────────────────────────┘  │
│                                                         │
│  Prompt                                                 │
│  Applied to every Claude session with channels enabled. │
│  Edits propagate immediately to running sessions.       │
│  ┌───────────────────────────────────────────────────┐  │
│  │ You receive events from Graftty when state        │  │
│  │ changes on the PR associated with your current    │  │
│  │ worktree. Each event arrives as a <channel …>     │  │
│  │ ...                                               │  │
│  │ (multi-line, plain-text)                          │  │
│  └───────────────────────────────────────────────────┘  │
│                                                         │
│  2 Claude sessions subscribed      Restore default →    │
└─────────────────────────────────────────────────────────┘
```

### Storage

Following the pattern established by `defaultCommand` in [2026-04-17-default-command-design.md](./2026-04-17-default-command-design.md):

| Key                     | Type   | Default                   | Meaning                                        |
| ----------------------- | ------ | ------------------------- | ---------------------------------------------- |
| `channelsEnabled`       | Bool   | `false`                   | Master enable. When false, no launch flags, router idle. |
| `channelPrompt`         | String | _built-in default prompt_ | The prompt text broadcast as `instructions` events. |

Both accessed via `@AppStorage`. No Apply/Cancel buttons — edits are write-through. `ChannelRouter` observes `channelPrompt` via a `UserDefaults` publisher and debounces changes at 500ms before broadcasting.

### Default prompt

Pre-populated at first run with guidance for the three v1 event types. Conservative phrasing ("don't take destructive actions without explicit confirmation"). Stored alongside the built-in default so "Restore default prompt" can revert without round-tripping through the network.

### Learn more link

Opens `https://docs.claude.com/en/channels` in the default browser. Users who want to understand the flag have a path to the authoritative docs. A Graftty-hosted explainer page is a v2 consideration.

### Subscribers count

Small caption at the bottom of the tab ("N Claude sessions subscribed"), bound to `ChannelRouter.subscribers.count`. Provides visible feedback that the channel is wired up without needing a Test button.

## Prompt update lifecycle

1. User types in the Settings textarea; SwiftUI binding updates `@AppStorage("channelPrompt")`.
2. `ChannelRouter`'s `UserDefaults` observer fires. A 500ms debounce timer starts; if another edit arrives first, the timer is reset.
3. On timer fire, router constructs `{"type": "instructions", "body": <new prompt>}` and writes one copy to every subscriber's socket.
4. Each subprocess reads the message and emits the corresponding MCP notification.
5. Each `claude` session sees `<channel source="graftty-channel" type="instructions">...</channel>` on its next turn.
6. Claude follows the most-recent-instructions-event rule set up by the MCP handshake's `instructions` field.

## Error handling

Five failure modes. None crashes the session; each either emits a one-shot `channel_error` MCP notification or silently no-ops.

| Failure                                              | Handling                                                                                         |
| ---------------------------------------------------- | ------------------------------------------------------------------------------------------------ |
| Channel socket missing (Graftty not running)         | Subprocess startup `SocketClient.openConnectedSocket()` throws `.appNotRunning`. Emit one `channel_error` notification, exit 1. |
| CWD not inside a tracked worktree                    | `WorktreeResolver.resolve()` throws `.notInsideWorktree`. Emit one `channel_error`, exit 1.      |
| Socket closes mid-session (Graftty quit)             | Subscriber's read loop hits EOF. Emit one `channel_error` ("Graftty channel disconnected — restart Graftty and your Claude session to reconnect"), exit 1. |
| `PRStatusStore` fetch fails                          | No event emitted. Existing `failureStreak` + backoff continues. Channel stays silent until next successful transition — avoids spamming Claude with polling errors. |
| Stale subscriber (claude died, socket wasn't cleanly torn down) | Router detects on next write: `EPIPE` / `ECONNRESET`. Remove subscriber from map; close our end; subscribers-count in Settings updates. |

No retries, no reconnection logic, no heartbeats. If things go wrong, user restarts the relevant piece.

## Plugin packaging & distribution

The plugin ships as static resources inside Graftty.app and is copied to the user's `~/.claude/plugins/` at install time.

### In the app bundle

```
Graftty.app/Contents/Resources/plugins/graftty-channel/
├── plugin.json
└── .mcp.json.template
```

### Install routine

`ChannelPluginInstaller.install()` (called on every app launch, idempotent):

1. Locate CLI binary at `Bundle.main.bundlePath + "/Contents/Resources/graftty"` (same path `CLIInstaller.swift` uses as `source:`).
2. Read `.mcp.json.template`:
   ```json
   {
     "mcpServers": {
       "graftty-channel": {
         "command": "{{CLI_PATH}}",
         "args": ["mcp-channel"]
       }
     }
   }
   ```
3. Substitute `{{CLI_PATH}}` with the absolute CLI path, write to `~/.claude/plugins/graftty-channel/.mcp.json`.
4. Copy `plugin.json` verbatim.

Called on Settings toggle enable and on every app launch where `channelsEnabled == true`. Gating on enabled state means users who never turn channels on get no files written into `~/.claude/plugins/`. Running on every relevant launch keeps the `command` path current if the user moves Graftty.app.

### Launch-flag composition

When `channelsEnabled == true`, `DefaultCommandDecision.compose(command:)` prepends to a `claude`-family command:

```
claude --channels plugin:graftty-channel --dangerously-load-development-channels plugin:graftty-channel
```

Both flags are required: `--channels` activates the plugin for this session, `--dangerously-load-development-channels` bypasses the allowlist (needed until channels graduate from research preview). Both are scoped to the plugin name — they don't extend the bypass to any other channels the user may have enabled.

When `channelsEnabled == false`, the launch string is unchanged. A user who toggles mid-session keeps whichever flags their existing `claude` process launched with; only new sessions pick up the change.

## Testing strategy

### Unit tests (automated, CI)

- **`ChannelRouterTests`**: subscriber add/remove, event fan-out to matching subscriber only, dead-subscriber cleanup on write failure, initial `instructions` event on subscribe, prompt-update debounce behavior with a fake scheduler.
- **`ChannelEventTests`**: Codable round-trips for `subscribe`, each transition type, `instructions`.
- **`MCPStdioServerTests`**: `initialize` handshake produces the correct capabilities + instructions, `notifications/claude/channel` serialization round-trips, unknown methods return a JSON-RPC error (not a crash).
- **`PRStatusStoreTests`** (extensions): the new `onTransition` callback fires on exactly the three v1 transition types, does not fire on idempotent polls (same state twice), and carries correct `from`/`to` values.
- **`SettingsViewTests`**: enabling the toggle flips `@AppStorage("channelsEnabled")`; editing the prompt flips `@AppStorage("channelPrompt")`.

### Manual smoke test (documented, not CI)

1. Enable channels in Settings; verify the launch-flag preview (if we add one) shows the two flags.
2. Open a worktree with an active PR; launch `claude`.
3. Verify `2 Claude sessions subscribed` (or whatever the count should be) updates.
4. Trigger a PR state change on GitHub (merge a test PR); verify the `<channel>` tag appears in Claude's session on the next turn.
5. Repeat for GitLab with `glab`.
6. Edit the prompt in Settings; verify the change shows up in Claude's behavior on the next turn.
7. Quit Graftty; verify Claude session emits a `channel_error` and continues without channels.

## SPECS.md requirements

New top-level section `CHANNELS` in `SPECS.md`:

- **CHANNELS-1.1** — While `channelsEnabled` is true and the user's `defaultCommand` begins with the `claude` binary name, the application shall insert `--channels plugin:graftty-channel --dangerously-load-development-channels plugin:graftty-channel` between the binary name and any user-supplied arguments for all subsequently launched sessions. If `defaultCommand` does not begin with `claude`, the launch string shall be unchanged.
- **CHANNELS-1.2** — While channels are enabled, the application shall rewrite `~/.claude/plugins/graftty-channel/.mcp.json` on every app launch with the current absolute path to the bundled `graftty` CLI binary.
- **CHANNELS-1.3** — When channels are disabled via the Settings toggle, the application shall stop forwarding events to existing subscribers but shall not close their sockets.
- **CHANNELS-1.4** — Existing `claude` sessions shall continue with their original launch flags when channels are enabled or disabled mid-session; only newly launched sessions shall pick up the change.
- **CHANNELS-2.1** — When `PRStatusStore` detects a PR state transition (`open`/`merged`/`closed`), CI conclusion change, or merge-state change for a worktree with an active channel subscriber, the application shall forward exactly one event to that subscriber.
- **CHANNELS-2.2** — Events shall not be sent to subscribers whose worktree path does not match the worktree that produced the transition.
- **CHANNELS-2.3** — Event attributes `worktree`, `provider`, `repo`, `pr_number`, and `pr_url` shall be present on every `pr_state_changed`, `ci_conclusion_changed`, and `merge_state_changed` event.
- **CHANNELS-2.4** — Events shall not be sent for idempotent polls where the previous and current state are identical.
- **CHANNELS-3.1** — When the user edits the channels prompt in Settings, the application shall fan out a `type=instructions` event to every connected subscriber after a 500ms debounce.
- **CHANNELS-3.2** — On first socket connection from a subscriber, the application shall immediately send a `type=instructions` event carrying the current prompt, before any other events.
- **CHANNELS-4.1** — If `WorktreeResolver.resolve()` fails during subprocess startup, the subprocess shall emit a single `type=channel_error` MCP notification and exit with status 1.
- **CHANNELS-4.2** — If the channel socket connection closes mid-session, the subprocess shall emit a single `type=channel_error` MCP notification and exit with status 1.
- **CHANNELS-4.3** — If a subscriber's socket write fails (e.g., `EPIPE` after the claude process exited), the router shall remove that subscriber from its subscriber map.
- **CHANNELS-4.4** — When a `PRStatusStore` fetch fails, no event shall be sent to any subscriber for that polling cycle.
- **CHANNELS-5.1** — The channel socket shall be located at the standard Graftty socket directory as resolved by `SocketPathResolver`, named `graftty-channels.sock`, distinct from the control socket at `graftty.sock`.
- **CHANNELS-5.2** — The channel socket and the control socket shall operate independently; a failure on one shall not disrupt the other.

## Future extensions

- **v2: PR comments, review comments, review submissions.** Requires extending `PRStatusStore` polling to include `gh pr view --json comments,reviews` and a "seen since" cursor per PR. New event types: `pr_comment_added`, `pr_review_submitted`, `pr_review_comment_added`. Additive — existing v1 events and code path stay as-is.
- **v2: Per-worktree or per-repo prompt overrides.** Additive Settings UI (worktree-context-menu entry or repo-settings panel), stored in `UserDefaults` under a keyed-by-worktree structure. Router's broadcast becomes per-worktree-aware.
- **v2: Marketplace submission.** Once channels leave research preview and the plugin passes Anthropic's security review, we can drop `--dangerously-load-development-channels`. The Settings flag-disclosure banner adapts: instead of "research preview", it shows a link to the published plugin entry.
- **v2: Permission-prompt relay.** The `claude/channel/permission` capability lets the channel forward Claude's tool-approval prompts to the same channel. For Graftty this could mean a macOS notification with approve/deny buttons when Claude wants to run a command. Needs careful thought around sender authentication (none of our inbound is externally authenticated, so we'd need a new mechanism).
- **v2: Graftty-hosted "Learn more" page.** Explains the flag, the risk model, and how Graftty events work. Replaces the `docs.claude.com` link in the flag-disclosure banner.

## References

- Claude Code channels reference: `https://docs.claude.com/en/channels-reference`
- Existing spec that establishes Settings + `@AppStorage` pattern: [2026-04-17-default-command-design.md](./2026-04-17-default-command-design.md)
- Existing spec for PR polling infrastructure: [2026-04-17-pr-mr-status-display-design.md](./2026-04-17-pr-mr-status-display-design.md)
- Existing spec for Graftty CLI pattern: [2026-04-17-cli-pane-commands-design.md](./2026-04-17-cli-pane-commands-design.md)
