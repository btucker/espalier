import SwiftUI
import GrafttyKit

/// Trailing divergence indicator on each sidebar worktree row showing
/// ahead/behind commits vs. the origin default branch, with a `+` suffix
/// on the ahead count when the worktree has uncommitted changes. The
/// `+I -D` insertion/deletion detail is surfaced on hover via `.help()`
/// rather than rendered inline, keeping the sidebar uncluttered.
///
/// Renders nothing when the worktree is at parity / has no resolvable
/// origin default / is stale.
struct WorktreeRowGutter: View {
    let stats: WorktreeStats?
    let baseRef: String?
    let theme: GhosttyTheme

    var body: some View {
        if let stats, !stats.isEmpty {
            HStack(spacing: 4) {
                if let ahead = aheadToken(stats) {
                    Text(ahead)
                        .foregroundColor(theme.foreground.opacity(0.55))
                }
                if stats.behind > 0 {
                    Text("↓\(stats.behind)")
                        .foregroundColor(.red)
                }
            }
            .font(.system(size: 10, design: .monospaced))
            .help(tooltip(stats))
        }
    }

    /// `↑X[+]` with the ahead side shown (as `↑0+`) when the worktree has
    /// uncommitted changes even if ahead is zero — so the dirty indicator
    /// never disappears. Nil when neither ahead nor dirty.
    private func aheadToken(_ s: WorktreeStats) -> String? {
        guard s.ahead > 0 || s.hasUncommittedChanges else { return nil }
        return "↑\(s.ahead)\(s.hasUncommittedChanges ? "+" : "")"
    }

    /// Hover tooltip detail: the committed-diff line counts, optionally
    /// followed by a note about uncommitted work and the base ref the
    /// diff was computed against. Shape is consistent across variants so
    /// the user knows where to look.
    private func tooltip(_ s: WorktreeStats) -> String {
        var parts: [String] = []
        if s.insertions > 0 || s.deletions > 0 {
            var linesParts: [String] = []
            if s.insertions > 0 { linesParts.append("+\(s.insertions)") }
            if s.deletions > 0 { linesParts.append("-\(s.deletions)") }
            parts.append("\(linesParts.joined(separator: " ")) lines")
        }
        if s.hasUncommittedChanges {
            parts.append("uncommitted changes")
        }
        let body = parts.joined(separator: ", ")
        if let baseRef, !baseRef.isEmpty, !body.isEmpty {
            return "\(body) vs. \(baseRef)"
        }
        return body
    }
}
