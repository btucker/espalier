import AppKit
import GrafttyKit
import SwiftUI

/// Settings pane that exposes the `agentTeamsEnabled` toggle and the
/// channel prompt editor that was previously in ChannelsSettingsPane.
///
/// Implements TEAM-1.1, TEAM-1.3 from SPECS.md.
struct AgentTeamsSettingsPane: View {
    @AppStorage("agentTeamsEnabled") private var agentTeamsEnabled: Bool = false
    @AppStorage("teamPRNotificationsEnabled") private var prNotificationsEnabled: Bool = true
    @AppStorage("teamLeadPrompt") private var teamLeadPrompt: String = ""
    @AppStorage("teamCoworkerPrompt") private var teamCoworkerPrompt: String = ""

    var body: some View {
        Form {
            Section {
                Toggle("Enable agent teams", isOn: $agentTeamsEnabled)
            } footer: {
                Text("Locks the Default Command field and gives each Claude pane in a multi-worktree repo team-aware instructions on connect.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if agentTeamsEnabled {
                Section("Managed default command") {
                    Text(teamModeManagedCommand)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                Section {
                    Toggle("Notify team about GitHub/GitLab PR activity", isOn: $prNotificationsEnabled)
                } footer: {
                    Text("When on, Graftty fires pr_state_changed and team_pr_merged channel events as PR state, CI conclusions, and merges are detected. Turn off to suppress all PR channel events without disabling team mode.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(
                            "Launch Claude with this flag",
                            systemImage: "terminal"
                        )
                        .font(.subheadline.bold())

                        Text(verbatim:
                            "Graftty registers a user-scope MCP server with Claude Code. " +
                            "To receive channel events, launch Claude with:"
                        )
                        .font(.caption)

                        HStack(spacing: 6) {
                            Text(verbatim: Self.launchFlag)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .padding(6)
                                .background(Color.secondary.opacity(0.12))
                                .cornerRadius(4)
                            Button("Copy") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(Self.launchFlag, forType: .string)
                            }
                            .font(.caption)
                            .buttonStyle(.borderless)
                        }

                        Text(verbatim:
                            "Research preview — the --dangerously-load-development-channels " +
                            "flag bypasses Claude Code's channel allowlist for this server only. " +
                            "Events originate from Graftty's local polling; no external senders."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)

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

                Section("Lead prompt") {
                    Text("Custom prompt for the lead (root) session. Appended to its MCP instructions.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    TextEditor(text: $teamLeadPrompt)
                        .font(.system(.caption, design: .monospaced))
                        .frame(minHeight: 120)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.secondary.opacity(0.3))
                        )
                }

                Section("Coworker prompt") {
                    Text("Custom prompt for coworker sessions. Appended to their MCP instructions.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    TextEditor(text: $teamCoworkerPrompt)
                        .font(.system(.caption, design: .monospaced))
                        .frame(minHeight: 120)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.secondary.opacity(0.3))
                        )
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 480, minHeight: 240)
    }

    /// The exact flag users need to append when launching Claude for a
    /// channel-subscribing session.
    static let launchFlag = "--dangerously-load-development-channels server:graftty-channel"
}
