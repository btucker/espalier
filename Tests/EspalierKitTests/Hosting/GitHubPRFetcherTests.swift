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
                "--head", branch,
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
                "--head", branch, "--state", "open", "--limit", "1",
                "--json", "number,title,url,state,headRefName"
            ],
            output: CLIOutput(stdout: loadFixture("gh-pr-empty"), stderr: "", exitCode: 0)
        )
        fake.stub(
            command: "gh",
            args: [
                "pr", "list", "--repo", "btucker/espalier",
                "--head", branch, "--state", "merged", "--limit", "1",
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

    @Test func returnsNilWhenNoOpenOrMerged() async throws {
        let fake = FakeCLIExecutor()
        fake.stub(
            command: "gh",
            args: [
                "pr", "list", "--repo", "btucker/espalier",
                "--head", branch, "--state", "open", "--limit", "1",
                "--json", "number,title,url,state,headRefName"
            ],
            output: CLIOutput(stdout: loadFixture("gh-pr-empty"), stderr: "", exitCode: 0)
        )
        fake.stub(
            command: "gh",
            args: [
                "pr", "list", "--repo", "btucker/espalier",
                "--head", branch, "--state", "merged", "--limit", "1",
                "--json", "number,title,url,state,headRefName,mergedAt"
            ],
            output: CLIOutput(stdout: loadFixture("gh-pr-empty"), stderr: "", exitCode: 0)
        )

        let fetcher = GitHubPRFetcher(executor: fake, now: { Date() })
        let pr = try await fetcher.fetch(origin: origin, branch: branch)
        #expect(pr == nil)
    }

    @Test func checksPendingRollup() async throws {
        let fake = FakeCLIExecutor()
        fake.stub(
            command: "gh",
            args: [
                "pr", "list", "--repo", "btucker/espalier",
                "--head", branch, "--state", "open", "--limit", "1",
                "--json", "number,title,url,state,headRefName"
            ],
            output: CLIOutput(stdout: loadFixture("gh-pr-open-passing"), stderr: "", exitCode: 0)
        )
        fake.stub(
            command: "gh",
            args: ["pr", "checks", "412", "--repo", "btucker/espalier", "--json", "name,state,conclusion"],
            output: CLIOutput(stdout: loadFixture("gh-pr-checks-pending"), stderr: "", exitCode: 0)
        )

        let fetcher = GitHubPRFetcher(executor: fake, now: { Date() })
        let pr = try await fetcher.fetch(origin: origin, branch: branch)
        #expect(pr?.checks == .pending)
    }

    @Test func checksFailingRollup() async throws {
        let fake = FakeCLIExecutor()
        fake.stub(
            command: "gh",
            args: [
                "pr", "list", "--repo", "btucker/espalier",
                "--head", branch, "--state", "open", "--limit", "1",
                "--json", "number,title,url,state,headRefName"
            ],
            output: CLIOutput(stdout: loadFixture("gh-pr-open-passing"), stderr: "", exitCode: 0)
        )
        fake.stub(
            command: "gh",
            args: ["pr", "checks", "412", "--repo", "btucker/espalier", "--json", "name,state,conclusion"],
            output: CLIOutput(stdout: loadFixture("gh-pr-checks-failing"), stderr: "", exitCode: 0)
        )

        let fetcher = GitHubPRFetcher(executor: fake, now: { Date() })
        let pr = try await fetcher.fetch(origin: origin, branch: branch)
        #expect(pr?.checks == .failure)
    }

    @Test func checksNoneRollup() async throws {
        let fake = FakeCLIExecutor()
        fake.stub(
            command: "gh",
            args: [
                "pr", "list", "--repo", "btucker/espalier",
                "--head", branch, "--state", "open", "--limit", "1",
                "--json", "number,title,url,state,headRefName"
            ],
            output: CLIOutput(stdout: loadFixture("gh-pr-open-passing"), stderr: "", exitCode: 0)
        )
        fake.stub(
            command: "gh",
            args: ["pr", "checks", "412", "--repo", "btucker/espalier", "--json", "name,state,conclusion"],
            output: CLIOutput(stdout: loadFixture("gh-pr-checks-none"), stderr: "", exitCode: 0)
        )

        let fetcher = GitHubPRFetcher(executor: fake, now: { Date() })
        let pr = try await fetcher.fetch(origin: origin, branch: branch)
        #expect(pr?.checks == PRInfo.Checks.none)
    }
}
