import Foundation

/// Dedup + change-detection helper behind `PWD-1.3`: a timer-driven
/// fallback that polls each tracked pane's cwd (via its inner-shell
/// PID) and fires the same onChange callback OSC 7 would, but only
/// when the observed cwd differs from the last known value for that
/// pane.
///
/// # Why a separate type
/// The orchestration — "iterate tracked IDs, ask resolver, compare
/// to memory, call onChange" — is the bulk of what needs testing,
/// and it has no dependency on timers, libghostty, or proc APIs.
/// `TerminalManager` composes this poller with a real `Timer`, a
/// real PID-from-log resolver, and the usual `onPWDChange` callback.
///
/// # Seeding vs. polling
/// `seed(_:pwd:)` updates the poller's memory without firing
/// `onChange`. The OSC 7 path seeds the poller for the pane's
/// initial worktree path so the first `pollOnce()` doesn't re-fire
/// the same value as if it were new. If OSC 7 races the poll and
/// both observe a cwd transition, the routing code on the receiving
/// end is already idempotent (same-destination no-op), so at worst
/// we get one redundant `reassignPaneByPWD` call.
@MainActor
public final class SurfacePWDPoller {

    public typealias CwdResolver = (TerminalID) -> String?
    public typealias ChangeHandler = (TerminalID, String) -> Void

    private let resolve: CwdResolver
    private let onChange: ChangeHandler
    private var tracked: Set<TerminalID> = []
    private var lastKnown: [TerminalID: String] = [:]

    public init(resolve: @escaping CwdResolver, onChange: @escaping ChangeHandler) {
        self.resolve = resolve
        self.onChange = onChange
    }

    /// Start watching `id` for cwd changes. No-op if already tracked.
    /// Does not pre-populate the last-known PWD — first resolver hit
    /// fires an `onChange`. Seed if you want to suppress that.
    public func track(_ id: TerminalID) {
        tracked.insert(id)
    }

    /// Stop watching `id` and forget its last-known cwd. Safe on IDs
    /// that were never tracked.
    public func untrack(_ id: TerminalID) {
        tracked.remove(id)
        lastKnown.removeValue(forKey: id)
    }

    /// Update the last-known cwd for `id` without invoking `onChange`.
    /// Typical callers: the OSC 7 handler, or the initial-worktree-path
    /// seed right after surface creation.
    public func seed(_ id: TerminalID, pwd: String) {
        lastKnown[id] = pwd
    }

    /// Run one poll across every tracked ID. For each, ask the
    /// resolver for a current cwd; if different from the last-known,
    /// update memory and invoke `onChange`. Resolver returning nil
    /// is treated as "no signal" — last-known is untouched.
    public func pollOnce() {
        for id in tracked {
            guard let pwd = resolve(id) else { continue }
            if lastKnown[id] != pwd {
                lastKnown[id] = pwd
                onChange(id, pwd)
            }
        }
    }
}
