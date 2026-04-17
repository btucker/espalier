import Testing
import Foundation
@testable import EspalierKit

@Suite("PRStatusStore integration")
struct PRStatusStoreIntegrationTests {

    @Test func fetchesAndPublishesPRInfo() async throws {
        let fake = FakeCLIExecutor()
        fake.stub(
            command: "gh",
            args: [
                "pr", "list", "--repo", "foo/bar",
                "--head", "feature/x", "--state", "open", "--limit", "1",
                "--json", "number,title,url,state,headRefName"
            ],
            output: CLIOutput(
                stdout: #"[{"number":10,"title":"hello","url":"https://github.com/foo/bar/pull/10","state":"OPEN","headRefName":"feature/x"}]"#,
                stderr: "",
                exitCode: 0
            )
        )
        fake.stub(
            command: "gh",
            args: ["pr", "checks", "10", "--repo", "foo/bar", "--json", "name,state,conclusion"],
            output: CLIOutput(stdout: "[]", stderr: "", exitCode: 0)
        )

        // Inject a host detector so the test doesn't need to touch GitRunner's
        // shared-state executor (which races with other suites in parallel).
        let origin = HostingOrigin(provider: .github, host: "github.com", owner: "foo", repo: "bar")
        let store = await PRStatusStore(
            executor: fake,
            detectHost: { _ in origin }
        )
        await store.refresh(worktreePath: "/wt", repoPath: "/repo", branch: "feature/x")

        // Poll for the async Task to complete.
        for _ in 0..<50 {
            if await store.infos["/wt"] != nil { break }
            try await Task.sleep(for: .milliseconds(50))
        }

        let info = await store.infos["/wt"]
        #expect(info?.number == 10)
        #expect(info?.state == .open)
        #expect(info?.checks == PRInfo.Checks.none)
    }

    @Test func absentWhenNoPR() async throws {
        let fake = FakeCLIExecutor()
        fake.stub(
            command: "gh",
            args: [
                "pr", "list", "--repo", "foo/bar",
                "--head", "feature/x", "--state", "open", "--limit", "1",
                "--json", "number,title,url,state,headRefName"
            ],
            output: CLIOutput(stdout: "[]", stderr: "", exitCode: 0)
        )
        fake.stub(
            command: "gh",
            args: [
                "pr", "list", "--repo", "foo/bar",
                "--head", "feature/x", "--state", "merged", "--limit", "1",
                "--json", "number,title,url,state,headRefName,mergedAt"
            ],
            output: CLIOutput(stdout: "[]", stderr: "", exitCode: 0)
        )

        let origin = HostingOrigin(provider: .github, host: "github.com", owner: "foo", repo: "bar")
        let store = await PRStatusStore(
            executor: fake,
            detectHost: { _ in origin }
        )
        await store.refresh(worktreePath: "/wt", repoPath: "/repo", branch: "feature/x")

        for _ in 0..<50 {
            if await store.absent.contains("/wt") { break }
            try await Task.sleep(for: .milliseconds(50))
        }

        #expect(await store.infos["/wt"] == nil)
        #expect(await store.absent.contains("/wt"))
    }

    @Test func unsupportedHostMarksAbsent() async throws {
        let fake = FakeCLIExecutor()

        let origin = HostingOrigin(provider: .unsupported, host: "bitbucket.org", owner: "foo", repo: "bar")
        let store = await PRStatusStore(
            executor: fake,
            detectHost: { _ in origin }
        )
        await store.refresh(worktreePath: "/wt", repoPath: "/repo", branch: "main")

        for _ in 0..<50 {
            if await store.absent.contains("/wt") { break }
            try await Task.sleep(for: .milliseconds(50))
        }

        #expect(await store.absent.contains("/wt"))
    }
}
