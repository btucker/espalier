import Foundation

public enum HostRepositorySnapshot {
    public struct Group: Identifiable, Sendable, Equatable {
        public var id: UUID
        public var host: MacHost
        public var hostHeader: String?
        public var repos: [RepoEntry]

        public init(id: UUID, host: MacHost, hostHeader: String?, repos: [RepoEntry]) {
            self.id = id
            self.host = host
            self.hostHeader = hostHeader
            self.repos = repos
        }
    }

    public static func groups(for state: AppState) -> [Group] {
        let hasRemoteHosts = state.visibleHosts.contains { $0.id != MacHost.localID }

        return state.visibleHosts.compactMap { host in
            let repos = repos(for: host, in: state)
            guard !repos.isEmpty else { return nil }

            return Group(
                id: host.id,
                host: host,
                hostHeader: hasRemoteHosts ? host.label : nil,
                repos: repos
            )
        }
    }

    private static func repos(for host: MacHost, in state: AppState) -> [RepoEntry] {
        if host.id == MacHost.localID {
            return state.repos.filter { state.hostID(forRepoPath: $0.path) == MacHost.localID }
        }

        let assignedRepos = state.repos.filter { state.hostID(forRepoPath: $0.path) == host.id }
        if !assignedRepos.isEmpty {
            return assignedRepos
        }
        return state.remoteRepoCache[host.id] ?? []
    }
}
