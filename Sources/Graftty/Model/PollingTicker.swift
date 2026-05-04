import Foundation
import AppKit
import GrafttyKit

/// Drives a single long-lived Task that fires `onTick` on a cadence.
/// Reacts to app active/inactive notifications (optionally pausing
/// when inactive), and exposes `pulse()` to wake early for
/// user-triggered refreshes.
///
/// The sleep + pulse-counter live inside `PollingHeart`, a private
/// actor with its own serial executor. This is load-bearing: keeping
/// the ticker `@MainActor` would put the sleep on a heavily-contended
/// actor (Swift 6.2's "approachable concurrency" defaults a lot of
/// app + test code to MainActor), and `Task.sleep` would block waiting
/// for MainActor cycles — observable on CI as 20ms sleeps taking
/// 700ms+, the loop missing its 40ms deadline, and PR-8.10's
/// regression tests reading `count == 1` after 220ms. Routing through
/// `PollingHeart` lets the sleep loop run on its own executor, so the
/// timer's cadence is independent of MainActor pressure. Only the
/// brief `onTick()` invocation hops to MainActor.
/// @spec PR-8.10
@MainActor
final class PollingTicker: PollingTickerLike {
    private let interval: Duration
    private let pauseWhenInactive: @MainActor () -> Bool
    private let heart = PollingHeart()
    private var task: Task<Void, Never>?
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
        let interval = self.interval
        let heart = self.heart
        task = Task.detached { [weak self] in
            while !Task.isCancelled {
                let isPaused = await self?.isPaused ?? true
                if !isPaused {
                    await onTick()
                }
                await heart.sleepUntilPulseOrInterval(for: interval)
            }
        }
    }

    private var isPaused: Bool { paused }

    func stop() {
        task?.cancel()
        task = nil
        removeObservers()
    }

    func pulse() {
        let heart = self.heart
        Task.detached { await heart.pulse() }
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

/// Owns the polling cadence on its own actor executor — independent
/// of MainActor contention. Sleep chunks are interruptible: `pulse()`
/// bumps a monotonic counter, the sleep loop re-checks between
/// chunks. Up to ~20ms pulse latency, invisible for UI refresh.
private actor PollingHeart {
    private var pulseCount: UInt64 = 0

    /// Granularity of the interruptible sleep. Trades pulse() latency
    /// against wakeups-per-interval. 20ms is well below human
    /// perception while keeping the wake count low for a multi-second
    /// poll cadence.
    private static let chunkDuration: Duration = .milliseconds(20)

    func pulse() {
        pulseCount &+= 1
    }

    func sleepUntilPulseOrInterval(for interval: Duration) async {
        let pulseAtEntry = pulseCount
        let deadline = ContinuousClock().now + interval
        while !Task.isCancelled
              && pulseCount == pulseAtEntry
              && ContinuousClock().now < deadline {
            let remaining = deadline - ContinuousClock().now
            let chunk = min(remaining, Self.chunkDuration)
            try? await Task.sleep(for: chunk)
        }
    }
}
