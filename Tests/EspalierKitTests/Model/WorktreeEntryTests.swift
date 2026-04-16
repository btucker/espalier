import Testing
import Foundation
@testable import EspalierKit

@Suite("WorktreeEntry Tests")
struct WorktreeEntryTests {

    @Test func newEntryIsClosedState() {
        let entry = WorktreeEntry(path: "/tmp/worktree", branch: "feature/foo")
        #expect(entry.state == .closed)
        #expect(entry.attention == nil)
    }

    @Test func attentionCanBeSet() {
        var entry = WorktreeEntry(path: "/tmp/worktree", branch: "main")
        entry.attention = Attention(text: "Build failed", timestamp: Date())
        #expect(entry.attention?.text == "Build failed")
    }

    @Test func attentionWithAutoClear() {
        let attn = Attention(text: "Done", timestamp: Date(), clearAfter: 10)
        #expect(attn.clearAfter == 10)
    }

    @Test func splitTreeDefaultsToNil() {
        let entry = WorktreeEntry(path: "/tmp/worktree", branch: "main")
        #expect(entry.splitTree.root == nil)
    }

    @Test func codableRoundTrip() throws {
        var entry = WorktreeEntry(path: "/tmp/worktree", branch: "feature/bar")
        entry.state = .running
        let id = TerminalID()
        entry.splitTree = SplitTree(root: .leaf(id))

        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(WorktreeEntry.self, from: data)
        #expect(decoded.path == "/tmp/worktree")
        #expect(decoded.branch == "feature/bar")
        #expect(decoded.state == .running)
        #expect(decoded.splitTree.leafCount == 1)
    }

    @Test func repoEntryContainsWorktrees() {
        let main = WorktreeEntry(path: "/tmp/repo", branch: "main")
        let feature = WorktreeEntry(path: "/tmp/worktrees/feature", branch: "feature/x")
        let repo = RepoEntry(
            path: "/tmp/repo",
            displayName: "my-repo",
            worktrees: [main, feature]
        )
        #expect(repo.worktrees.count == 2)
        #expect(repo.displayName == "my-repo")
    }

    @Test func repoEntryCodeableRoundTrip() throws {
        let main = WorktreeEntry(path: "/tmp/repo", branch: "main")
        let repo = RepoEntry(path: "/tmp/repo", displayName: "my-repo", worktrees: [main])
        let data = try JSONEncoder().encode(repo)
        let decoded = try JSONDecoder().decode(RepoEntry.self, from: data)
        #expect(decoded.path == "/tmp/repo")
        #expect(decoded.worktrees.count == 1)
    }
}
