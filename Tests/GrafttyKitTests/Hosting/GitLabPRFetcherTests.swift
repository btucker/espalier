import Testing
import Foundation
@testable import GrafttyKit

@Suite("GitLabPRFetcher")
struct GitLabPRFetcherTests {
    let origin = HostingOrigin(provider: .gitlab, host: "gitlab.com", owner: "foo", repo: "bar")
    let branch = "feature/blindspots"

    // PR-5.3: opened-only MR listing for the current glab CLI has no
    // state flag (default = opened). This shape also pins us against
    // glab's removal of the old `--state <opened|merged>` flag: if
    // glab changes again, the stub won't match and the tests will yell.
    var listOpenedArgs: [String] {
        ["mr", "list", "--repo", "foo/bar", "--source-branch", branch, "--per-page", "5", "-F", "json"]
    }

    var listMergedArgs: [String] {
        ["mr", "list", "--repo", "foo/bar", "--source-branch", branch, "--per-page", "5", "-F", "json", "--merged"]
    }

    func viewArgs(_ iid: Int) -> [String] {
        ["mr", "view", String(iid), "--repo", "foo/bar", "-F", "json"]
    }

    func loadFixture(_ name: String) -> String {
        let url = Bundle.module.url(forResource: name, withExtension: "json")!
        return try! String(contentsOf: url, encoding: .utf8)
    }

    @Test func returnsOpenMRWithSuccessChecks() async throws {
        let fake = FakeCLIExecutor()
        fake.stub(
            command: "glab",
            args: listOpenedArgs,
            output: CLIOutput(stdout: loadFixture("glab-mr-opened"), stderr: "", exitCode: 0)
        )
        fake.stub(
            command: "glab",
            args: viewArgs(512),
            output: CLIOutput(stdout: loadFixture("glab-mr-view-pipeline-success"), stderr: "", exitCode: 0)
        )

        let fetcher = GitLabPRFetcher(executor: fake, now: { Date() })
        let mr = try await fetcher.fetch(origin: origin, branch: branch)
        #expect(mr?.number == 512)
        #expect(mr?.state == .open)
        #expect(mr?.checks == .success)
    }

    @Test func filtersForkMRInFavorOfOriginMR() async throws {
        // `glab mr list` will surface same-source-branch MRs from forks
        // (their `source_project_id` differs from the target project's).
        // Parity with PR-5.1 on the GitHub side: take the origin-owned
        // MR, not the fork's, even if `glab`'s default sort puts the
        // fork first.
        let fake = FakeCLIExecutor()
        fake.stub(
            command: "glab",
            args: listOpenedArgs,
            output: CLIOutput(stdout: loadFixture("glab-mr-fork-open"), stderr: "", exitCode: 0)
        )
        fake.stub(
            command: "glab",
            args: viewArgs(512),
            output: CLIOutput(stdout: loadFixture("glab-mr-view-pipeline-success"), stderr: "", exitCode: 0)
        )

        let fetcher = GitLabPRFetcher(executor: fake, now: { Date() })
        let mr = try await fetcher.fetch(origin: origin, branch: branch)
        #expect(mr?.number == 512)
        #expect(mr?.state == .open)
        #expect(mr?.checks == .success)
    }

    @Test func returnsMergedWhenNoOpen() async throws {
        let fake = FakeCLIExecutor()
        fake.stub(
            command: "glab",
            args: listOpenedArgs,
            output: CLIOutput(stdout: loadFixture("glab-mr-empty"), stderr: "", exitCode: 0)
        )
        fake.stub(
            command: "glab",
            args: listMergedArgs,
            output: CLIOutput(stdout: loadFixture("glab-mr-merged"), stderr: "", exitCode: 0)
        )

        let fetcher = GitLabPRFetcher(executor: fake, now: { Date() })
        let mr = try await fetcher.fetch(origin: origin, branch: branch)
        #expect(mr?.number == 498)
        #expect(mr?.state == .merged)
        #expect(mr?.checks == PRInfo.Checks.none)
    }

    // PR-5.4 parity: if the pipeline-status view call fails after the
    // list call succeeded, still surface the MR with `.none` checks
    // rather than losing the whole PRInfo. Hiding the `#<iid>` badge
    // because pipeline couldn't resolve is worse UX than a neutral dot.
    @Test func pipelineViewFailureFallsBackToNoneChecks() async throws {
        let fake = FakeCLIExecutor()
        fake.stub(
            command: "glab",
            args: listOpenedArgs,
            output: CLIOutput(stdout: loadFixture("glab-mr-opened"), stderr: "", exitCode: 0)
        )
        fake.stub(
            command: "glab",
            args: viewArgs(512),
            error: .nonZeroExit(command: "glab", exitCode: 1, stderr: "network hiccup")
        )

        let fetcher = GitLabPRFetcher(executor: fake, now: { Date() })
        let mr = try await fetcher.fetch(origin: origin, branch: branch)
        #expect(mr?.number == 512)
        #expect(mr?.state == .open)
        #expect(mr?.checks == PRInfo.Checks.none)
    }
}

@Suite("GitLabPRFetcher.mapStatus")
struct GitLabPRFetcherMapStatusTests {
    @Test func successMaps() { #expect(GitLabPRFetcher.mapStatus("success") == .success) }
    @Test func failedMaps() { #expect(GitLabPRFetcher.mapStatus("failed") == .failure) }
    @Test func canceledMaps() { #expect(GitLabPRFetcher.mapStatus("canceled") == .failure) }
    @Test func runningMaps() { #expect(GitLabPRFetcher.mapStatus("running") == .pending) }
    @Test func pendingMaps() { #expect(GitLabPRFetcher.mapStatus("pending") == .pending) }
    @Test func preparingMaps() { #expect(GitLabPRFetcher.mapStatus("preparing") == .pending) }
    @Test func scheduledMaps() { #expect(GitLabPRFetcher.mapStatus("scheduled") == .pending) }
    @Test func unknownIsNone() { #expect(GitLabPRFetcher.mapStatus("something-new") == PRInfo.Checks.none) }
    @Test func caseInsensitive() { #expect(GitLabPRFetcher.mapStatus("SUCCESS") == .success) }
}
