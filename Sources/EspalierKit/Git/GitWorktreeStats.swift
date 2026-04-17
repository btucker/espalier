import Foundation

/// Ephemeral per-worktree divergence information vs. the origin default branch.
/// Not persisted — lives in `WorktreeStatsStore` for the session only.
public struct WorktreeStats: Equatable, Sendable {
    public let ahead: Int
    public let behind: Int
    public let insertions: Int
    public let deletions: Int

    public init(ahead: Int, behind: Int, insertions: Int, deletions: Int) {
        self.ahead = ahead
        self.behind = behind
        self.insertions = insertions
        self.deletions = deletions
    }

    public var isEmpty: Bool {
        ahead == 0 && behind == 0 && insertions == 0 && deletions == 0
    }
}

public enum GitWorktreeStats {

    /// Parse output of `git rev-list --left-right --count <ref>...HEAD`.
    /// A single line of the form `<left>\t<right>\n`, where left = commits
    /// reachable from `<ref>` but not HEAD (behind), right = commits
    /// reachable from HEAD but not `<ref>` (ahead).
    public static func parseRevListCounts(_ output: String) -> (behind: Int, ahead: Int)? {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let parts = trimmed.split(separator: "\t", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let behind = Int(parts[0].trimmingCharacters(in: .whitespaces)),
              let ahead = Int(parts[1].trimmingCharacters(in: .whitespaces)) else {
            return nil
        }
        return (behind: behind, ahead: ahead)
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
}
