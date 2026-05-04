import Foundation
import Testing
@testable import Graftty

/// Regression tests for the polling-loop hang. The previous
/// `sleepOrPulse` raced an `AsyncStream` consumer Task against a
/// `Task.sleep` Task inside a nested `withTaskGroup`. When one of
/// the two child Tasks completed and `cancelAll()` was called, the
/// OTHER child was still awaiting the OUTER Task's `.value` — and
/// `Task<Void, Never>.value` does not propagate cancellation back
/// to the awaited Task. So the outer pulseTask kept iterating the
/// stream forever, the awaiting child could never finish, the
/// `withTaskGroup` could not return, and `sleepOrPulse` blocked
/// permanently. The user-visible shape: the polling loop fired
/// exactly one initial tick at startup, then never again — only
/// the on-demand `refresh()` path (sidebar selection) produced
/// fresh data. Earlier `PR-7.13` / `PR-7.14` fixes addressed
/// scenarios where the ticker is alive but failing; none of them
/// touched the case where the ticker itself stops running, and
/// the previous regression test for `PR-7.14` used a fake
/// `CapturingTicker`, which is why this hang stayed undetected.
@MainActor
@Suite("""
PollingTicker liveness

@spec PR-8.10: The polling ticker shall keep firing `onTick` on its configured interval indefinitely, without stalling after one or more sleep / pulse cycles. `pulse()` shall cancel the in-progress sleep so the next tick fires immediately rather than waiting for the full interval. The ticker's sleep mechanism must not depend on `AsyncStream` iteration awaited via `Task.value`, because `Task<Void, Never>.value` does not propagate cancellation to the awaited Task and that pattern can deadlock the polling loop after a single sleep-wins iteration — observable to the user as "PR / stats status only updates when I click on a worktree tab".
""")
struct PollingTickerTests {

    /// Multiple ticks must fire over time without external pulses —
    /// the loop has to keep itself alive between sleep cycles.
    @Test
    func tickFiresMultipleTimesWithoutPulse() async throws {
        let counter = TickCounter()
        let ticker = PollingTicker(
            interval: .milliseconds(40),
            pauseWhenInactive: { false }
        )
        ticker.start { await counter.increment() }
        defer { ticker.stop() }

        // Poll until we see 4 ticks or hit the timeout. At 40ms cadence
        // on an idle machine this takes ~160ms; under heavy CI
        // parallelism (170+ test suites contending for MainActor for
        // each onTick hop), each tick can take many times that — so
        // give the test a generous budget. The bug we're guarding
        // against is the loop ticking once and never again, which the
        // timeout-bound liveness check catches reliably.
        let deadline = Date().addingTimeInterval(5.0)
        while await counter.value < 4 && Date() < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }

        let count = await counter.value
        #expect(count >= 4, "expected ≥4 ticks within 5s; got \(count) (loop must keep firing between sleep cycles)")
    }

    /// `pulse()` cancels the active sleep and the loop fires the
    /// next tick immediately. Without this, the only way to wake
    /// the ticker early would be to wait for the full interval.
    @Test
    func pulseFiresNextTickEarly() async throws {
        let counter = TickCounter()
        let ticker = PollingTicker(
            // Long enough that an unpulsed second tick can't land
            // within the test window — only `pulse()` can produce one.
            interval: .seconds(5),
            pauseWhenInactive: { false }
        )
        ticker.start { await counter.increment() }
        defer { ticker.stop() }

        // Wait for the initial tick to fire and the loop to enter
        // its sleep phase.
        for _ in 0..<50 {
            if await counter.value >= 1 { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(await counter.value == 1, "initial tick should have fired")

        ticker.pulse()

        // The pulse cancels the in-progress sleep; the next tick
        // should land within a few ms, well under the 5-second
        // interval.
        for _ in 0..<100 {
            if await counter.value >= 2 { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(await counter.value >= 2, "pulse should produce a second tick")
    }

    /// Many pulse-and-sleep cycles in succession must not stall the
    /// loop. The previous implementation leaked one pulse-iterator
    /// Task per iteration; the deadlock surfaced after the first
    /// sleep-wins iteration. This test exercises the cycle
    /// sufficiently that any "one-iteration-then-stuck" regression
    /// would fail it.
    @Test
    func surviveManyPulseSleepCycles() async throws {
        let counter = TickCounter()
        let ticker = PollingTicker(
            interval: .milliseconds(50),
            pauseWhenInactive: { false }
        )
        ticker.start { await counter.increment() }
        defer { ticker.stop() }

        for _ in 0..<10 {
            try await Task.sleep(for: .milliseconds(15))
            ticker.pulse()
        }

        // Wait a beat for the trailing ticks to land.
        try await Task.sleep(for: .milliseconds(80))

        let count = await counter.value
        #expect(count >= 5, "expected the loop to survive multiple pulse cycles; got \(count) ticks")
    }
}

actor TickCounter {
    private(set) var value: Int = 0
    func increment() { value += 1 }
}
