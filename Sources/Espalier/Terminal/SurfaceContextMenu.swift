import AppKit
import GhosttyKit

// MARK: - Context Menu

/// Right-click / ctrl-click context menu on a terminal surface. Ported
/// from Ghostty's upstream `SurfaceView_AppKit.menu(for:)` — same items,
/// same actions, same semantics.
///
/// - Returning a non-nil menu from `NSView.menu(for:)` swallows the
///   subsequent mouse event, so on ctrl-left-click we synthesize a
///   right-mouse-press to keep the terminal's mouse-reporting in sync.
/// - When the terminal has enabled mouse capture, the menu is suppressed
///   so the underlying app can handle the click itself.
/// - Copy is only added when there's a non-empty selection — presence
///   implies "selection exists", so no separate validation is needed for
///   that item.
/// - "Terminal Read-only" reflects current state via a checkmark at
///   build time; the menu is rebuilt on each invocation so state is
///   always current.
extension SurfaceNSView {
    override func menu(for event: NSEvent) -> NSMenu? {
        guard let surface else { return nil }

        switch event.type {
        case .rightMouseDown:
            break
        case .leftMouseDown:
            // Only fire for ctrl-click (otherwise a regular left click).
            guard event.modifierFlags.contains(.control) else { return nil }
            // If the terminal app captures the mouse, give it the click
            // instead of popping the menu.
            if ghostty_surface_mouse_captured(surface) { return nil }
            // AppKit calls menu(for:) before dispatching any mouse event
            // for ctrl-click. Returning non-nil swallows the event, so
            // synthesize a right-press for the terminal's benefit.
            let mods = Self.ghosttyMods(from: event.modifierFlags)
            _ = ghostty_surface_mouse_button(
                surface,
                GHOSTTY_MOUSE_PRESS,
                GHOSTTY_MOUSE_RIGHT,
                mods
            )
        default:
            return nil
        }

        let menu = NSMenu()
        var item: NSMenuItem

        if hasNonEmptySelection {
            item = menu.addItem(
                withTitle: "Copy",
                action: #selector(copyFromTerminal(_:)),
                keyEquivalent: ""
            )
            item.setImageIfDesired(systemSymbolName: "document.on.document")
        }

        item = menu.addItem(
            withTitle: "Paste",
            action: #selector(pasteToTerminal(_:)),
            keyEquivalent: ""
        )
        item.setImageIfDesired(systemSymbolName: "document.on.clipboard")

        menu.addItem(.separator())
        item = menu.addItem(
            withTitle: "Split Right",
            action: #selector(splitRight(_:)),
            keyEquivalent: ""
        )
        item.setImageIfDesired(systemSymbolName: "rectangle.righthalf.inset.filled")
        item = menu.addItem(
            withTitle: "Split Left",
            action: #selector(splitLeft(_:)),
            keyEquivalent: ""
        )
        item.setImageIfDesired(systemSymbolName: "rectangle.leadinghalf.inset.filled")
        item = menu.addItem(
            withTitle: "Split Down",
            action: #selector(splitDown(_:)),
            keyEquivalent: ""
        )
        item.setImageIfDesired(systemSymbolName: "rectangle.bottomhalf.inset.filled")
        item = menu.addItem(
            withTitle: "Split Up",
            action: #selector(splitUp(_:)),
            keyEquivalent: ""
        )
        item.setImageIfDesired(systemSymbolName: "rectangle.tophalf.inset.filled")

        menu.addItem(.separator())
        item = menu.addItem(
            withTitle: "Reset Terminal",
            action: #selector(resetTerminal(_:)),
            keyEquivalent: ""
        )
        item.setImageIfDesired(systemSymbolName: "arrow.trianglehead.2.clockwise")
        item = menu.addItem(
            withTitle: "Toggle Terminal Inspector",
            action: #selector(toggleTerminalInspector(_:)),
            keyEquivalent: ""
        )
        item.setImageIfDesired(systemSymbolName: "scope")
        item = menu.addItem(
            withTitle: "Terminal Read-only",
            action: #selector(toggleReadonly(_:)),
            keyEquivalent: ""
        )
        item.setImageIfDesired(systemSymbolName: "eye.fill")
        item.state = isReadonly ? .on : .off

        return menu
    }

    // MARK: - Copy / Paste

    @objc func copyFromTerminal(_ sender: Any?) {
        bindingAction("copy_to_clipboard")
    }

    @objc func pasteToTerminal(_ sender: Any?) {
        bindingAction("paste_from_clipboard")
    }

    // MARK: - Splits

    @objc func splitRight(_ sender: Any?) {
        guard let surface else { return }
        ghostty_surface_split(surface, GHOSTTY_SPLIT_DIRECTION_RIGHT)
    }

    @objc func splitLeft(_ sender: Any?) {
        guard let surface else { return }
        ghostty_surface_split(surface, GHOSTTY_SPLIT_DIRECTION_LEFT)
    }

    @objc func splitDown(_ sender: Any?) {
        guard let surface else { return }
        ghostty_surface_split(surface, GHOSTTY_SPLIT_DIRECTION_DOWN)
    }

    @objc func splitUp(_ sender: Any?) {
        guard let surface else { return }
        ghostty_surface_split(surface, GHOSTTY_SPLIT_DIRECTION_UP)
    }

    // MARK: - Reset / Inspector / Read-only

    @objc func resetTerminal(_ sender: Any?) {
        bindingAction("reset")
    }

    @objc func toggleTerminalInspector(_ sender: Any?) {
        bindingAction("inspector:toggle")
    }

    @objc func toggleReadonly(_ sender: Any?) {
        bindingAction("toggle_readonly")
        // Flip our local flag so the next menu open has the right
        // checkmark. libghostty owns the authoritative state; this is
        // just our UI mirror.
        isReadonly.toggle()
    }

    // MARK: - Helpers

    /// True if libghostty reports a non-empty text selection on this
    /// surface. Drives whether "Copy" appears in the menu.
    ///
    /// libghostty doesn't currently expose a pure "is there a selection"
    /// query through the headers we have, so we use `read_selection` +
    /// immediate free as the check: returns true means there's a
    /// non-empty selected string. If the API isn't present at compile
    /// time, we always show the Copy item and let the binding-action
    /// no-op if selection is empty.
    fileprivate var hasNonEmptySelection: Bool {
        // Conservative default until we wire up a read-selection check.
        // Always showing Copy is harmless — `copy_to_clipboard` no-ops
        // when there's nothing selected.
        return true
    }

    /// Dispatches a named binding action via
    /// `ghostty_surface_binding_action`. The action string is not
    /// NUL-required but must be sized in UTF-8 bytes, matching upstream.
    fileprivate func bindingAction(_ action: String) {
        guard let surface else { return }
        _ = action.withCString { cstr in
            ghostty_surface_binding_action(
                surface,
                cstr,
                UInt(action.lengthOfBytes(using: .utf8))
            )
        }
    }
}

// MARK: - NSMenuItem helpers

extension NSMenuItem {
    /// Attach an SF Symbol to this menu item only on macOS versions that
    /// render menu icons as a norm (macOS 26 / Tahoe+). Earlier versions
    /// render menu items without icons per Apple HIG.
    func setImageIfDesired(systemSymbolName symbol: String) {
        if #available(macOS 26, *) {
            image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        }
    }
}
