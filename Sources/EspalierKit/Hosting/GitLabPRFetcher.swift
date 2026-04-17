import Foundation

public struct GitLabPRFetcher: PRFetcher {
    private let executor: CLIExecutor
    private let now: @Sendable () -> Date

    public init(executor: CLIExecutor = CLIRunner(), now: @Sendable @escaping () -> Date = Date.init) {
        self.executor = executor
        self.now = now
    }

    public func fetch(origin: HostingOrigin, branch: String) async throws -> PRInfo? {
        if let opened = try await fetchOne(origin: origin, branch: branch, state: "opened") {
            let checks = try await fetchChecks(origin: origin, pipelineId: opened.head_pipeline?.id)
            return PRInfo(
                number: opened.iid,
                title: opened.title,
                url: opened.web_url,
                state: .open,
                checks: checks,
                fetchedAt: now()
            )
        }
        if let merged = try await fetchOne(origin: origin, branch: branch, state: "merged") {
            return PRInfo(
                number: merged.iid,
                title: merged.title,
                url: merged.web_url,
                state: .merged,
                checks: .none,
                fetchedAt: now()
            )
        }
        return nil
    }

    // MARK: - Internals

    private struct RawMR: Decodable {
        let iid: Int
        let title: String
        let web_url: URL
        let state: String
        let source_branch: String
        let head_pipeline: RawPipeline?
    }

    private struct RawPipeline: Decodable {
        let id: Int
        let status: String
    }

    private func fetchOne(origin: HostingOrigin, branch: String, state: String) async throws -> RawMR? {
        let args = [
            "mr", "list",
            "--repo", origin.slug,
            "--source-branch", branch,
            "--state", state,
            "--per-page", "1",
            "-F", "json"
        ]
        let output = try await executor.run(command: "glab", args: args, at: NSHomeDirectory())
        let data = Data(output.stdout.utf8)
        let mrs = try JSONDecoder().decode([RawMR].self, from: data)
        return mrs.first
    }

    private func fetchChecks(origin: HostingOrigin, pipelineId: Int?) async throws -> PRInfo.Checks {
        guard let pipelineId else { return .none }
        let args = ["ci", "get", "--repo", origin.slug, "--pipeline-id", String(pipelineId), "-F", "json"]
        let output = try await executor.run(command: "glab", args: args, at: NSHomeDirectory())
        let data = Data(output.stdout.utf8)
        let pipeline = try JSONDecoder().decode(RawPipeline.self, from: data)
        return Self.mapStatus(pipeline.status)
    }

    private static func mapStatus(_ status: String) -> PRInfo.Checks {
        switch status.lowercased() {
        case "success": return .success
        case "failed", "canceled": return .failure
        case "running", "pending", "waiting_for_resource", "preparing", "scheduled": return .pending
        default: return .none
        }
    }
}
