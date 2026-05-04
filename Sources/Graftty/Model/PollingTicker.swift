import Foundation
import AppKit
import GrafttyKit

/// Drives a single long-lived Task that fires `onTick` on a cadence.
/// Reacts to app active/inactive notifications (optionally pausing
/// when inactive), and exposes `pulse()` to wake early for
/// user-triggered refreshes.
///
/// Each sleep races a `Task.sleep` child against a per-iteration
/// `AsyncStream` consumer child inside `withTaskGroup`. The work
/// runs INSIDE the children — no nested unstructured Tasks, no
/// `await someTask.value`. That's load-bearing: awaiting an
/// unstructured `Task<Void, Never>.value` from `@MainActor` can
/// hang on the resume hop (swiftlang/swift#57150 / SR-14802),
/// observable as the polling loop ticking once and then stalling.
/// Structured children let `group.cancelAll()` actually cancel the
/// in-flight `Task.sleep` and `for await` directly, so whichever
/// child wins, the loser unwinds cleanly.
/// @spec PR-8.10
@MainActor
final class PollingTicker: PollingTickerLike {
    private let interval: Duration
    private let pauseWhenInactive: @MainActor () -> Bool
    private var task: Task<Void, Never>?
    private var pulseContinuation: AsyncStream<Void>.Continuation?
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
        pulseContinuation?.finish()
        pulseContinuation = nil
        removeObservers()
    }

    func pulse() {
        pulseContinuation?.yield(())
    }

    // MARK: - Private

    private func sleepUntilPulseOrInterval() async {
        let (stream, cont) = AsyncStream<Void>.makeStream()
        pulseContinuation = cont
        defer { pulseContinuation = nil }

        await withTaskGroup(of: Void.self) { [interval] group in
            group.addTask {
                _ = try? await Task.sleep(for: interval)
            }
            group.addTask {
                for await _ in stream { return }
            }
            _ = await group.next()
            group.cancelAll()
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
