import Testing
import Foundation
@testable import EspalierKit

@Suite("SessionRestartBanner")
struct SessionRestartBannerTests {

    @Test func bannerWrapsTimestampInDimAnsi() {
        let date = Self.dateAt(hour: 14, minute: 23)
        let banner = sessionRestartBanner(at: date)
        #expect(banner.contains("14:23"))
        // Embedded *literal* `\033[2m` / `\033[0m` — the outer shell's
        // printf turns them into ESC at runtime, so we assert the
        // backslash-octal form, not the real ESC byte.
        #expect(banner.contains("\\033[2m"))
        #expect(banner.contains("\\033[0m"))
    }

    @Test func bannerEndsWithExecutableNewline() {
        let banner = sessionRestartBanner(at: Self.dateAt(hour: 9, minute: 5))
        #expect(banner.last == "\n")
    }

    @Test func bannerInvokesPrintfNotEcho() {
        let banner = sessionRestartBanner(at: Self.dateAt(hour: 0, minute: 0))
        #expect(banner.hasPrefix("printf "))
    }

    @Test func bannerZeroPadsSingleDigitHourAndMinute() {
        let banner = sessionRestartBanner(at: Self.dateAt(hour: 9, minute: 5))
        #expect(banner.contains("09:05"))
    }

    private static func dateAt(hour: Int, minute: Int) -> Date {
        var comps = DateComponents()
        comps.year = 2026
        comps.month = 4
        comps.day = 19
        comps.hour = hour
        comps.minute = minute
        return Calendar.current.date(from: comps)!
    }
}
