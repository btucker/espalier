import Testing
import Foundation
@testable import EspalierKit

@Suite("GitHubPRFetcher")
struct GitHubPRFetcherTests {
    let origin = HostingOrigin(provider: .github, host: "github.com", owner: "btucker", repo: "espalier")
    let branch = "feature/git-improvements"

    func loadFixture(_ name: String) -> String {
        let url = Bundle.module.url(forResource: name, withExtension: "json")!
        return try! String(contentsOf: url, encoding: .utf8)
    }

    @Test func returnsOpenPRWithPassingChecks() async throws {
        let fake = FakeCLIExecutor()
        fake.stub(
            command: "gh",
            args: [
                "pr", "list",
                "--repo", "btucker/espalier",
                "--head", "btucker:\(branch)",
                "--state", "open",
                "--limit", "1",
                "--json", "number,title,url,state,headRefName"
            ],
            output: CLIOutput(stdout: loadFixture("gh-pr-open-passing"), stderr: "", exitCode: 0)
        )
        fake.stub(
            command: "gh",
            args: ["pr", "checks", "412", "--repo", "btucker/espalier", "--json", "name,state,bucket"],
            output: CLIOutput(stdout: loadFixture("gh-pr-checks-passing"), stderr: "", exitCode: 0)
        )

        let fetcher = GitHubPRFetcher(executor: fake, now: { Date(timeIntervalSince1970: 100) })
        let pr = try await fetcher.fetch(origin: origin, branch: branch)

        #expect(pr?.number == 412)
        #expect(pr?.state == .open)
        #expect(pr?.checks == .success)
        #expect(pr?.title == "Add PR/MR status button to breadcrumb")
        #expect(pr?.url.absoluteString == "https://github.com/btucker/espalier/pull/412")
    }

    @Test func returnsMergedPRWhenNoOpen() async throws {
        let fake = FakeCLIExecutor()
        fake.stub(
            command: "gh",
            args: [
                "pr", "list", "--repo", "btucker/espalier",
                "--head", "btucker:\(branch)", "--state", "open", "--limit", "1",
                "--json", "number,title,url,state,headRefName"
            ],
            output: CLIOutput(stdout: loadFixture("gh-pr-empty"), stderr: "", exitCode: 0)
        )
        fake.stub(
            command: "gh",
            args: [
                "pr", "list", "--repo", "btucker/espalier",
                "--head", "btucker:\(branch)", "--state", "merged", "--limit", "1",
                "--json", "number,title,url,state,headRefName,mergedAt"
            ],
            output: CLIOutput(stdout: loadFixture("gh-pr-merged"), stderr: "", exitCode: 0)
        )

        let fetcher = GitHubPRFetcher(executor: fake, now: { Date() })
        let pr = try await fetcher.fetch(origin: origin, branch: branch)

        #expect(pr?.number == 398)
        #expect(pr?.state == .merged)
        #expect(pr?.checks == PRInfo.Checks.none)
    }

    @Test func scopesHeadFilterToOriginOwnerSoForkPRsAreExcluded() async throws {
        // Regression: `gh pr list --head <branch>` matches PRs from forks
        // that happen to share the branch name, so worktrees were sometimes
        // associated with a stranger's PR. The fetcher must qualify the
        // filter as `<owner>:<branch>` to scope to the same repo.
        let fake = FakeCLIExecutor()
        fake.stub(
            command: "gh",
            args: [
                "pr", "list",
                "--repo", "btucker/espalier",
                "--head", "btucker:\(branch)",
                "--state", "open",
                "--limit", "1",
                "--json", "number,title,url,state,headRefName"
            ],
            output: CLIOutput(stdout: loadFixture("gh-pr-open-passing"), stderr: "", exitCode: 0)
        )
        fake.stub(
            command: "gh",
            args: ["pr", "checks", "412", "--repo", "btucker/espalier", "--json", "name,state,conclusion"],
            output: CLIOutput(stdout: loadFixture("gh-pr-checks-passing"), stderr: "", exitCode: 0)
        )

        let fetcher = GitHubPRFetcher(executor: fake, now: { Date() })
        _ = try await fetcher.fetch(origin: origin, branch: branch)

        let listArgs = fake.invocations.first(where: { $0.args.contains("list") })?.args ?? []
        let headIdx = listArgs.firstIndex(of: "--head")
        #expect(headIdx != nil)
        #expect(headIdx.map { listArgs[listArgs.index(after: $0)] } == "btucker:\(branch)")
    }

