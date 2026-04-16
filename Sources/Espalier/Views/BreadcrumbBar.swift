import SwiftUI
import EspalierKit

/// The row that sits at the very top of the detail column. Shows the
/// selected repo/worktree context. Aligns to the left edge of the
/// terminal content below — the traffic lights live over the sidebar
/// column, not this one, so no reserved width is needed.
struct BreadcrumbBar: View {
    let repoName: String?
    let branchName: String?
    let path: String?
    let theme: GhosttyTheme

    var body: some View {
        HStack(spacing: 4) {
            if let repoName {
                Text(repoName)
                    .foregroundColor(theme.foreground.opacity(0.6))
            }
            if branchName != nil {
                Text("/")
                    .foregroundColor(theme.foreground.opacity(0.3))
            }
            if let branchName {
                Text(branchName)
                    .foregroundColor(theme.foreground)
                    .fontWeight(.medium)
            }
            Spacer()
            if let path {
                Text(path)
                    .font(.caption)
                    .foregroundColor(theme.foreground.opacity(0.5))
            }
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(theme.background)
    }
}
