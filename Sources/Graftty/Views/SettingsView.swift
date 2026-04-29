// Sources/Graftty/Views/SettingsView.swift
import AppKit
import GrafttyKit
import SwiftUI

/// Preferences pane for Graftty — the "General" tab inside the SwiftUI
/// `Settings` scene. The `TabView` + `.tabItem` shell lives in `GrafttyApp`
/// so this view renders its form directly; wrapping another `TabView` here
/// would nest a second "General" tab strip under the first.
struct SettingsView: View {
    @AppStorage(SettingsKeys.defaultCommand) private var defaultCommand: String = ""
    @AppStorage("defaultCommandFirstPaneOnly") private var firstPaneOnly: Bool = true
    @AppStorage(SettingsKeys.editorKind) private var editorKind: String = ""
    @AppStorage(SettingsKeys.editorAppBundleID) private var editorAppBundleID: String = ""
    @AppStorage(SettingsKeys.editorCliCommand) private var editorCliCommand: String = ""

    /// Resolved editor for the "currently using $EDITOR from shell" caption.
    /// Recomputed on view body re-evaluation; cheap enough since the
    /// shell-env probe is itself cached inside EditorPreference.
    @State private var resolvedEditorCaption: String = ""

    /// Cached list of installed text-editor apps; populated lazily on
    /// first selection of the "App" radio.
    @State private var availableApps: [TextEditorApp] = []

    /// Owner shows the "Restart ZMX…" confirmation alert. Injected as a
    /// closure so SettingsView stays decoupled from TerminalManager.
    let onRestartZMX: () -> Void

    var body: some View {
        Form {
            TextField("Default command:", text: $defaultCommand, prompt: Text("e.g., claude"))
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.leading)

            Toggle("Run in first pane only", isOn: $firstPaneOnly)

            Text("Runs automatically when a worktree opens. Leave empty to disable.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider().padding(.vertical, 4)

            // Editor section — EDITOR-1.x.
            Text("Editor")
                .font(.headline)

            Picker(selection: $editorKind) {
                Text(shellEditorRowLabel)
                    .tag("")
                Text("App")
                    .tag("app")
                Text("CLI Editor")
                    .tag("cli")
            } label: {
                Text("Editor:")
            }
            .pickerStyle(.radioGroup)

            if editorKind == "app" {
                Picker(selection: $editorAppBundleID) {
                    Text("Choose…").tag("")
                    ForEach(availableApps) { app in
                        Text(app.displayName).tag(app.bundleID)
                    }
                } label: {
                    Text("Application:")
                }
                .onAppear { loadAvailableApps() }
            }

            if editorKind == "cli" {
                TextField("CLI command:", text: $editorCliCommand, prompt: Text("e.g., nvim"))
                    .textFieldStyle(.roundedBorder)
            }

            Text("Used when you cmd-click a file path in a pane.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider().padding(.vertical, 4)

            HStack {
                Button("Restart ZMX…", action: onRestartZMX)
                Spacer()
            }

            Text("Ends all running terminal sessions. Use this if panes become unresponsive or you want fresh zmx daemons.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .frame(minWidth: 420, minHeight: 360)
        .onAppear { recomputeShellEditorCaption() }
    }

    private var shellEditorRowLabel: String {
        if resolvedEditorCaption.isEmpty {
            return "Use $EDITOR from shell"
        }
        return "Use $EDITOR from shell  (current: \(resolvedEditorCaption))"
    }

    /// Fire-and-forget probe for the caption; matches what
    /// EditorPreference.resolve() would return when the user has nothing
    /// set. Runs on a background queue to avoid blocking the UI.
    private func recomputeShellEditorCaption() {
        DispatchQueue.global(qos: .userInitiated).async {
            let probe = LoginShellEnvProbe()
            let value = probe.value(forName: "EDITOR") ?? "vi"
            DispatchQueue.main.async {
                self.resolvedEditorCaption = value
            }
        }
    }

    private func loadAvailableApps() {
        // Use a sample text file so LaunchServices reports every editor
        // registered for plain text.
        let sampleURL = URL(fileURLWithPath: "/tmp/x.txt")
        let urls = NSWorkspace.shared.urlsForApplications(toOpen: sampleURL)

        var seen = Set<String>()
        var apps: [TextEditorApp] = []
        for url in urls {
            guard let bundle = Bundle(url: url),
                  let bundleID = bundle.bundleIdentifier,
                  !seen.contains(bundleID) else { continue }
            seen.insert(bundleID)

            let displayName = FileManager.default.displayName(atPath: url.path)
            apps.append(TextEditorApp(bundleID: bundleID, displayName: displayName, url: url))
        }
        apps.sort { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        self.availableApps = apps
    }
}

private struct TextEditorApp: Identifiable, Hashable {
    let bundleID: String
    let displayName: String
    let url: URL
    var id: String { bundleID }
}
