import Foundation

public enum GitPathType: Equatable, Sendable {
    case repoRoot(String)
    case worktree(worktreePath: String, repoPath: String)
    case notARepo
}

public enum GitRepoDetector {
    public static func detect(path: String) throws -> GitPathType {
        // `CanonicalPath.canonicalize` (POSIX `realpath`) matches the path
        // shape that `git worktree list --porcelain` emits and that
        // `state.json` therefore stores. Foundation's symlink resolvers
        // collapse `/private/tmp` → `/tmp` — the opposite direction —
        // which made `espalier notify` run from under `/tmp/*` fail
        // "Not inside a tracked worktree" even for tracked worktrees.
        var current = URL(fileURLWithPath: CanonicalPath.canonicalize(path))

        while true {
            let gitPath = current.appendingPathComponent(".git")

            if FileManager.default.fileExists(atPath: gitPath.path) {
                var isDir: ObjCBool = false
                FileManager.default.fileExists(atPath: gitPath.path, isDirectory: &isDir)

                if isDir.boolValue {
                    return .repoRoot(current.path)
                } else {
                    let contents = try String(contentsOf: gitPath, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
                    guard contents.hasPrefix("gitdir: ") else { return .notARepo }
                    let gitDir = String(contents.dropFirst("gitdir: ".count))
                    let repoPath = resolveRepoRoot(fromGitDir: gitDir, worktreePath: current.path)
                    return .worktree(worktreePath: current.path, repoPath: repoPath)
                }
            }

            let parent = current.deletingLastPathComponent()
            if parent.path == current.path { return .notARepo }
            current = parent
        }
    }

    private static func resolveRepoRoot(fromGitDir gitDir: String, worktreePath: String) -> String {
        // Git ≥ 2.52 with `worktree.useRelativePaths=true` writes
        // relative gitdir entries in the worktree's `.git` file
        // (`gitdir: ../repo/.git/worktrees/name`). Feeding that to
        // `realpath(3)` resolves against the process cwd — unrelated
        // to the worktree dir — so the returned repoPath was wrong.
        // Resolve relative inputs against the worktree dir first.
        // `GIT-1.4`.
        let absoluteGitDir: String
        if gitDir.hasPrefix("/") {
            absoluteGitDir = gitDir
        } else {
            absoluteGitDir = URL(fileURLWithPath: worktreePath)
                .appendingPathComponent(gitDir)
                .standardized
                .path
        }
        // Same private-root issue as `detect`: use realpath so the
        // repoPath we return matches what `state.json` holds.
        var url = URL(fileURLWithPath: CanonicalPath.canonicalize(absoluteGitDir))
        while url.lastPathComponent != ".git" && url.path != "/" {
            url = url.deletingLastPathComponent()
        }
        return url.deletingLastPathComponent().path
    }
}
