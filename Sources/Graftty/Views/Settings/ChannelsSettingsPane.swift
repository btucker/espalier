import SwiftUI

/// Preferences pane for the Claude Code Channels feature — a research-preview
/// integration that delivers PR state events into Claude sessions running in
/// tracked worktrees.
///
/// Backed entirely by `@AppStorage`:
/// - `channelsEnabled` (Bool): opt-in for the whole feature. When off, the
///   disclosure banner and prompt editor are hidden.
/// - `channelPrompt` (String): the instructions text broadcast to every
///   subscribed Claude session as the initial `type=instructions` event.
///
/// Subscriber-count caption ("N Claude sessions subscribed") is intentionally
/// omitted here; it requires injecting the `ChannelRouter` via an environment
/// object, which is wired up in a later task once `AppServices` owns a router.
struct ChannelsSettingsPane: View {
    @AppStorage("channelsEnabled") private var channelsEnabled: Bool = false
    @AppStorage("channelPrompt") private var channelPrompt: String = ChannelsSettingsPane.defaultPrompt

    var body: some View {
        Form {
            Section {
                Toggle("Enable GitHub/GitLab channel", isOn: $channelsEnabled)
                Text("Claude sessions in tracked worktrees receive events for their PR.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if channelsEnabled {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Label(
                            "Research preview — launches Claude with a development flag",
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .foregroundStyle(.orange)
                        .font(.subheadline.bold())

                        Text(verbatim:
                            "This prepends --dangerously-load-development-channels " +
                            "plugin:graftty-channel to your Claude launch. The flag bypasses " +
                            "Claude Code's channel allowlist only for this plugin. Events " +
                            "originate from Graftty's local polling — no external senders."
                        )
                        .font(.caption)

                        if let url = URL(string: "https://docs.claude.com/en/channels") {
                            Link("Learn more →", destination: url)
                                .font(.caption)
                        }
                    }
                    .padding(8)
                    .background(Color.orange.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.orange.opacity(0.4))
                    )
                }

                Section("Prompt") {
                    Text("Applied to every Claude session with channels enabled. " +
                         "Edits propagate immediately to running sessions.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    TextEditor(text: $channelPrompt)
                        .font(.system(.caption, design: .monospaced))
                        .frame(minHeight: 200)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.secondary.opacity(0.3))
                        )

                    HStack {
                        Spacer()
                        Button("Restore default") {
                            channelPrompt = Self.defaultPrompt
                        }
                        .font(.caption)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 480, minHeight: 240)
    }

    static let defaultPrompt: String = """
    You receive events from Graftty when state changes on the PR associated with your current worktree. Each event arrives as a <channel source="graftty-channel" type="..."> tag with attributes (pr_number, provider, repo, worktree, pr_url) and a short body.

    When you see:
    - type=pr_state_changed, to=merged: The PR merged. Briefly acknowledge. Don't take destructive actions (e.g. delete the worktree) without explicit confirmation.
    - type=ci_conclusion_changed, to=failure: Read the failing check log via the pr_url if accessible, summarize what failed, and propose a fix. Don't commit without confirmation.
    - type=ci_conclusion_changed, to=success: Brief acknowledgement. If the PR is now mergeable, mention it.

    Keep replies short. The user is working in the same terminal; noisy output is disruptive.
    """
}
