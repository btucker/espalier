import Foundation

public enum WorktreeRoute: Equatable, Sendable {
    case local(worktreePath: String)
    case remote(hostID: UUID, worktreePath: String)

    public static func resolve(path: String, state: AppState) -> WorktreeRoute {
        for (hostID, repos) in state.remoteRepoCache {
            for repo in repos {
                if repo.path == path || repo.worktrees.contains(where: { $0.path == path }) {
                    return .remote(hostID: hostID, worktreePath: path)
                }
            }
        }
        return .local(worktreePath: path)
    }
}
