#if canImport(UIKit)
import Foundation
import GhosttyTerminal
import Testing
import UIKit
@testable import GrafttyMobileKit

@MainActor
final class FakeSurfaceProxy: SurfaceProxy {
    enum Event: Equatable {
        case leftDown
        case leftUp
        case mousePos(Double, Double)
        case action(String)
    }
    var events: [Event] = []
    var selectionText: String?

    @discardableResult func sendLeftMouseDown() -> Bool {
        events.append(.leftDown)
        return true
    }
    @discardableResult func sendLeftMouseUp() -> Bool {
        events.append(.leftUp)
        return true
    }
    func sendMousePos(x: Double, y: Double) {
        events.append(.mousePos(x, y))
    }
    @discardableResult func performAction(_ name: String) -> Bool {
        events.append(.action(name))
        return true
    }
    func readSelection() -> String? { selectionText }
}

@MainActor
final class FakePasteboard: Pasteboard {
    var hasStrings: Bool { string?.isEmpty == false }
    var string: String?
}

@Suite
@MainActor
struct TerminalSelectionControllerTests {

    @Test("""
    @spec IOS-11.2: When the user taps **Select** in the long-press menu, the application shall word-select the cell under the press by synthesizing a left click followed by a held second press, so subsequent drags extend the selection across words and lines. Copy, Cancel, and Select All shall release the held button.
    """)
    func beginSelectionSynthesizesDoubleClickAtPointAndActivatesMode() {
        let surface = FakeSurfaceProxy()
        let controller = TerminalSelectionController(surface: surface)

        controller.beginSelection(at: CGPoint(x: 10, y: 20))

        #expect(controller.isActive)
        // Keep the second press down so a later drag extends this word.
        #expect(surface.events == [
            .mousePos(10, 20),
            .leftDown,
            .leftUp,
            .leftDown,
        ])
    }

    @Test
    func copyingReleasesHeldButtonBeforeClearingSelection() {
        let surface = FakeSurfaceProxy()
        let controller = TerminalSelectionController(surface: surface)
        controller.beginSelection(at: .zero)
        controller.extend(to: CGPoint(x: 120, y: 40))
        surface.selectionText = "first line\nsecond line"
        let pasteboard = FakePasteboard()
        #expect(controller.copy(toPasteboard: pasteboard) == "first line\nsecond line")
        #expect(Array(surface.events.suffix(2)) == [.leftUp, .action("clear_selection")])
    }

    @Test
    func cancelAndSelectAllReleaseHeldButton() {
        let surface = FakeSurfaceProxy()
        let controller = TerminalSelectionController(surface: surface)
        controller.beginSelection(at: .zero)
        surface.events.removeAll()
        controller.cancel()
        #expect(Array(surface.events.suffix(2)) == [.leftUp, .action("clear_selection")])
        controller.beginSelection(at: .zero)
        surface.events.removeAll()
        controller.selectAll()
        #expect(Array(surface.events.suffix(2)) == [.leftUp, .action("select_all")])
    }

    @Test
    func realSurfaceSelectionExtendsAcrossWordsAndLines() async throws {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 600, height: 400))
        let host = UIViewController()
        window.rootViewController = host
        window.makeKeyAndVisible()
        let view = UITerminalView(frame: window.bounds)
        let metrics = SelectionMetrics()
        view.delegate = metrics
        let session = InMemoryTerminalSession(write: { _ in }, resize: { _ in })
        let renderer = MobileTerminalControllerFactory.make(configText: """
        font-size = 14
        window-padding-x = 0
        window-padding-y = 0
        """)
        view.configuration = .init(backend: .inMemory(session))
        view.controller = renderer
        host.view.addSubview(view)
        defer {
            view.removeFromSuperview()
            window.isHidden = true
        }
        let surface = try #require(view.surface)
        session.receive("alpha beta gamma\r\nsecond line words")
        for _ in 0..<100 where session.readViewportText()?.contains("second line words") != true {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(session.readViewportText()?.contains("second line words") == true)
        let grid = try #require(metrics.value)
        let scale = view.contentScaleFactor
        let cellWidth = CGFloat(grid.cellWidthPixels) / scale
        let cellHeight = CGFloat(grid.cellHeightPixels) / scale
        let controller = TerminalSelectionController(surface: RealSurfaceProxy { surface })
        defer { controller.cancel() }
        controller.beginSelection(at: CGPoint(x: cellWidth * 1.5, y: cellHeight * 0.5))
        #expect(surface.readSelection() == "alpha")
        controller.extend(to: CGPoint(x: cellWidth * 8.5, y: cellHeight * 1.5))
        let selected = try #require(surface.readSelection())
        #expect(selected.contains("alpha beta gamma"))
        #expect(selected.contains("second line"))
    }

    private final class SelectionMetrics: TerminalSurfaceGridResizeDelegate {
        var value: TerminalGridMetrics?
        func terminalDidResize(_ size: TerminalGridMetrics) { value = size }
    }

    @Test("""
    @spec IOS-11.3: When the user taps **Select All** in the long-press menu, the application shall invoke libghostty's `select_all` binding action via `surface.performAction("select_all")` and shall enter selection mode for that pane with the visible viewport highlighted.
    """)
    func selectAllInvokesBindingAndActivatesMode() {
        let surface = FakeSurfaceProxy()
        let controller = TerminalSelectionController(surface: surface)

        controller.selectAll()

        #expect(controller.isActive)
        #expect(surface.events == [.action("select_all")])
    }

    @Test
    func extendForwardsToMousePosOnlyWhenActive() {
        let surface = FakeSurfaceProxy()
        let controller = TerminalSelectionController(surface: surface)

        // Inactive: extend is a no-op.
        controller.extend(to: CGPoint(x: 5, y: 5))
        #expect(surface.events.isEmpty)

        controller.beginSelection(at: CGPoint(x: 0, y: 0))
        let pre = surface.events.count
        controller.extend(to: CGPoint(x: 100, y: 200))
        #expect(surface.events.count == pre + 1)
        #expect(surface.events.last == .mousePos(100, 200))
    }

    @Test("""
    @spec IOS-11.6: When the user taps **Copy**, the application shall extract the active selection via `surface.readSelection()`, write the result to `UIPasteboard.general.string`, clear libghostty's selection, and exit selection mode. If `readSelection()` returns nil or empty, the pasteboard shall not be modified.
    """)
    func copyWritesSelectionToPasteboardAndExitsMode() {
        let surface = FakeSurfaceProxy()
        surface.selectionText = "captured"
        let pb = FakePasteboard()
        let controller = TerminalSelectionController(surface: surface)
        controller.beginSelection(at: .zero)
        surface.events.removeAll()  // ignore begin events for this assertion

        let result = controller.copy(toPasteboard: pb)

        #expect(result == "captured")
        #expect(pb.string == "captured")
        #expect(!controller.isActive)
        #expect(surface.events.contains(.action("clear_selection")))
    }

    @Test
    func copyWithEmptySelectionDoesNotTouchPasteboard() {
        let surface = FakeSurfaceProxy()
        surface.selectionText = ""
        let pb = FakePasteboard()
        pb.string = "untouched"
        let controller = TerminalSelectionController(surface: surface)
        controller.beginSelection(at: .zero)

        _ = controller.copy(toPasteboard: pb)

        #expect(pb.string == "untouched")
        #expect(!controller.isActive)
    }

    @Test
    func copyWithNilSelectionDoesNotTouchPasteboard() {
        let surface = FakeSurfaceProxy()
        surface.selectionText = nil
        let pb = FakePasteboard()
        pb.string = "untouched"
        let controller = TerminalSelectionController(surface: surface)
        controller.beginSelection(at: .zero)

        _ = controller.copy(toPasteboard: pb)

        #expect(pb.string == "untouched")
        #expect(!controller.isActive)
    }

    @Test("""
    @spec IOS-11.7: When the user taps **Cancel**, taps outside the highlighted selection, or presses a key on the terminal control bar while in selection mode, the application shall clear libghostty's selection and exit selection mode without modifying the pasteboard.
    """)
    func cancelClearsSelectionAndExitsModeWithoutPasteboard() {
        let surface = FakeSurfaceProxy()
        surface.selectionText = "would-have-been-copied"
        let pb = FakePasteboard()
        pb.string = "untouched"
        let controller = TerminalSelectionController(surface: surface)
        controller.beginSelection(at: .zero)

        controller.cancel()

        #expect(pb.string == "untouched")
        #expect(!controller.isActive)
        #expect(surface.events.contains(.action("clear_selection")))
    }

    @Test("""
    @spec IOS-11.10: Selection mode shall be per-pane state owned by the focused pane's `TerminalSelectionController`. Selection in one pane shall not affect the selection state of any other pane.
    """)
    func twoControllersHaveIndependentState() {
        let aSurface = FakeSurfaceProxy()
        let bSurface = FakeSurfaceProxy()
        let a = TerminalSelectionController(surface: aSurface)
        let b = TerminalSelectionController(surface: bSurface)

        a.beginSelection(at: .zero)
        #expect(a.isActive)
        #expect(!b.isActive)
        #expect(bSurface.events.isEmpty)
    }
}
#endif
