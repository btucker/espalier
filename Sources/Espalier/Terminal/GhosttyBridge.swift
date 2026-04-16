import Foundation
import GhosttyKit
import SwiftUI

// MARK: - GhosttyConfig

/// Swift wrapper around `ghostty_config_t`.
///
/// Lifecycle: `ghostty_config_new` -> load defaults -> finalize -> hand to `GhosttyApp`.
/// `ghostty_app_new` takes ownership of the config on success, so this wrapper only frees
/// the config if ownership was never transferred.
final class GhosttyConfig {
    /// Underlying C handle (`ghostty_config_t` is `typedef void*`).
    let config: ghostty_config_t

    /// Set to `true` once ownership is transferred to a `ghostty_app_t`.
    fileprivate var ownershipTransferred: Bool = false

    init() {
        config = ghostty_config_new()
        ghostty_config_load_default_files(config)
        ghostty_config_finalize(config)
    }

    deinit {
        if !ownershipTransferred {
            ghostty_config_free(config)
        }
    }

    /// Read a `ghostty_config_color_s` value from the config by key (e.g.
    /// "background", "foreground", "cursor-color"). Returns nil if the key
    /// is unknown or the value isn't set.
    func color(forKey key: String) -> ghostty_config_color_s? {
        var color = ghostty_config_color_s()
        let ok = key.withCString { keyPtr -> Bool in
            ghostty_config_get(config, &color, keyPtr, UInt(strlen(keyPtr)))
        }
        return ok ? color : nil
    }
}

extension ghostty_config_color_s {
    /// Convert a libghostty RGB triple to a SwiftUI color.
    var swiftUIColor: Color {
        Color(
            .sRGB,
            red: Double(r) / 255.0,
            green: Double(g) / 255.0,
            blue: Double(b) / 255.0,
            opacity: 1.0
        )
    }
}

// MARK: - GhosttyTheme

/// Snapshot of the ghostty-config-driven theme colors we apply to Espalier's
/// app chrome (sidebar, title bar, breadcrumb) so the whole window visually
/// matches the terminal's appearance.
struct GhosttyTheme: Equatable {
    let background: Color
    let foreground: Color

    /// Fallback theme used when ghostty config is unavailable or doesn't
    /// specify background/foreground. Matches macOS dark-mode defaults so
    /// things don't look broken.
    static let fallback = GhosttyTheme(
        background: Color(.sRGB, red: 0.05, green: 0.05, blue: 0.1, opacity: 1),
        foreground: Color(.sRGB, red: 0.87, green: 0.87, blue: 0.87, opacity: 1)
    )

    /// Read theme colors from a `GhosttyConfig`. Missing keys fall back to
    /// `.fallback` component-wise.
    init(config: GhosttyConfig) {
        self.background = config.color(forKey: "background")?.swiftUIColor
            ?? Self.fallback.background
        self.foreground = config.color(forKey: "foreground")?.swiftUIColor
            ?? Self.fallback.foreground
    }

    init(background: Color, foreground: Color) {
        self.background = background
        self.foreground = foreground
    }
}

// MARK: - GhosttyApp

/// Swift wrapper around `ghostty_app_t`.
///
/// # Threading
/// libghostty may invoke the wakeup callback from any thread. We hop to the main queue and
/// post `Notification.Name.ghosttyWakeup` so observers can safely call `tick()` on the main
/// thread. The action callback may also fire from any thread; the supplied `actionHandler`
/// must be thread-safe (or dispatch to the main queue before touching UI state).
final class GhosttyApp {
    /// Underlying `ghostty_app_t` handle (opaque pointer).
    let app: ghostty_app_t

    /// Theme snapshot read from the ghostty config at init time. Used by the
    /// app chrome (sidebar, breadcrumb, title area) so the whole window
    /// matches the terminal's visual theme.
    let theme: GhosttyTheme

    /// Retained so the config outlives any internal references. `GhosttyApp` owns the
    /// config from the C side's perspective once `ghostty_app_new` succeeds.
    private let config: GhosttyConfig

