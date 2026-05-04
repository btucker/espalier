import SwiftUI
import AppKit
import GrafttyKit

struct PRButton: View {
    let info: PRInfo
    let theme: GhosttyTheme
    let onRefresh: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            statusDot

            Text("#\(info.number)\(info.state == .merged ? " ✓ merged" : "")")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(info.state == .merged ? info.state.statusColor : theme.foreground)

            Text(info.title)
                .font(.caption)
                .foregroundColor(theme.foreground.opacity(0.55))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 260, alignment: .leading)

            if info.state == .open && info.mergeable == .conflicting {
                Text("merge conflict")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .foregroundColor(PRInfo.Mergeable.conflicting.statusColor)
                    .background(
                        Capsule().fill(PRInfo.Mergeable.conflicting.statusColor.opacity(0.18))
                    )
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .background(background)
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(theme.foreground.opacity(0.12), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .help("Open #\(info.number) on \(info.url.host ?? "")")
        .accessibilityLabel(
            "Pull request \(info.number), \(accessibilityChecks), \(info.title). Click to open in browser."
        )
        .contentShape(Rectangle())
        .onTapGesture { NSWorkspace.shared.open(info.url) }
        .contextMenu {
            Button("Refresh now") { onRefresh() }
            Button("Copy URL") { Pasteboard.copy(info.url.absoluteString) }
        }
    }

    private var background: Color {
        info.state == .merged
            ? Color(red: 0.64, green: 0.44, blue: 0.97, opacity: 0.15)
            : theme.foreground.opacity(0.08)
    }

    @ViewBuilder
    private var statusDot: some View {
        if info.checks == .pending {
            PendingCIPulseDot(color: PendingCIIndicatorMotion.pendingNSColor)
                .frame(width: 8, height: 8)
                .overlay(
                    Circle()
                        .stroke(dotColor.opacity(0.5), lineWidth: 2)
                )
        } else {
            Circle()
                .fill(dotColor)
                .frame(width: 8, height: 8)
        }
    }

    private var dotColor: Color { info.checks.statusColor }

    private var accessibilityChecks: String {
        switch info.checks {
        case .success: return "CI passing"
        case .failure: return "CI failing"
        case .pending: return "CI running"
        case .none:    return "no CI checks"
        }
    }
}

extension PRInfo.State {
    /// Color representing this PR's state. Green for open, purple for
    /// merged. Shared between the sidebar badge (foreground color of
    /// `#<number>`) and the breadcrumb pill (foreground color when
    /// merged). A future `.closed` case maps to red here.
    var statusColor: Color {
        switch self {
        case .open:   return Color(red: 0.25, green: 0.73, blue: 0.31)
        case .merged: return Color(red: 0.82, green: 0.66, blue: 1.0)
        }
    }
}

extension PRInfo.Checks {
    /// Color encoding the CI verdict. Reused by the breadcrumb PR
    /// button's dot and, per `PR-3.5`, the sidebar `#<number>` badge.
    /// The `.success` green intentionally matches `PRInfo.State.open`
    /// so an open PR with passing CI reads as a single signal.
    var statusColor: Color {
        switch self {
        case .success: return PRInfo.State.open.statusColor
        case .failure: return Color(red: 0.97, green: 0.32, blue: 0.29)
        case .pending: return Color(red: 0.82, green: 0.60, blue: 0.13)
        case .none:    return Color(red: 0.43, green: 0.46, blue: 0.51)
        }
    }
}

extension PRInfo.Mergeable {
    /// Color for the merge-conflict cue. Distinct from CI failure
    /// red so a "PR has conflicts but CI is green" state reads
    /// differently from "PR is broken in CI". Used by the sidebar
    /// `#<number>` badge when `PRBadgeStyle` returns `.conflicting`
    /// and by the breadcrumb's "merge conflict" pill.
    var statusColor: Color {
        switch self {
        case .conflicting: return Color(red: 0.95, green: 0.46, blue: 0.20)
        case .mergeable, .unknown: return PRInfo.State.open.statusColor
        }
    }
}

/// Static emphasis for a pending CI indicator.
enum PendingCIIndicatorMotion {
    static let usesContinuousSwiftUIStateLoop = false
    static let usesCompositorLayerAnimation = true
    static let pendingOpacity = 0.9
    static let pulseAnimationKey = "graftty.pending-ci.opacity"
    static let pulseDuration = 0.9
    static let pendingNSColor = NSColor(calibratedRed: 0.82, green: 0.60, blue: 0.13, alpha: 1.0)

    static func opacity(isPending: Bool) -> Double {
        isPending ? pendingOpacity : 1.0
    }
}

struct PendingCIEmphasis: ViewModifier {
    let isPending: Bool

    func body(content: Content) -> some View {
        content
            .opacity(PendingCIIndicatorMotion.opacity(isPending: isPending))
    }
}

struct PendingCIPulseDot: NSViewRepresentable {
    let color: NSColor

    func makeNSView(context: Context) -> PendingCIPulseNSView {
        PendingCIPulseNSView(color: color)
    }

    func updateNSView(_ nsView: PendingCIPulseNSView, context: Context) {
        nsView.color = color
    }
}

final class PendingCIPulseNSView: NSView {
    var color: NSColor {
        didSet { layer?.backgroundColor = color.cgColor }
    }

    init(color: NSColor) {
        self.color = color
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = color.cgColor
        layer?.masksToBounds = true
        startPulse()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        layer?.cornerRadius = min(bounds.width, bounds.height) / 2
    }

    private func startPulse() {
        guard layer?.animation(forKey: PendingCIIndicatorMotion.pulseAnimationKey) == nil else { return }
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = 1.0
        animation.toValue = 0.45
        animation.duration = PendingCIIndicatorMotion.pulseDuration
        animation.autoreverses = true
        animation.repeatCount = .infinity
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer?.add(animation, forKey: PendingCIIndicatorMotion.pulseAnimationKey)
    }
}
