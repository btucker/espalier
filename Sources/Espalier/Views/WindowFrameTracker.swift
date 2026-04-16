import SwiftUI
import AppKit

/// Attach to a view to track its window's frame. Reports frame changes
/// (move + resize) to the callback, debounced so rapid drags don't
/// generate a flood of writes.
struct WindowFrameTracker: NSViewRepresentable {
    let debounceInterval: TimeInterval
    let onFrameChange: (CGRect) -> Void

    init(debounceInterval: TimeInterval = 0.25, onFrameChange: @escaping (CGRect) -> Void) {
        self.debounceInterval = debounceInterval
        self.onFrameChange = onFrameChange
    }

    func makeNSView(context: Context) -> NSView {
        let view = TrackerNSView()
        view.coordinator = context.coordinator
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onFrameChange: onFrameChange, debounceInterval: debounceInterval)
    }

    @MainActor
    final class Coordinator {
        private let onFrameChange: (CGRect) -> Void
        private let debounceInterval: TimeInterval
        private var observers: [NSObjectProtocol] = []
        private var pendingTask: Task<Void, Never>?
        private weak var window: NSWindow?

        init(onFrameChange: @escaping (CGRect) -> Void, debounceInterval: TimeInterval) {
            self.onFrameChange = onFrameChange
            self.debounceInterval = debounceInterval
        }

        func attach(to window: NSWindow) {
            guard self.window !== window else { return }
            detach()
            self.window = window

            let nc = NotificationCenter.default
            let resize = nc.addObserver(
                forName: NSWindow.didResizeNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.scheduleFrameChange() }
            }
            let move = nc.addObserver(
                forName: NSWindow.didMoveNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.scheduleFrameChange() }
            }
            observers = [resize, move]
        }

        func detach() {
            observers.forEach(NotificationCenter.default.removeObserver)
            observers.removeAll()
            pendingTask?.cancel()
            pendingTask = nil
            window = nil
        }

        private func scheduleFrameChange() {
            pendingTask?.cancel()
            guard let window else { return }
            let frame = window.frame
            pendingTask = Task { [weak self] in
                guard let self else { return }
                try? await Task.sleep(for: .seconds(self.debounceInterval))
                if Task.isCancelled { return }
                self.onFrameChange(frame)
            }
        }

        deinit {
            observers.forEach(NotificationCenter.default.removeObserver)
        }
    }

    private final class TrackerNSView: NSView {
        var coordinator: Coordinator?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            MainActor.assumeIsolated {
                coordinator?.attach(to: window)
            }
        }
    }
}

extension View {
    /// Observe the host window's frame; callback is debounced so rapid drags
    /// don't spam writes.
    func trackWindowFrame(
        debounceInterval: TimeInterval = 0.25,
        onChange: @escaping (CGRect) -> Void
    ) -> some View {
        background(WindowFrameTracker(debounceInterval: debounceInterval, onFrameChange: onChange))
    }
}
