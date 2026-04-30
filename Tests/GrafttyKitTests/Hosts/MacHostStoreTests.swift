import Foundation
import Testing
@testable import GrafttyKit

@Suite
struct MacHostStoreTests {
    @Test
    func freshStateHasImplicitLocalHost() {
        let state = AppState()

        #expect(state.visibleHosts == [MacHost.local])
        #expect(state.hostID(forRepoPath: "/missing") == MacHost.localID)
    }

    @Test
    func legacyJSONDecodesReposAsLocalHost() throws {
        let repoID = UUID()
        let json = """
        {
          "repos": [{
            "id": "\(repoID.uuidString)",
            "path": "/repo",
            "displayName": "repo",
            "isCollapsed": false,
            "worktrees": [],
            "bookmark": null
          }],
          "selectedWorktreePath": null,
          "windowFrame": {"x": 1, "y": 2, "width": 3, "height": 4},
          "sidebarWidth": 240
        }
        """.data(using: .utf8)!

        let state = try JSONDecoder().decode(AppState.self, from: json)

        #expect(state.visibleHosts == [MacHost.local])
        #expect(state.hostID(forRepoPath: "/repo") == MacHost.localID)
    }

    @Test
    func addingRemoteHostMakesLocalHostVisible() {
        var state = AppState()
        let remote = MacHost.ssh(sshHost: "dev-mini", username: "btucker")

        state.addHost(remote)

        #expect(state.visibleHosts.map(\.id) == [MacHost.localID, remote.id])
    }

    @Test
    func localOnlySidebarGroupsAreFlat() {
        var state = AppState()
        state.addRepo(RepoEntry(path: "/repo-a", displayName: "repo-a"))

        let groups = HostRepositorySnapshot.groups(for: state)

        #expect(groups.count == 1)
        #expect(groups[0].hostHeader == nil)
        #expect(groups[0].repos.map(\.displayName) == ["repo-a"])
    }

    @Test
    func multipleHostsShowHostHeadersWithoutChangingRepoEntries() {
        var state = AppState()
        let remote = MacHost.ssh(label: "dev-mini", sshHost: "dev-mini", username: nil)
        state.addHost(remote)
        state.addRepo(RepoEntry(path: "/local", displayName: "local"))
        state.addRepo(RepoEntry(path: "/remote", displayName: "remote"), hostID: remote.id)

        let groups = HostRepositorySnapshot.groups(for: state)

        #expect(groups.map(\.hostHeader) == ["This Mac", "dev-mini"])
        #expect(groups[0].repos.map(\.displayName) == ["local"])
        #expect(groups[1].repos.map(\.displayName) == ["remote"])
    }

    @Test
    func removingHostDropsRemoteCacheAndAssignments() {
        var state = AppState()
        let remote = MacHost.ssh(sshHost: "dev-mini", username: nil)
        state.addHost(remote)
        state.remoteRepoCache[remote.id] = [RepoEntry(path: "/remote", displayName: "remote")]
        state.repoHostAssignments["/remote"] = remote.id

        state.removeHost(remote.id)

        #expect(!state.visibleHosts.contains(where: { $0.id == remote.id }))
        #expect(state.remoteRepoCache[remote.id] == nil)
        #expect(state.repoHostAssignments["/remote"] == nil)
    }
}
