import Foundation

public enum GitOriginDefaultBranch {

    /// Resolves the origin default branch for a repository.
    ///
    /// Returns a short ref like `"origin/main"` suitable for direct use in
    /// `git rev-list` / `git diff` arguments, or `nil` if there is no origin
    /// remote or no default branch can be identified.
    ///
    /// Local only — never hits the network. First tries `git symbolic-ref
    /// --short refs/remotes/origin/HEAD`; on failure, probes `origin/main`,
    /// `origin/master`, `origin/develop` in order via `git show-ref --verify`.
    public static func resolve(repoPath: String) throws -> String? {
        if let (out, code) = try? runGitCapturing(
            args: ["symbolic-ref", "--short", "refs/remotes/origin/HEAD"],
            at: repoPath
        ), code == 0 {
            let trimmed = out.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }

        // Probe fallback. show-ref --verify exits 0 if the ref exists, non-zero
        // otherwise. We check `refs/remotes/origin/<name>` directly so a
        // local branch of the same name doesn't false-positive.
        for candidate in ["main", "master", "develop"] {
            guard let (_, code) = try? runGitCapturing(
                args: ["show-ref", "--verify", "--quiet", "refs/remotes/origin/\(candidate)"],
                at: repoPath
            ) else { continue }
            if code == 0 { return "origin/\(candidate)" }
        }

        return nil
    }

    /// Runs git and returns `(stdout, terminationStatus)`. Never throws on
    /// non-zero exit — callers decide whether the exit code is meaningful.
    /// Throws only if the process itself fails to launch.
    private static func runGitCapturing(args: [String], at directory: String) throws -> (String, Int32) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
        process.currentDirectoryURL = URL(fileURLWithPath: directory)
        let stdoutPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let out = String(data: data, encoding: .utf8) ?? ""
        return (out, process.terminationStatus)
    }
}
