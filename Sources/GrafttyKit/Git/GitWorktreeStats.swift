import Foundation

/// Ephemeral per-worktree divergence information vs. the worktree's
/// upstream refs (union of `origin/<defaultBranch>` and `origin/<branch>`
/// when both exist). Not persisted — lives in `WorktreeStatsStore` for
/// the session only.
public struct WorktreeStats: Equatable, Sendable {
    public let ahead: Int
    public let behind: Int
    public let insertions: Int
    public let deletions: Int
    /// True when the worktree has modified, staged, deleted, or untracked
    /// files. Surfaced inline as a `+` suffix on the ahead count so the
    /// user can distinguish "clean branch, 2 commits ahead" from
    /// "2 commits ahead plus work in progress" at a glance.
    public let hasUncommittedChanges: Bool

    public init(
        ahead: Int,
        behind: Int,
        insertions: Int,
        deletions: Int,
        hasUncommittedChanges: Bool = false
    ) {
        self.ahead = ahead
        self.behind = behind
        self.insertions = insertions
        self.deletions = deletions
        self.hasUncommittedChanges = hasUncommittedChanges
    }

    public var isEmpty: Bool {
        ahead == 0 && behind == 0 && insertions == 0 && deletions == 0 && !hasUncommittedChanges
    }
}

/// The set of refs a worktree's divergence is measured against. Always
/// at least `defaultRef` (the repo's `origin/<defaultBranch>`); also
/// includes `branchRef` = `origin/<worktree-branch>` when that tracking
/// ref exists. `↓N` is computed as the union — "commits reachable from
/// any upstream ref but not HEAD" — so a PR merge on the default branch
/// *and* a collaborator push to the worktree's own branch both surface
/// as new behind commits, on every worktree that doesn't yet have them.
public struct UpstreamRefs: Equatable, Sendable {
    public let defaultRef: String
    public let branchRef: String?

    public init(defaultRef: String, branchRef: String? = nil) {
        self.defaultRef = defaultRef
        // Collapse the degenerate "branch == default" case (home checkout
        // on the default branch) so `rev-list` isn't handed the same ref
        // twice and the tooltip doesn't render `"origin/main + origin/main"`.
        self.branchRef = (branchRef == defaultRef) ? nil : branchRef
    }

    /// Every ref to include on the reachable side of `rev-list`.
    public var all: [String] {
        branchRef.map { [defaultRef, $0] } ?? [defaultRef]
    }

    /// Human-readable label for the sidebar tooltip: either the single
    /// default ref or both refs joined with `" + "`.
    public var displayLabel: String {
        branchRef.map { "\(defaultRef) + \($0)" } ?? defaultRef
    }
}

public enum GitWorktreeStats {

    /// Picks the upstream refs to measure against for a given worktree.
    /// Always includes `origin/<defaultBranch>` so a PR merge on the
    /// default branch surfaces on every worktree — including linked
    /// feature-branch worktrees that don't have the merged commits yet.
    /// Additionally includes `origin/<branch>` when that tracking ref
    /// exists, so a collaborator push to the worktree's own branch also
    /// surfaces. Returns nil when the default branch isn't resolvable
    /// (callers already gate rendering on that, per `DIVERGE-1.5`).
    public static func resolveUpstreamRefs(
        worktreePath: String,
        branch: String,
        defaultBranch: String
    ) async -> UpstreamRefs {
        let defaultRef = "origin/\(defaultBranch)"
        guard !branch.isEmpty, branch != defaultBranch else {
            return UpstreamRefs(defaultRef: defaultRef)
        }
        let branchCandidate = "origin/\(branch)"
        guard let captured = try? await GitRunner.capture(
            args: ["show-ref", "--verify", "--quiet", "refs/remotes/\(branchCandidate)"],
            at: worktreePath
        ), captured.exitCode == 0 else {
            return UpstreamRefs(defaultRef: defaultRef)
        }
        return UpstreamRefs(defaultRef: defaultRef, branchRef: branchCandidate)
    }

