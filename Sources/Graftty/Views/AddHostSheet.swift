import SwiftUI
import GrafttyKit

struct AddHostSheet: View {
    let tester: AddHostConnectionTester
    let onSave: (MacHost) -> Void
    let onCancel: () -> Void

    @State private var form = AddHostFormModel()
    @State private var statusText: String?
    @State private var isTesting = false

    private var draftHost: MacHost? {
        form.makeHost()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add SSH Host")
                .font(.headline)

            Form {
                TextField("Display Name", text: $form.label)
                TextField("Hostname, IP, or SSH alias", text: $form.host)
                TextField("Username", text: $form.username)
                TextField("SSH Port", value: $form.sshPort, format: .number)
                    .frame(width: 120)
                TextField("Graftty Port", value: $form.remoteGrafttyPort, format: .number)
                    .frame(width: 120)
            }
            .formStyle(.grouped)
            .frame(height: 210)

            VStack(alignment: .leading, spacing: 4) {
                Text("The remote Mac must already accept your SSH login and have Graftty running with Web Access set to SSH Tunnel mode.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Graftty uses your existing SSH keys, agent, and ~/.ssh/config. It does not generate or import keys on Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let statusText {
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Button("Test Connection") {
                    testConnection()
                }
                .disabled(draftHost?.sshConfig == nil || isTesting)

                Spacer()

                Button("Cancel", action: onCancel)
                Button("Save") {
                    if let draftHost {
                        onSave(draftHost)
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(draftHost == nil)
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    private func testConnection() {
        guard let config = draftHost?.sshConfig else { return }
        statusText = "Testing..."
        isTesting = true
        Task {
            let result = await tester.test(config: config)
            await MainActor.run {
                isTesting = false
                switch result {
                case .success(let url):
                    statusText = "Connected to \(url.absoluteString)"
                case .sshFailed(let message), .grafttyUnavailable(let message):
                    statusText = message
                }
            }
        }
    }
}