    @Test func returnsNilWhenNoOpenOrMerged() async throws {
        let fake = FakeCLIExecutor()
        fake.stub(
            command: "gh",
            args: [
                "pr", "list", "--repo", "btucker/espalier",
                "--head", "btucker:\(branch)", "--state", "open", "--limit", "1",
                "--json", "number,title,url,state,headRefName"
            ],
            output: CLIOutput(stdout: loadFixture("gh-pr-empty"), stderr: "", exitCode: 0)
        )
        fake.stub(
            command: "gh",
            args: [
                "pr", "list", "--repo", "btucker/espalier",
                "--head", "btucker:\(branch)", "--state", "merged", "--limit", "1",
                "--json", "number,title,url,state,headRefName,mergedAt"
            ],
            output: CLIOutput(stdout: loadFixture("gh-pr-empty"), stderr: "", exitCode: 0)
        )

        let fetcher = GitHubPRFetcher(executor: fake, now: { Date() })
        let pr = try await fetcher.fetch(origin: origin, branch: branch)
        #expect(pr == nil)
    }
}

@Suite("GitHubPRFetcher.rollup")
struct GitHubPRFetcherRollupTests {
    // `gh pr checks --json ...` exposes the per-check verdict via the
    // `bucket` field (values: "pass", "fail", "pending", "skipping",
    // "cancel"), NOT `conclusion` (which is the underlying Actions
    // attribute visible only through the GraphQL API). Earlier code asked
    // gh for `conclusion` and got a hard error — this suite now pins
    // against the real gh schema.

    @Test func emptyIsNone() {
        #expect(GitHubPRFetcher.rollup([]) == PRInfo.Checks.none)
    }

    @Test func anyFailureWins() {
        #expect(GitHubPRFetcher.rollup([
            ("COMPLETED", "pass"),
            ("COMPLETED", "fail")
        ]) == .failure)
    }

    @Test func inProgressBeatsSuccess() {
        #expect(GitHubPRFetcher.rollup([
            ("COMPLETED", "pass"),
            ("IN_PROGRESS", nil)
        ]) == .pending)
    }

    @Test func pendingBucketIsPending() {
        #expect(GitHubPRFetcher.rollup([("PENDING", "pending")]) == .pending)
    }

    @Test func queuedStateIsPending() {
        #expect(GitHubPRFetcher.rollup([("QUEUED", nil)]) == .pending)
    }

    @Test func allPassIsSuccess() {
        #expect(GitHubPRFetcher.rollup([
            ("COMPLETED", "pass"),
            ("COMPLETED", "pass")
        ]) == .success)
    }

    @Test func completedWithNullBucketIsNone() {
        // Neutral / skipped checks: COMPLETED but gh didn't classify it.
        #expect(GitHubPRFetcher.rollup([
            ("COMPLETED", "pass"),
            ("COMPLETED", nil)
        ]) == PRInfo.Checks.none)
    }

    @Test func skippingAndCancelDoNotCountAsSuccess() {
        // One skip alongside passes: don't promote to "success" — user
        // probably wants visibility that not everything ran.
        #expect(GitHubPRFetcher.rollup([
            ("COMPLETED", "pass"),
            ("COMPLETED", "skipping")
        ]) == PRInfo.Checks.none)
    }
}
