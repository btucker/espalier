import Foundation
import AppKit
import GrafttyKit

/// Drives a single long-lived Task that fires `onTick` on a cadence.
/// Reacts to app active/inactive notifications (optionally pausing
/// when inactive), and exposes `pulse()` to wake early for
/// user-triggered refreshes.
///
/// `pulse()` cancels the in-progress sleep directly (the sleep Task
/// is owned by the ticker). The earlier implementation raced an
/// `AsyncStream` consumer Task against a `Task.sleep` Task inside a
/// nested `withTaskGroup`; on each iteration the losing child
/// awaited `Task<Void, Never>.value` of the outer pulseTask, which
/// does not propagate cancellation, so the group could never
/// return and the polling loop deadlocked after a single
/// sleep-wins iteration. Single owned sleep Task + direct
/// cancellation removes that class of bug structurally.
/// @spec PR-8.10
@MainActor
final class PollingTicker: PollingTickerLike {
    private let interval: Duration
    private let pauseWhenInactive: @MainActor () -> Bool
    private var task: Task<Void, Never>?
    private var sleepTask: Task<Void, Never>?
    private var sleepGeneration = 0
    private var paused = false
    private var activeObserver: NSObjectProtocol?
    private var inactiveObserver: NSObjectProtocol?

    init(
        interval: Duration,
        pauseWhenInactive: @MainActor @escaping () -> Bool = { true }
    ) {
        self.interval = interval
        self.pauseWhenInactive = pauseWhenInactive
    }

    func start(onTick: @MainActor @escaping () async -> Void) {
        guard task == nil else { return }
        installObservers()
        task = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                if !self.paused {
                    await onTick()
                }
                await self.sleepUntilPulseOrInterval()
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        sleepTask?.cancel()
        sleepTask = nil
        removeObservers()
    }

    func pulse() {
        // Cancellation makes `Task.sleep` throw, the `try?` swallows
        // it, and `sleepUntilPulseOrInterval` returns — so the next
        // iteration of the polling loop fires `onTick` immediately.
        sleepTask?.cancel()
    }

    // MARK: - Private

    private func sleepUntilPulseOrInterval() async {
        sleepGeneration += 1
        let myGeneration = sleepGeneration
        // Detached so the sleep task is NOT inherited onto MainActor.
        // On Swift 6.2 a non-detached `Task { }` here inherits the
        // enclosing `@MainActor`, putting both the outer loop's
        // `await s.value` and the inner `Task.sleep` on the same
        // actor — and the outer await fails to resume after the sleep
        // completes, stalling the loop after one tick.
        let s = Task.detached { [interval] in
            _ = try? await Task.sleep(for: interval)
        }
        sleepTask = s
        _ = await s.value
        // Don't clobber a fresh `sleepTask` that `stop()` cleared or a
        // re-entered loop installed during the await.
        if sleepGeneration == myGeneration { sleepTask = nil }
    }

    private func installObservers() {
        let center = NotificationCenter.default
        activeObserver = center.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.paused = false }
        }
        inactiveObserver = center.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.pauseWhenInactive() {
                    self.paused = true
                }
            }
        }
    }

    private func removeObservers() {
        let center = NotificationCenter.default
        if let o = activeObserver { center.removeObserver(o); activeObserver = nil }
        if let o = inactiveObserver { center.removeObserver(o); inactiveObserver = nil }
    }
}
