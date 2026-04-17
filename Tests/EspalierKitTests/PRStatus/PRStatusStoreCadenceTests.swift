import Testing
import Foundation
@testable import EspalierKit

@Suite("PRStatusStore cadence")
struct PRStatusStoreCadenceTests {
    let url = URL(string: "https://github.com/x/y/pull/1")!

    @Test func pendingOpenIs25s() {
        let info = PRInfo(number: 1, title: "x", url: url, state: .open, checks: .pending, fetchedAt: Date())
        let d = PRStatusStore.cadenceFor(info: info, isAbsent: false, failureStreak: 0)
        #expect(d == .seconds(25))
    }

    @Test func stableOpenIs5min() {
        let info = PRInfo(number: 1, title: "x", url: url, state: .open, checks: .success, fetchedAt: Date())
        let d = PRStatusStore.cadenceFor(info: info, isAbsent: false, failureStreak: 0)
        #expect(d == .seconds(300))
    }

    @Test func mergedIs15min() {
        let info = PRInfo(number: 1, title: "x", url: url, state: .merged, checks: .none, fetchedAt: Date())
        let d = PRStatusStore.cadenceFor(info: info, isAbsent: false, failureStreak: 0)
        #expect(d == .seconds(900))
    }

    @Test func absentIs15min() {
        let d = PRStatusStore.cadenceFor(info: nil, isAbsent: true, failureStreak: 0)
        #expect(d == .seconds(900))
    }

    @Test func unknownIsImmediate() {
        let d = PRStatusStore.cadenceFor(info: nil, isAbsent: false, failureStreak: 0)
        #expect(d == .zero)
    }

    @Test func backoffDoublesCadence() {
        let info = PRInfo(number: 1, title: "x", url: url, state: .open, checks: .success, fetchedAt: Date())
        let d1 = PRStatusStore.cadenceFor(info: info, isAbsent: false, failureStreak: 1)
        #expect(d1 == .seconds(600))
        let d2 = PRStatusStore.cadenceFor(info: info, isAbsent: false, failureStreak: 2)
        #expect(d2 == .seconds(1200))
        // failureStreak: 3 -> 300 * 8 = 2400s, but the 30min (1800s) cap clamps it.
        let d3 = PRStatusStore.cadenceFor(info: info, isAbsent: false, failureStreak: 3)
        #expect(d3 == .seconds(30 * 60))
    }

    @Test func backoffCapsAt30min() {
        let info = PRInfo(number: 1, title: "x", url: url, state: .open, checks: .success, fetchedAt: Date())
        let d = PRStatusStore.cadenceFor(info: info, isAbsent: false, failureStreak: 20)
        #expect(d == .seconds(30 * 60))
    }
}
