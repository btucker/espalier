import Foundation
import AppKit
import GrafttyKit

/// Drives a single long-lived Task that fires `onTick` on a cadence.
/// Reacts to app active/inactive notifications (optionally pausing
/// when inactive), and exposes `pulse()` to wake early for
/// user-triggered refreshes.
///
/// The sleep loop uses only bare `Task.sleep` on `@MainActor` and a
/// monotonic `pulseCount` counter as the wakeup signal. Earlier
/// designs (inner sleep `Task` + `await s.value`, or `withTaskGroup`
/// racing sleep against an `AsyncStream`) all hung after one tick
/// on Swift 6.2.x — symptomatic of swiftlang/swift#57150 (SR-14802),
/// where a continuation resume across the same actor's boundary can
/// be dropped. Any approach with a continuation hop back to MainActor
/// (group child completion signal, AsyncStream iterator, awaited
/// Task.value) is vulnerable. Polling a counter avoids continuation
/// handoffs entirely; the trade-off is up to ~one chunk of pulse
/// latency, which is invisible for a UI refresh trigger.
/// @spec PR-8.10
@MainActor
final class PollingTicker: PollingTickerLike {
    private let interval: Duration
    private let pauseWhenInactive: @MainActor () -> Bool
    private var task: Task<Void, Never>?
    private var pulseCount: UInt64 = 0
    private var paused = false
    private var activeObserver: NSObjectProtocol?
    private var inactiveObserver: NSObjectProtocol?

    /// Granularity of the interruptible sleep. Trades pulse() latency
    /// against wakeups-per-interval. 20ms is well below human
    /// perception while keeping the wake count low for a multi-second
    /// poll cadence.
    private static let chunkDuration: Duration = .milliseconds(20)

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
        removeObservers()
    }

    func pulse() {
        pulseCount &+= 1
    }

    // MARK: - Private

    private func sleepUntilPulseOrInterval() async {
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
