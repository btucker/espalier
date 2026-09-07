#if canImport(UIKit)
import CoreGraphics

/// IOS-11.x: per-pane selection state machine. Drives libghostty's
/// native selection through a `SurfaceProxy`, extracts selection text
/// via `SurfaceProxy.readSelection`, writes to a `Pasteboard`. Pure
/// logic — no UIKit imports beyond `CGPoint` (CoreGraphics).
@MainActor
public final class TerminalSelectionController {
    public private(set) var isActive: Bool = false
    private var isLeftMouseDown = false
    private let surface: SurfaceProxy

    public init(surface: SurfaceProxy) {
        self.surface = surface
    }

    /// IOS-11.2: word-select via synthesized double-click at `point`.
    public func beginSelection(at point: CGPoint) {
        releaseMouseButton()
        surface.sendMousePos(x: Double(point.x), y: Double(point.y))
        // Two left-clicks at the same point — libghostty's mouse handler
        // promotes back-to-back presses within its double-click window
        // to word-select semantics.
        surface.sendLeftMouseDown()
        surface.sendLeftMouseUp()
        surface.sendLeftMouseDown()
        isLeftMouseDown = true
        isActive = true
    }

    /// IOS-11.3: full-viewport select via libghostty's `select_all` binding.
    public func selectAll() {
        releaseMouseButton()
        surface.performAction("select_all")
        isActive = true
    }

    /// IOS-11.4: forward pan to libghostty's mouse-position handler,
    /// which extends the current selection while the second LEFT press
    /// remains held. Finger lifts keep that anchor until Copy or Cancel,
    /// allowing another drag to adjust the same selection.
    public func extend(to point: CGPoint) {
        guard isActive else { return }
        surface.sendMousePos(x: Double(point.x), y: Double(point.y))
    }

    /// Stop edge autoscrolling while retaining the held selection anchor.
    public func endExtension(at point: CGPoint, viewportHeight: CGFloat, displayScale: CGFloat) {
        guard isActive else { return }
        let scale = max(1, displayScale)
        let heightPixels = (viewportHeight * scale).rounded(.down)
        // Ghostty scrolls within one pixel of an edge and ignores mouse
        // moves smaller than one pixel. Two pixels crosses both thresholds.
        let inset = min(2, heightPixels / 2)
        let yPixels = min(max(point.y * scale, inset), heightPixels - inset)
        extend(to: CGPoint(x: point.x, y: yPixels / scale))
    }

    /// IOS-11.6: extract + clipboard + clear + exit. Returns the copied
    /// text (or nil if there was nothing to copy).
    @discardableResult
    public func copy(toPasteboard pb: Pasteboard) -> String? {
        defer { exit() }
        guard let text = surface.readSelection(), !text.isEmpty else {
            return nil
        }
        var pb = pb
        pb.string = text
        return text
    }

    /// IOS-11.7: clear libghostty's selection and exit mode without
    /// touching the pasteboard.
    public func cancel() {
        exit()
    }

    private func exit() {
        releaseMouseButton()
        surface.performAction("clear_selection")
        isActive = false
    }

    private func releaseMouseButton() {
        guard isLeftMouseDown else { return }
        surface.sendLeftMouseUp()
        isLeftMouseDown = false
    }
}
#endif
