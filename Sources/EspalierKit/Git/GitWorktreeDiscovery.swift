import Foundation

public struct DiscoveredWorktree: Sendable {
    public let path: String
    public let branch: String
}

public enum GitWorktreeDiscovery {
    public static func parsePorcelain(_ output: String) -> [DiscoveredWorktree] {
        var results: [DiscoveredWorktree] = []
        var currentPath: String?
        var currentBranch: String?

        for line in output.components(separatedBy: "\n") {
            if line.hasPrefix("worktree ") {
                if let path = currentPath {
                    results.append(DiscoveredWorktree(path: path, branch: currentBranch ?? "(unknown)"))
                }
                currentPath = String(line.dropFirst("worktree ".count))
                currentBranch = nil
            } else if line.hasPrefix("branch refs/heads/") {
                currentBranch = String(line.dropFirst("branch refs/heads/".count))
            } else if line == "detached" {
                currentBranch = "(detached)"
            } else if line == "bare" {
                currentBranch = "(bare)"
            }
        }

        if let path = currentPath {
            results.append(DiscoveredWorktree(path: path, branch: currentBranch ?? "(unknown)"))
        }

        return results
    }

    public static func discover(repoPath: String) throws -> [DiscoveredWorktree] {
        let output = try runGit(args: ["worktree", "list", "--porcelain"], at: repoPath)
        return parsePorcelain(output)
    }

    private static func runGit(args: [String], at directory: String) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
        process.currentDirectoryURL = URL(fileURLWithPath: directory)
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw GitDiscoveryError.gitFailed(terminationStatus: process.terminationStatus)
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }
}

public enum GitDiscoveryError: Error {
    case gitFailed(terminationStatus: Int32)
}
