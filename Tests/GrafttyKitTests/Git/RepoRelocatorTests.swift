import Testing
import Foundation
@testable import GrafttyKit

@Suite("RepoRelocator Tests")
struct RepoRelocatorTests {

    private func repo(
        path: String,
        worktrees: [(path: String, branch: String, state: WorktreeState)]
    ) -> RepoEntry {
        let wts = worktrees.map {
            WorktreeEntry(path: $0.path, branch: $0.branch, state: $0.state)
        }
        return RepoEntry(path: path, displayName: URL(fileURLWithPath: path).lastPathComponent,
                         worktrees: wts)
    }

    private func discovered(path: String, branch: String) -> DiscoveredWorktree {
        DiscoveredWorktree(path: path, branch: branch)
    }

    @Test func cleanMoveCarriesAllWorktreesForward() {
        let existing = repo(path: "/old/repo", worktrees: [
            ("/old/repo", "main", .running),
            ("/old/repo/.worktrees/feature", "feature", .closed)
        ])
        let discoveredList = [
            discovered(path: "/new/repo", branch: "main"),
            discovered(path: "/new/repo/.worktrees/feature", branch: "feature")
        ]

        let decision = RepoRelocator.decide(
            repo: existing,
            newRepoPath: "/new/repo",
            discovered: discoveredList,
            selectedWorktreePath: "/old/repo/.worktrees/feature"
        )

        #expect(decision.needsRepair == false)
        #expect(decision.carriedForward.count == 2)
        #expect(decision.carriedForward.contains { $0.newPath == "/new/repo" && $0.existingID == existing.worktrees[0].id })
        #expect(decision.carriedForward.contains {
            $0.newPath == "/new/repo/.worktrees/feature"
                && $0.existingID == existing.worktrees[1].id
        })
        #expect(decision.goneStale.isEmpty)
        #expect(decision.newSelectedWorktreePath == "/new/repo/.worktrees/feature")
    }

    @Test func brokenGitdirSchedulesRepair() {
        let existing = repo(path: "/old/repo", worktrees: [
            ("/old/repo", "main", .running),
            ("/old/repo/.worktrees/feature", "feature", .closed)
        ])
        // Discovery omits the linked worktree — symptom of a broken
        // gitdir pointer git would prune.
        let discoveredList = [discovered(path: "/new/repo", branch: "main")]

        let decision = RepoRelocator.decide(
            repo: existing,
            newRepoPath: "/new/repo",
            discovered: discoveredList,
            selectedWorktreePath: nil
        )

        #expect(decision.needsRepair == true)
        #expect(decision.repairCandidatePaths == ["/new/repo/.worktrees/feature"])
    }

    @Test func postRepairUnmatchedWorktreeGoesStale() {
        let existing = repo(path: "/old/repo", worktrees: [
            ("/old/repo", "main", .running),
            ("/old/repo/.worktrees/feature", "feature", .closed)
        ])
        // Post-repair discovery still doesn't list the feature worktree.
        let postRepair = [discovered(path: "/new/repo", branch: "main")]

        let decision = RepoRelocator.decidePostRepair(
            repo: existing,
            newRepoPath: "/new/repo",
            discovered: postRepair,
            selectedWorktreePath: "/old/repo/.worktrees/feature"
        )

        #expect(decision.carriedForward.count == 1)
        #expect(decision.goneStale.count == 1)
        #expect(decision.goneStale.first?.branch == "feature")
        #expect(decision.newSelectedWorktreePath == nil)
    }

    @Test func carryForwardMatchesByBranchPreservingID() {
        let existing = repo(path: "/old/repo", worktrees: [
            ("/old/repo/.worktrees/a", "feat-a", .running),
            ("/old/repo/.worktrees/b", "feat-b", .running)
        ])
        // Discovery returns worktrees at different leaf names but same
        // branches — the carry-forward should match by branch.
        let discoveredList = [
            discovered(path: "/new/repo", branch: "main"),
            discovered(path: "/new/repo/renamed-a", branch: "feat-a"),
            discovered(path: "/new/repo/renamed-b", branch: "feat-b")
        ]

        let decision = RepoRelocator.decide(
            repo: existing,
            newRepoPath: "/new/repo",
            discovered: discoveredList,
            selectedWorktreePath: nil
        )

        let aCarry = decision.carriedForward.first { $0.newPath == "/new/repo/renamed-a" }
        let bCarry = decision.carriedForward.first { $0.newPath == "/new/repo/renamed-b" }
        #expect(aCarry?.existingID == existing.worktrees[0].id)
        #expect(bCarry?.existingID == existing.worktrees[1].id)
    }

    @Test func selectionUpdatesToNewPathWhenWorktreeCarriesForward() {
        let existing = repo(path: "/old/repo", worktrees: [
            ("/old/repo/.worktrees/feature", "feature", .running)
        ])
        let discoveredList = [discovered(path: "/new/repo/.worktrees/feature", branch: "feature")]

        let decision = RepoRelocator.decide(
            repo: existing,
            newRepoPath: "/new/repo",
            discovered: discoveredList,
            selectedWorktreePath: "/old/repo/.worktrees/feature"
        )

        #expect(decision.newSelectedWorktreePath == "/new/repo/.worktrees/feature")
    }

    @Test func twoDetachedHeadWorktreesMatchByPathLeafNotCollide() {
        let existing = repo(path: "/old/repo", worktrees: [
            ("/old/repo", "main", .closed),
            ("/old/repo/.worktrees/tag-a", "(detached)", .closed),
            ("/old/repo/.worktrees/tag-b", "(detached)", .closed)
        ])
        let discoveredList = [
            discovered(path: "/new/repo", branch: "main"),
            discovered(path: "/new/repo/.worktrees/tag-a", branch: "(detached)"),
            discovered(path: "/new/repo/.worktrees/tag-b", branch: "(detached)")
        ]

        let decision = RepoRelocator.decide(
            repo: existing,
            newRepoPath: "/new/repo",
            discovered: discoveredList,
            selectedWorktreePath: nil
        )

        #expect(decision.carriedForward.count == 3)
        #expect(decision.goneStale.isEmpty)
        let tagA = decision.carriedForward.first { $0.newPath == "/new/repo/.worktrees/tag-a" }
        let tagB = decision.carriedForward.first { $0.newPath == "/new/repo/.worktrees/tag-b" }
        #expect(tagA?.existingID == existing.worktrees[1].id)
        #expect(tagB?.existingID == existing.worktrees[2].id)
    }
}
