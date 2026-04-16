import SwiftUI
import EspalierKit

/// The row that sits at the very top of the window, replacing the macOS
/// title bar. Shows the selected repo/worktree context and leaves ~72pt of
/// leading padding for the traffic lights (which still render on top of the
/// content thanks to `.windowStyle(.hiddenTitleBar)`).
struct BreadcrumbBar: View {
    let repoName: String?
    let branchName: String?
    let path: String?
    let theme: GhosttyTheme

    /// Leading padding to leave room for the traffic lights (close/min/zoom).
    /// macOS renders them at ~(20, 14) with ~60pt of total width; we use 72
    /// for a tiny safety margin.
    private static let trafficLightsReservedWidth: CGFloat = 72

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
        .padding(.leading, Self.trafficLightsReservedWidth)
        .padding(.trailing, 12)
        .padding(.vertical, 8)
        .background(theme.background)
    }
}
