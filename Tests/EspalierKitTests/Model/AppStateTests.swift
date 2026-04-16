import Testing
import Foundation
@testable import EspalierKit

@Suite("AppState Tests")
struct AppStateTests {

    func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("espalier-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test func emptyStateHasNoRepos() {
        let state = AppState()
        #expect(state.repos.isEmpty)
        #expect(state.selectedWorktreePath == nil)
    }

    @Test func addRepo() {
        var state = AppState()
        let repo = RepoEntry(path: "/tmp/repo", displayName: "repo", worktrees: [
            WorktreeEntry(path: "/tmp/repo", branch: "main")
        ])
        state.addRepo(repo)
        #expect(state.repos.count == 1)
    }

    @Test func addDuplicateRepoIsIgnored() {
        var state = AppState()
        let repo1 = RepoEntry(path: "/tmp/repo", displayName: "repo")
        let repo2 = RepoEntry(path: "/tmp/repo", displayName: "repo-dup")
        state.addRepo(repo1)
        state.addRepo(repo2)
        #expect(state.repos.count == 1)
    }

    @Test func removeRepo() {
        var state = AppState()
        let repo = RepoEntry(path: "/tmp/repo", displayName: "repo")
        state.addRepo(repo)
        state.removeRepo(atPath: "/tmp/repo")
        #expect(state.repos.isEmpty)
    }

    @Test func saveAndLoad() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        var state = AppState()
        state.addRepo(RepoEntry(path: "/tmp/repo", displayName: "repo", worktrees: [
            WorktreeEntry(path: "/tmp/repo", branch: "main")
        ]))
        state.selectedWorktreePath = "/tmp/repo"
        state.sidebarWidth = 280

        try state.save(to: dir)

        let loaded = try AppState.load(from: dir)
        #expect(loaded.repos.count == 1)
        #expect(loaded.repos[0].path == "/tmp/repo")
        #expect(loaded.selectedWorktreePath == "/tmp/repo")
        #expect(loaded.sidebarWidth == 280)
    }

    @Test func loadFromEmptyDirReturnsDefault() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let loaded = try AppState.load(from: dir)
        #expect(loaded.repos.isEmpty)
    }

    @Test func worktreeForPathFindsCorrectEntry() {
        var state = AppState()
        let wt = WorktreeEntry(path: "/tmp/worktrees/feature", branch: "feature/x")
        state.addRepo(RepoEntry(path: "/tmp/repo", displayName: "repo", worktrees: [
            WorktreeEntry(path: "/tmp/repo", branch: "main"),
            wt,
        ]))
        let found = state.worktree(forPath: "/tmp/worktrees/feature")
        #expect(found?.branch == "feature/x")
    }

    @Test func worktreeForPathReturnsNilWhenNotFound() {
        let state = AppState()
        #expect(state.worktree(forPath: "/nonexistent") == nil)
    }
}
