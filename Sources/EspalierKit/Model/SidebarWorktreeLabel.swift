import Foundation

/// User-facing label for a worktree in sidebar-adjacent surfaces —
/// the left-side selection row, right-click "Move to <worktree>"
/// menu items, and anywhere else the worktree needs a short name.
///
/// Splits on the main-vs-linked distinction:
///   - Main checkout (path == repo.path): the branch name, sanitized
///     via `displayBranch` so a collaborator-controlled branch with a
///     Unicode BIDI-override scalar can't render RTL-reversed in the
///     menu. The sidebar icon disambiguates main vs linked, so there's
///     no disambiguation-suffix work to do.
///   - Linked worktree: `WorktreeEntry.displayName(amongSiblingPaths:)`
///     — collision-aware directory name. Directory names are
///     user-owned, not a Trojan-Source surface.
///
/// Extracted from `SidebarView.label(for:in:)` so the main-checkout
/// path can be unit-tested end-to-end (SwiftUI views resist direct
/// testing) and so the same helper can't drift between menu item
/// surfaces that share this label form.
public enum SidebarWorktreeLabel {
    public static func text(
        for worktree: WorktreeEntry,
        inRepoAtPath repoPath: String,
        siblingPaths: [String]
    ) -> String {
        if worktree.path == repoPath {
            return worktree.displayBranch
        }
        return worktree.displayName(amongSiblingPaths: siblingPaths)
    }
}
