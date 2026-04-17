import Foundation

public struct GitHubPRFetcher: PRFetcher {
    private let executor: CLIExecutor
    private let now: @Sendable () -> Date

    public init(executor: CLIExecutor = CLIRunner(), now: @Sendable @escaping () -> Date = Date.init) {
        self.executor = executor
        self.now = now
    }

    public func fetch(origin: HostingOrigin, branch: String) async throws -> PRInfo? {
        if let open = try await fetchOne(origin: origin, branch: branch, state: "open") {
            let checks = try await fetchChecks(origin: origin, number: open.number)
            return PRInfo(
                number: open.number,
                title: open.title,
                url: open.url,
                state: .open,
                checks: checks,
                fetchedAt: now()
            )
        }
        if let merged = try await fetchOne(origin: origin, branch: branch, state: "merged") {
            return PRInfo(
                number: merged.number,
                title: merged.title,
                url: merged.url,
                state: .merged,
                checks: .none,
                fetchedAt: now()
            )
        }
        return nil
    }

    // MARK: - Internals

    private struct RawPR: Decodable {
        let number: Int
        let title: String
        let url: URL
        let state: String
        let headRefName: String
    }

    private struct RawCheck: Decodable {
        let name: String
        let state: String
        let conclusion: String?
    }

    private func fetchOne(origin: HostingOrigin, branch: String, state: String) async throws -> RawPR? {
        var args = [
            "pr", "list",
            "--repo", origin.slug,
            "--head", branch,
            "--state", state,
            "--limit", "1",
            "--json", "number,title,url,state,headRefName"
        ]
        if state == "merged" {
            if let idx = args.firstIndex(of: "number,title,url,state,headRefName") {
                args[idx] = "number,title,url,state,headRefName,mergedAt"
            }
        }
        let output = try await executor.run(command: "gh", args: args, at: NSHomeDirectory())
        let data = Data(output.stdout.utf8)
        let prs = try JSONDecoder().decode([RawPR].self, from: data)
        return prs.first
    }

    private func fetchChecks(origin: HostingOrigin, number: Int) async throws -> PRInfo.Checks {
        let args = [
            "pr", "checks", String(number),
            "--repo", origin.slug,
            "--json", "name,state,conclusion"
        ]
        let output = try await executor.run(command: "gh", args: args, at: NSHomeDirectory())
        let data = Data(output.stdout.utf8)
        let checks = try JSONDecoder().decode([RawCheck].self, from: data)
        return Self.rollup(checks)
    }

    private static func rollup(_ checks: [RawCheck]) -> PRInfo.Checks {
        if checks.isEmpty { return .none }
        if checks.contains(where: { ($0.conclusion ?? "").uppercased() == "FAILURE" }) {
            return .failure
        }
        if checks.contains(where: {
            let s = $0.state.uppercased()
            return s == "IN_PROGRESS" || s == "QUEUED" || s == "PENDING"
        }) {
            return .pending
        }
        if checks.allSatisfy({ ($0.conclusion ?? "").uppercased() == "SUCCESS" }) {
            return .success
        }
        return .none
    }
}
