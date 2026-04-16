import SwiftUI
import AppKit

/// Applies a color to the host `NSWindow`'s `backgroundColor`. Used to tint
/// the area behind the traffic-lights (the transparent hidden-title-bar
/// region) so it doesn't render as system default white/light-gray behind
/// our ghostty-themed content.
///
/// Without this, `.windowStyle(.hiddenTitleBar)` leaves a visible strip of
/// NSWindow chrome peeking through above the content.
struct WindowBackgroundTint: NSViewRepresentable {
    let color: Color

    func makeNSView(context: Context) -> NSView {
        let view = TintView()
        view.tint = nsColor(color)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? TintView)?.tint = nsColor(color)
        (nsView as? TintView)?.apply()
    }

    private func nsColor(_ color: Color) -> NSColor {
        NSColor(color)
    }

    private final class TintView: NSView {
        var tint: NSColor = .windowBackgroundColor

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            apply()
        }

        func apply() {
            guard let window else { return }
            window.backgroundColor = tint
            window.titlebarAppearsTransparent = true
        }
    }
}

extension View {
    /// Tint the host NSWindow's background color. Use with
    /// `.windowStyle(.hiddenTitleBar)` to make the title-bar area match
    /// the content chrome.
    func windowBackgroundTint(_ color: Color) -> some View {
        background(WindowBackgroundTint(color: color))
    }
}
