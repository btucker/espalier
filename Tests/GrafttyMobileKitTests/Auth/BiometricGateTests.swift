#if canImport(UIKit)
import Foundation
import Testing
@testable import GrafttyMobileKit

@Suite
@MainActor
struct BiometricGateTests {

    final class FakeClock: Clock, @unchecked Sendable {
        var now: Date
        init(_ start: Date) { self.now = start }
        func sleep(for duration: TimeInterval) async throws {
            try await Task.sleep(nanoseconds: UInt64(max(0, duration) * 1_000_000_000))
        }
    }

    final class FakeAuthenticator: BiometricAuthenticator, @unchecked Sendable {
        var outcome: Result<Void, Error> = .success(())
        var callCount = 0
        func authenticate() async -> Result<Void, Error> {
            callCount += 1
            return outcome
        }
    }

    actor SuspendedAuthenticator: BiometricAuthenticator {
        private(set) var callCount = 0
        private var replies: [CheckedContinuation<Result<Void, Error>, Never>] = []

        func authenticate() async -> Result<Void, Error> {
            callCount += 1
            return await withCheckedContinuation { replies.append($0) }
        }

        func succeed() {
            for reply in replies { reply.resume(returning: .success(())) }
            replies.removeAll()
        }
    }

    private func activate(_ gate: BiometricGate) async {
        gate.applicationWillEnterForeground()
        await gate.authenticateOnActivation()
    }

    @Test("@spec IOS-3.5: When launch, scene activation, or the Unlock button requests authentication while a prompt is pending, the application shall keep a single authentication request in flight.")
    func overlappingRequestsShareOnePrompt() async {
        let auth = SuspendedAuthenticator()
        let gate = BiometricGate(authenticator: auth)
        gate.applicationWillEnterForeground()
        let first = Task { await gate.authenticate() }
        while await auth.callCount == 0 { await Task.yield() }
        var secondStarted = false
        let second = Task {
            secondStarted = true
            await gate.authenticate()
        }
        while !secondStarted { await Task.yield() }
        #expect(await auth.callCount == 1)
        await auth.succeed()
        await first.value
        await second.value
        #expect(gate.state == .unlocked)
    }

    @Test("@spec IOS-3.6: When the scene first becomes active while locked, the application shall promptly request authentication once per foreground visit. Transient inactive-to-active transitions after denial or cancellation shall leave the retry button available without reopening the prompt.")
    func automaticPromptWaitsForActivationAndDoesNotLoop() async {
        let auth = FakeAuthenticator()
        struct Cancelled: Error {}
        auth.outcome = .failure(Cancelled())
        let gate = BiometricGate(authenticator: auth)
        #expect(auth.callCount == 0)
        await activate(gate)
        #expect(auth.callCount == 1)
        #expect(gate.state == .locked)
        await activate(gate)
        #expect(auth.callCount == 1)
        await gate.authenticate()
        #expect(auth.callCount == 2)
        gate.applicationDidEnterBackground()
        await activate(gate)
        #expect(auth.callCount == 3)
    }

    @Test
    func coldLaunchStartsLocked() {
        let gate = BiometricGate(clock: FakeClock(Date()), authenticator: FakeAuthenticator())
        #expect(gate.state == .locked)
    }

    @Test
    func queuedActivationDoesNotPromptAfterSceneLeavesActive() async {
        let auth = FakeAuthenticator()
        let gate = BiometricGate(authenticator: auth)
        gate.applicationWillEnterForeground()
        gate.applicationDidBecomeInactive()
        await gate.authenticateOnActivation()
        #expect(auth.callCount == 0)
        gate.applicationDidEnterBackground()
        await gate.authenticateOnActivation()
        await gate.authenticate()
        #expect(auth.callCount == 0)
        #expect(gate.state == .locked)
    }

    @Test("@spec IOS-3.8: When authentication completes after the application has entered the background, the application shall discard that result and request fresh authentication on the next active foreground visit.")
    func backgroundInvalidatesPendingSuccess() async {
        let auth = SuspendedAuthenticator()
        let gate = BiometricGate(authenticator: auth)
        let attempt = Task { await activate(gate) }
        while await auth.callCount == 0 { await Task.yield() }
        gate.applicationDidEnterBackground()
        await auth.succeed()
        await attempt.value
        #expect(gate.state == .locked)
        #expect(!gate.isAuthenticating)
    }

    @Test
    func reactivationWaitsForStalePromptThenRetries() async {
        let auth = SuspendedAuthenticator()
        let gate = BiometricGate(authenticator: auth)
        let attempt = Task { await activate(gate) }
        while await auth.callCount == 0 { await Task.yield() }
        gate.applicationDidEnterBackground()
        await activate(gate)
        #expect(await auth.callCount == 1)
        await auth.succeed()
        for _ in 0..<1_000 {
            if await auth.callCount == 2 { break }
            await Task.yield()
        }
        #expect(await auth.callCount == 2)
        #expect(gate.state == .locked)
        await auth.succeed()
        await attempt.value
        #expect(gate.state == .unlocked)
    }

    @Test
    func staleCompletionWhileInactiveWaitsForActivation() async {
        let auth = SuspendedAuthenticator()
        let gate = BiometricGate(authenticator: auth)
        let attempt = Task { await activate(gate) }
        while await auth.callCount == 0 { await Task.yield() }
        gate.applicationDidEnterBackground()
        await activate(gate)
        gate.applicationDidBecomeInactive()
        await auth.succeed()
        await attempt.value
        #expect(await auth.callCount == 1)
        #expect(gate.state == .locked)

        let fresh = Task { await activate(gate) }
        while await auth.callCount < 2 { await Task.yield() }
        await auth.succeed()
        await fresh.value
        #expect(gate.state == .unlocked)
    }

    @Test
    func successfulAuthUnlocks() async {
        let auth = FakeAuthenticator()
        let gate = BiometricGate(clock: FakeClock(Date()), authenticator: auth)
        gate.applicationWillEnterForeground()
        await gate.authenticate()
        #expect(gate.state == .unlocked)
        #expect(auth.callCount == 1)
    }

    @Test
    func backgroundForLessThanFiveMinutesStaysUnlocked() async {
        let clock = FakeClock(Date(timeIntervalSince1970: 1_000))
        let gate = BiometricGate(clock: clock, authenticator: FakeAuthenticator())
        gate.applicationWillEnterForeground()
        await gate.authenticate()
        gate.applicationDidEnterBackground()
        clock.now = clock.now.addingTimeInterval(4 * 60)
        gate.applicationWillEnterForeground()
        #expect(gate.state == .unlocked)
    }

    @Test
    func backgroundForFiveOrMoreMinutesLocks() async {
        let clock = FakeClock(Date(timeIntervalSince1970: 1_000))
        let gate = BiometricGate(clock: clock, authenticator: FakeAuthenticator())
        gate.applicationWillEnterForeground()
        await gate.authenticate()
        gate.applicationDidEnterBackground()
        clock.now = clock.now.addingTimeInterval(5 * 60)
        gate.applicationWillEnterForeground()
        #expect(gate.state == .locked)
    }

    @Test
    func failedAuthStaysLocked() async {
        let auth = FakeAuthenticator()
        struct Denied: Error {}
        auth.outcome = .failure(Denied())
        let gate = BiometricGate(clock: FakeClock(Date()), authenticator: auth)
        gate.applicationWillEnterForeground()
        await gate.authenticate()
        #expect(gate.state == .locked)
    }
}
#endif