    /// Parse `git rev-list --count …` output — a single non-negative
    /// integer on its own line. Returns nil on non-numeric input.
    public static func parseSingleCount(_ output: String) -> Int? {
        Int(output.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Parse output of `git diff --shortstat`. Empty output means no diff —
    /// return (0, 0) rather than failing, since "no changes" is a valid answer.
    public static func parseShortStat(_ output: String) -> (insertions: Int, deletions: Int) {
        var insertions = 0
        var deletions = 0
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return (0, 0) }
        for part in trimmed.split(separator: ",") {
            let token = part.trimmingCharacters(in: .whitespaces)
            if token.contains("insertion"), let n = leadingInt(token) {
                insertions = n
            } else if token.contains("deletion"), let n = leadingInt(token) {
                deletions = n
            }
        }
        return (insertions: insertions, deletions: deletions)
    }

    private static func leadingInt(_ s: String) -> Int? {
        var digits = ""
        for ch in s {
            if ch.isWholeNumber { digits.append(ch) } else if !digits.isEmpty { break }
        }
        return Int(digits)
    }

    /// Computes divergence stats for a worktree vs. the union of its
    /// upstream refs. Runs four local git commands in sequence; each is
    /// awaited so callers yield rather than block. Throws if git fails
    /// to launch or exits non-zero.
    ///
    /// Semantics:
    /// - `behind` = commits reachable from any upstream ref but not
    ///   HEAD. `git rev-list` natively dedupes so overlap (e.g. a push
    ///   to `origin/<branch>` that was already rebased onto `origin/<default>`)
    ///   is counted once.
    /// - `ahead` = commits reachable from HEAD but not from any
    ///   upstream ref — the user's truly unpushed local work.
    /// - Lines and dirty-flag semantics unchanged; the `git diff` uses
    ///   the worktree's own branch upstream when present (so the
    ///   tooltip describes "your work on this branch"), falling back
    ///   to the default ref.
    public static func compute(
        worktreePath: String,
        upstreamRefs: UpstreamRefs
    ) async throws -> WorktreeStats {
        let allRefs = upstreamRefs.all

        let behindArgs = ["rev-list", "--count"] + allRefs + ["^HEAD"]
        let behindOutput: String
        do {
            behindOutput = try await GitRunner.run(args: behindArgs, at: worktreePath)
        } catch let err as CLIError {
            throw GitWorktreeStatsError.gitFailed(err)
        }
        guard let behind = parseSingleCount(behindOutput) else {
            throw GitWorktreeStatsError.unparseableRevList(behindOutput)
        }

        var aheadArgs = ["rev-list", "--count", "HEAD"]
        aheadArgs.append(contentsOf: allRefs.map { "^\($0)" })
        let aheadOutput: String
        do {
            aheadOutput = try await GitRunner.run(args: aheadArgs, at: worktreePath)
        } catch let err as CLIError {
            throw GitWorktreeStatsError.gitFailed(err)
        }
        guard let ahead = parseSingleCount(aheadOutput) else {
            throw GitWorktreeStatsError.unparseableRevList(aheadOutput)
        }

        // Lines: use the worktree's own branch upstream when present,
        // else the default. `branch...HEAD` (three-dot) counts work from
        // the merge-base forward — i.e. "your commits on this branch".
        let diffBase = upstreamRefs.branchRef ?? upstreamRefs.defaultRef
        let diffOutput: String
        do {
            diffOutput = try await GitRunner.run(
                args: ["diff", "--shortstat", "\(diffBase)...HEAD"],
                at: worktreePath
            )
        } catch let err as CLIError {
            throw GitWorktreeStatsError.gitFailed(err)
        }
        let diff = parseShortStat(diffOutput)

        let statusOutput: String
        do {
            statusOutput = try await GitRunner.run(
                args: ["status", "--porcelain"],
                at: worktreePath
            )
        } catch let err as CLIError {
            throw GitWorktreeStatsError.gitFailed(err)
        }
        let dirty = !statusOutput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        return WorktreeStats(
            ahead: ahead,
            behind: behind,
            insertions: diff.insertions,
            deletions: diff.deletions,
            hasUncommittedChanges: dirty
        )
    }
}

public enum GitWorktreeStatsError: Swift.Error, Equatable {
    case gitFailed(CLIError)
    case unparseableRevList(String)
}
