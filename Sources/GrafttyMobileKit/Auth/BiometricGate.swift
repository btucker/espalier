#if canImport(UIKit)
import Foundation
import LocalAuthentication
import Observation

public protocol BiometricAuthenticator: Sendable {
    func authenticate() async -> Result<Void, Error>
}

public struct LocalAuthenticationAuthenticator: BiometricAuthenticator {
    public init() {}

    public func authenticate() async -> Result<Void, Error> {
        let context = LAContext()
        context.localizedFallbackTitle = "Use passcode"
        return await withCheckedContinuation { continuation in
            context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: "Unlock Graftty"
            ) { ok, error in
                if ok { continuation.resume(returning: .success(())) }
                else { continuation.resume(returning: .failure(error ?? NSError(domain: "LA", code: -1))) }
            }
        }
    }
}

@Observable
@MainActor
public final class BiometricGate {

    public enum State: Equatable { case locked, unlocked }

    public private(set) var state: State = .locked
    public private(set) var isAuthenticating = false

    private let clock: any Clock
    private let authenticator: any BiometricAuthenticator
    private let idleTimeout: TimeInterval
    private var backgroundedAt: Date?
    private var attemptedThisForeground = false
    private var foregroundGeneration = 0
    private var applicationIsActive = false

    public init(
        clock: any Clock = SystemClock(),
        authenticator: any BiometricAuthenticator = LocalAuthenticationAuthenticator(),
        idleTimeout: TimeInterval = 5 * 60
    ) {
        self.clock = clock
        self.authenticator = authenticator
        self.idleTimeout = idleTimeout
    }

    public func authenticate() async {
        guard applicationIsActive, state == .locked, !isAuthenticating else { return }
        isAuthenticating = true
        defer { isAuthenticating = false }
        repeat {
            let generation = foregroundGeneration
            attemptedThisForeground = true
            let result = await authenticator.authenticate()
            // A prompt can finish after backgrounding. Only the foreground
            // visit that started it may consume its result.
            if generation == foregroundGeneration {
                switch result {
                case .success:
                    state = .unlocked
                    backgroundedAt = nil
                case .failure:
                    state = .locked
                }
                return
            }
            // If the user already returned, finish the obsolete request
            // before presenting this visit's prompt.
        } while applicationIsActive && !attemptedThisForeground && state == .locked
    }

    public func applicationDidBecomeInactive() {
        applicationIsActive = false
    }

    public func applicationDidEnterBackground() {
        applicationIsActive = false
        foregroundGeneration += 1
        attemptedThisForeground = false
        guard state == .unlocked else { return }
        backgroundedAt = clock.now
    }

    /// Called by queued UI work after the synchronous foreground transition.
    /// authenticate() rechecks the current activity before starting a prompt.
    public func authenticateOnActivation() async {
        guard !attemptedThisForeground else { return }
        await authenticate()
    }

    public func applicationWillEnterForeground() {
        applicationIsActive = true
        guard let since = backgroundedAt else { return }
        if clock.now.timeIntervalSince(since) >= idleTimeout {
            state = .locked
        }
        backgroundedAt = nil
    }
}
#endif
