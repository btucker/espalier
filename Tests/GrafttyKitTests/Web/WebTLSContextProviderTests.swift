import Testing
import Foundation
import NIOSSL
@testable import GrafttyKit

@Suite("WebTLSContextProvider")
struct WebTLSContextProviderTests {

    @Test func currentReturnsInitialContext() throws {
        let ctx = try makeTestTLSContext()
        let provider = WebTLSContextProvider(initial: ctx)
        #expect(provider.current() === ctx)
    }

    @Test func swapReplacesContext() throws {
        let a = try makeTestTLSContext()
        let b = try makeTestTLSContext()
        let provider = WebTLSContextProvider(initial: a)
        provider.swap(b)
        #expect(provider.current() === b)
    }

    @Test func concurrentReadsDoNotCrash() async throws {
        let ctx = try makeTestTLSContext()
        let provider = WebTLSContextProvider(initial: ctx)
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<100 {
                group.addTask { _ = provider.current() }
            }
        }
    }
}