    /// Backing storage for the runtime config struct. libghostty copies this at
    /// `ghostty_app_new` time, but we keep it alive defensively for the app's lifetime.
    private var runtimeConfig: ghostty_runtime_config_s

    /// Raw pointer to the retained `ActionHandlerBox`; released in `deinit`.
    private let handlerBoxPointer: UnsafeMutableRawPointer

    /// Creates a new ghostty app.
    /// - Parameters:
    ///   - config: A finalized `GhosttyConfig`. Ownership is transferred to the app on success.
    ///   - actionHandler: Invoked when libghostty emits an action. May fire from any thread.
    ///     The return value is forwarded as the C callback's return value.
    init(config: GhosttyConfig, actionHandler: @escaping (ghostty_target_s, ghostty_action_s) -> Bool) {
        // Read theme BEFORE ghostty_app_new transfers config ownership.
        self.theme = GhosttyTheme(config: config)

        self.config = config

        let handlerBox = ActionHandlerBox(handler: actionHandler)
        let handlerPtr = Unmanaged.passRetained(handlerBox).toOpaque()
        self.handlerBoxPointer = handlerPtr

        // Zero-initialize then fill. All callback slots must be non-null: libghostty will
        // call them unconditionally. We stub clipboard + close_surface with safe no-ops that
        // higher layers can later replace by building a richer runtime.
        var rtConfig = ghostty_runtime_config_s()
        rtConfig.userdata = handlerPtr
        rtConfig.supports_selection_clipboard = false

        rtConfig.wakeup_cb = { _ in
            if Thread.isMainThread {
                NotificationCenter.default.post(name: .ghosttyWakeup, object: nil)
            } else {
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .ghosttyWakeup, object: nil)
                }
            }
        }

        rtConfig.action_cb = { appHandle, target, action -> Bool in
            // Recover the Swift handler. libghostty's action_cb signature has no `userdata`
            // parameter, so we retrieve it from the app via `ghostty_app_userdata`, which
            // returns the `userdata` field we set on the runtime config.
            guard let appHandle, let userdata = ghostty_app_userdata(appHandle) else {
                return false
            }
            let box = Unmanaged<ActionHandlerBox>.fromOpaque(userdata).takeUnretainedValue()
            return box.handler(target, action)
        }

        rtConfig.read_clipboard_cb = { _, _, _ in
            // Return false: we did not read the clipboard.
            return false
        }
        rtConfig.confirm_read_clipboard_cb = { _, _, _, _ in
            // No-op: OSC 52 confirmation unsupported at this layer.
        }
        rtConfig.write_clipboard_cb = { _, _, _, _, _ in
            // No-op: clipboard writes unsupported at this layer.
        }
        rtConfig.close_surface_cb = { _, _ in
            // No-op: surface close handled by a higher layer.
        }

        self.runtimeConfig = rtConfig

        guard let newApp = ghostty_app_new(&self.runtimeConfig, config.config) else {
            Unmanaged<ActionHandlerBox>.fromOpaque(handlerPtr).release()
            fatalError("ghostty_app_new returned null")
        }
        self.app = newApp
        config.ownershipTransferred = true
    }

    deinit {
        ghostty_app_free(app)
        // Release the handler box after the app is freed so libghostty can't invoke callbacks
        // against a released box.
        Unmanaged<ActionHandlerBox>.fromOpaque(handlerBoxPointer).release()
    }

    /// Advance the ghostty event loop. Call on the main thread in response to a
    /// `ghosttyWakeup` notification.
    func tick() {
        ghostty_app_tick(app)
    }
}

// MARK: - Action trampoline

/// Box carrying a Swift closure across the C ABI via `Unmanaged`.
private final class ActionHandlerBox {
    let handler: (ghostty_target_s, ghostty_action_s) -> Bool
    init(handler: @escaping (ghostty_target_s, ghostty_action_s) -> Bool) {
        self.handler = handler
    }
}

// MARK: - Notification

extension Notification.Name {
    /// Posted on the main thread whenever libghostty's wakeup callback fires. Observers
    /// should call `GhosttyApp.tick()` in response.
    static let ghosttyWakeup = Notification.Name("com.espalier.ghostty.wakeup")
}
