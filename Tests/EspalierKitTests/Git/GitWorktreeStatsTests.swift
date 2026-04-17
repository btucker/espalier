import Testing
import Foundation
@testable import EspalierKit

@Suite("GitWorktreeStats — parsers")
struct GitWorktreeStatsParserTests {

    // MARK: parseRevListCounts
    // Format is `<behind>\t<ahead>\n` because we invoke
    // `rev-list --left-right --count <default>...HEAD` — the left side
    // of A...B is "commits in A not B" (behind for us), right side is
    // "commits in B not A" (ahead).

    @Test func parsesRevListBothNonZero() throws {
        let result = GitWorktreeStats.parseRevListCounts("2\t5\n")
        #expect(result?.behind == 2)
        #expect(result?.ahead == 5)
    }

    @Test func parsesRevListAllZeros() throws {
        let result = GitWorktreeStats.parseRevListCounts("0\t0\n")
        #expect(result?.behind == 0)
        #expect(result?.ahead == 0)
    }

    @Test func parsesRevListWithTrailingWhitespace() throws {
        let result = GitWorktreeStats.parseRevListCounts("  3\t7  \n")
        #expect(result?.behind == 3)
        #expect(result?.ahead == 7)
    }

    @Test func rejectsMalformedRevListOutput() throws {
        #expect(GitWorktreeStats.parseRevListCounts("") == nil)
        #expect(GitWorktreeStats.parseRevListCounts("not a number\tnope\n") == nil)
        #expect(GitWorktreeStats.parseRevListCounts("only-one-column\n") == nil)
    }

    // MARK: parseShortStat
    // git diff --shortstat output looks like:
    //   " 3 files changed, 42 insertions(+), 7 deletions(-)"
    // Insertions or deletions may be absent if zero. Empty output
    // (no diff) returns (0, 0) rather than failing.

    @Test func parsesShortStatBoth() throws {
        let output = " 3 files changed, 42 insertions(+), 7 deletions(-)\n"
        let result = GitWorktreeStats.parseShortStat(output)
        #expect(result.insertions == 42)
        #expect(result.deletions == 7)
    }

    @Test func parsesShortStatSingularInsertion() throws {
        let output = " 1 file changed, 1 insertion(+)\n"
        let result = GitWorktreeStats.parseShortStat(output)
        #expect(result.insertions == 1)
        #expect(result.deletions == 0)
    }

    @Test func parsesShortStatOnlyDeletions() throws {
        let output = " 2 files changed, 15 deletions(-)\n"
        let result = GitWorktreeStats.parseShortStat(output)
        #expect(result.insertions == 0)
        #expect(result.deletions == 15)
    }

    @Test func parsesShortStatEmpty() throws {
        let result = GitWorktreeStats.parseShortStat("")
        #expect(result.insertions == 0)
        #expect(result.deletions == 0)
    }

    @Test func parsesShortStatBlankLineOnly() throws {
        let result = GitWorktreeStats.parseShortStat("\n")
        #expect(result.insertions == 0)
        #expect(result.deletions == 0)
    }

    // MARK: WorktreeStats.isEmpty

    @Test func isEmptyWhenAllZero() throws {
        let s = WorktreeStats(ahead: 0, behind: 0, insertions: 0, deletions: 0)
        #expect(s.isEmpty)
    }

    @Test func isNotEmptyWhenAnyNonZero() throws {
        #expect(!WorktreeStats(ahead: 1, behind: 0, insertions: 0, deletions: 0).isEmpty)
        #expect(!WorktreeStats(ahead: 0, behind: 1, insertions: 0, deletions: 0).isEmpty)
        #expect(!WorktreeStats(ahead: 0, behind: 0, insertions: 1, deletions: 0).isEmpty)
        #expect(!WorktreeStats(ahead: 0, behind: 0, insertions: 0, deletions: 1).isEmpty)
    }
}
