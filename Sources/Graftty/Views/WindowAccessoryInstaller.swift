import SwiftUI
import AppKit
import GrafttyKit

/// Installs the update-badge titlebar accessory on the host `NSWindow`
/// once the view is attached. Mirrors the `NSViewRepresentable` +
/// `viewDidMoveToWindow` pattern used by `WindowBackgroundTint`.
struct WindowAccessoryInstaller: NSViewRepresentable {
    let updaterController: UpdaterController

    func makeNSView(context: Context) -> NSView {
        let view = InstallerView()
        view.updaterController = updaterController
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? InstallerView)?.updaterController = updaterController
    }

    private final class InstallerView: NSView {
        var updaterController: UpdaterController?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window, let controller = updaterController else { return }
            let accessory = UpdaterTitlebarAccessory(controller: controller)
            accessory.install(on: window)
        }
    }
}

extension View {
    /// Install the update-badge accessory in the host window's titlebar.
    func installUpdateBadgeAccessory(controller: UpdaterController) -> some View {
        background(WindowAccessoryInstaller(updaterController: controller))
    }
}
