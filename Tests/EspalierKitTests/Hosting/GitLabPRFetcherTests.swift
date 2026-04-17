import Testing
import Foundation
@testable import EspalierKit

@Suite("GitLabPRFetcher")
struct GitLabPRFetcherTests {
    let origin = HostingOrigin(provider: .gitlab, host: "gitlab.com", owner: "foo", repo: "bar")
    let branch = "feature/blindspots"

    func loadFixture(_ name: String) -> String {
        let url = Bundle.module.url(forResource: name, withExtension: "json")!
        return try! String(contentsOf: url, encoding: .utf8)
    }

    @Test func returnsOpenMRWithSuccessChecks() async throws {
        let fake = FakeCLIExecutor()
        fake.stub(
            command: "glab",
            args: [
                "mr", "list",
                "--repo", "foo/bar",
                "--source-branch", branch,
                "--state", "opened",
                "--per-page", "1",
                "-F", "json"
            ],
            output: CLIOutput(stdout: loadFixture("glab-mr-opened"), stderr: "", exitCode: 0)
        )
        fake.stub(
            command: "glab",
            args: ["ci", "get", "--repo", "foo/bar", "--pipeline-id", "9001", "-F", "json"],
            output: CLIOutput(stdout: loadFixture("glab-pipeline-success"), stderr: "", exitCode: 0)
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
            args: [
                "mr", "list",
                "--repo", "foo/bar",
                "--source-branch", branch,
                "--state", "opened",
                "--per-page", "1",
                "-F", "json"
            ],
            output: CLIOutput(stdout: loadFixture("glab-mr-empty"), stderr: "", exitCode: 0)
        )
        fake.stub(
            command: "glab",
            args: [
                "mr", "list",
                "--repo", "foo/bar",
                "--source-branch", branch,
                "--state", "merged",
                "--per-page", "1",
                "-F", "json"
            ],
            output: CLIOutput(stdout: loadFixture("glab-mr-merged"), stderr: "", exitCode: 0)
        )

        let fetcher = GitLabPRFetcher(executor: fake, now: { Date() })
        let mr = try await fetcher.fetch(origin: origin, branch: branch)
        #expect(mr?.number == 498)
        #expect(mr?.state == .merged)
        #expect(mr?.checks == PRInfo.Checks.none)
    }

    @Test func pipelineStatusMapping() async throws {
        func tryStatus(_ fixture: String) async throws -> PRInfo.Checks? {
            let fake = FakeCLIExecutor()
            fake.stub(
                command: "glab",
                args: [
                    "mr", "list",
                    "--repo", "foo/bar",
                    "--source-branch", branch,
                    "--state", "opened",
                    "--per-page", "1",
                    "-F", "json"
                ],
                output: CLIOutput(stdout: loadFixture("glab-mr-opened"), stderr: "", exitCode: 0)
            )
            fake.stub(
                command: "glab",
                args: ["ci", "get", "--repo", "foo/bar", "--pipeline-id", "9001", "-F", "json"],
                output: CLIOutput(stdout: loadFixture(fixture), stderr: "", exitCode: 0)
            )
            let fetcher = GitLabPRFetcher(executor: fake, now: { Date() })
            return try await fetcher.fetch(origin: origin, branch: branch)?.checks
        }

        #expect(try await tryStatus("glab-pipeline-running") == .pending)
        #expect(try await tryStatus("glab-pipeline-failed") == .failure)
        #expect(try await tryStatus("glab-pipeline-success") == .success)
    }
}
