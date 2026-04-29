#if canImport(UIKit)
import GrafttyProtocol
import SwiftUI

public struct AddWorktreeSheetView: View {

    public let host: Host
    public let baseURL: URL
    public let onCreated: (CreateWorktreeClient.Response) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var reposState: ReposState = .loading
    @State private var selectedRepoPath: String?
    @State private var worktreeName: String = ""
    @State private var branchName: String = ""
    /// Once the user types a branch that differs from the worktree name,
    /// stop auto-syncing so their edit sticks.
    @State private var branchMirrorsWorktree: Bool = true
    @State private var isSubmitting: Bool = false
    @State private var errorMessage: String?

    public init(
        host: Host,
        baseURL: URL? = nil,
        onCreated: @escaping (CreateWorktreeClient.Response) -> Void
    ) {
        self.host = host
        self.baseURL = baseURL ?? host.baseURL
        self.onCreated = onCreated
    }

    private enum ReposState {
        case loading
        case loaded([ReposFetcher.RepoInfo])
        case error(String)
    }

    public var body: some View {
        NavigationStack {
            Group {
                switch reposState {
                case .loading:
                    ProgressView().padding()
                case .error(let msg):
                    ContentUnavailableView {
                        Label("Couldn't load repositories", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(msg)
                    } actions: {
                        Button("Retry") { Task { await loadRepos() } }
                            .buttonStyle(.borderedProminent)
                    }
                case .loaded(let repos) where repos.isEmpty:
                    ContentUnavailableView(
                        "No repositories tracked",
                        systemImage: "folder.badge.questionmark",
                        description: Text("Open a repository in Graftty on the Mac first.")
                    )
                case .loaded(let repos):
                    form(repos: repos)
                }
            }
            .disabled(isSubmitting)
            .navigationTitle("Add Worktree")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSubmitting {
                        ProgressView().controlSize(.small)
                    } else {
                        Button("Create") { Task { await submit() } }
                            .disabled(!canSubmit)
                    }
                }
            }
            .task { await loadRepos() }
        }
    }

    @ViewBuilder
    private func form(repos: [ReposFetcher.RepoInfo]) -> some View {
        Form {
            if repos.count > 1 {
                Section("Repository") {
                    Picker("Repository", selection: $selectedRepoPath) {
                        ForEach(repos, id: \.path) { repo in
                            Text(repo.displayName).tag(Optional(repo.path))
                        }
                    }
                    .pickerStyle(.menu)
                }
            }
            Section("Worktree name") {
                TextField("feature-xyz", text: $worktreeName)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .onChange(of: worktreeName) { _, new in
                        let sanitized = WorktreeNameSanitizer.sanitize(new)
                        if sanitized != new {
                            worktreeName = sanitized
                            return
                        }
                        if branchMirrorsWorktree && branchName != sanitized {
                            branchName = sanitized
                        }
                    }
            }
            Section("Branch") {
                TextField("feature-xyz", text: $branchName)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .onChange(of: branchName) { _, new in
                        let sanitized = WorktreeNameSanitizer.sanitize(new)
                        if sanitized != new {
                            branchName = sanitized
                            return
                        }
                        if sanitized != worktreeName {
                            branchMirrorsWorktree = false
                        }
                    }
            }
            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var canSubmit: Bool {
        guard !isSubmitting, selectedRepoPath != nil else { return false }
        return !WorktreeNameSanitizer.trimForSubmit(worktreeName).isEmpty
            && !WorktreeNameSanitizer.trimForSubmit(branchName).isEmpty
    }

    private func loadRepos() async {
        reposState = .loading
        do {
            let repos = try await ReposFetcher.fetch(baseURL: baseURL)
            reposState = .loaded(repos)
            if !repos.contains(where: { $0.path == selectedRepoPath }) {
                selectedRepoPath = repos.first?.path
            }
        } catch let err as ReposFetcher.FetchError {
            reposState = .error(err.userMessage)
        } catch {
            reposState = .error(ReposFetcher.FetchError.transport.userMessage)
        }
    }

    private func submit() async {
        guard let repoPath = selectedRepoPath else { return }
        errorMessage = nil
        isSubmitting = true
        defer { isSubmitting = false }

        let body = CreateWorktreeClient.Request(
            repoPath: repoPath,
            worktreeName: WorktreeNameSanitizer.trimForSubmit(worktreeName),
            branchName: WorktreeNameSanitizer.trimForSubmit(branchName)
        )
        do {
            let response = try await CreateWorktreeClient.create(baseURL: baseURL, body: body)
            onCreated(response)
            dismiss()
        } catch let err as CreateWorktreeClient.CreateError {
            errorMessage = err.userMessage
        } catch {
            errorMessage = CreateWorktreeClient.CreateError.transport.userMessage
        }
    }
}
#endif
