import Foundation

public struct GitLabPRFetcher: PRFetcher {
    private let executor: CLIExecutor
    private let now: @Sendable () -> Date

    public init(executor: CLIExecutor = CLIRunner(), now: @Sendable @escaping () -> Date = { Date() }) {
        self.executor = executor
        self.now = now
    }

    public func fetch(origin: HostingOrigin, branch: String) async throws -> PRInfo? {
        if let opened = try await fetchOne(origin: origin, branch: branch, scope: .opened) {
            // PR-5.4 parity: pipeline status is a SEPARATE `glab mr view`
            // call because the MR list endpoint (backing `glab mr list`)
            // doesn't include `head_pipeline` — only the single-MR view
            // does. If the view call fails, still surface the MR with
            // neutral checks rather than dropping the whole PRInfo.
            let checks = (try? await fetchPipelineStatus(origin: origin, iid: opened.iid)) ?? .none
            return PRInfo(
                number: opened.iid,
                // PR-5.5: strip BIDI-override scalars from the
                // author-controlled title (same rationale as the
                // GitHub side).
                title: BidiOverrides.stripping(opened.title),
                url: opened.web_url,
                state: .open,
                checks: checks,
                fetchedAt: now()
            )
        }
        if let merged = try await fetchOne(origin: origin, branch: branch, scope: .merged) {
            return PRInfo(
                number: merged.iid,
                title: BidiOverrides.stripping(merged.title),
                url: merged.web_url,
                state: .merged,
                checks: .none,
                fetchedAt: now()
            )
        }
        return nil
    }

    // MARK: - Internals

    enum Scope { case opened, merged }

    private struct RawMR: Decodable {
        let iid: Int
        let title: String
        let web_url: URL
        let state: String
        let source_branch: String
        // PR-5.3: `glab mr list --source-branch` returns MRs from forks
        // too (their source_project_id differs from the target
        // project's). We use these to filter forks out — same rationale
        // as `headRepositoryOwner` on the GitHub side.
        let source_project_id: Int?
        let target_project_id: Int?
    }

    private struct RawMRDetail: Decodable {
        let head_pipeline: RawPipeline?
    }

    private struct RawPipeline: Decodable {
        let id: Int
        let status: String
    }

    private func fetchOne(origin: HostingOrigin, branch: String, scope: Scope) async throws -> RawMR? {
        // PR-5.3: `--per-page 5` (rather than 1) so a fork MR returned
        // first by glab's default sort cannot crowd out a same-repo MR
        // that the source/target project-id filter would otherwise accept.
        // State selection is expressed via boolean flags (`--merged` for
        // merged MRs; the default is opened-only). The earlier
        // `--state <string>` spelling was removed by glab in favor of
        // discrete flags, which is why it was silently rejecting every
        // invocation and hiding the integration entirely.
        var args = [
            "mr", "list",
            "--repo", origin.slug,
            "--source-branch", branch,
            "--per-page", "5",
            "-F", "json"
        ]
        if case .merged = scope { args.append("--merged") }
        let output = try await executor.run(command: "glab", args: args, at: NSTemporaryDirectory())
        let data = Data(output.stdout.utf8)
        let mrs = try JSONDecoder().decode([RawMR].self, from: data)
        return mrs.first { mr in
            guard let src = mr.source_project_id, let tgt = mr.target_project_id else { return false }
            return src == tgt
        }
    }

    private func fetchPipelineStatus(origin: HostingOrigin, iid: Int) async throws -> PRInfo.Checks {
        let args = [
            "mr", "view", String(iid),
            "--repo", origin.slug,
            "-F", "json"
        ]
        let output = try await executor.run(command: "glab", args: args, at: NSTemporaryDirectory())
        let data = Data(output.stdout.utf8)
        let detail = try JSONDecoder().decode(RawMRDetail.self, from: data)
        return detail.head_pipeline.map { Self.mapStatus($0.status) } ?? .none
    }

    static func mapStatus(_ status: String) -> PRInfo.Checks {
        switch status.lowercased() {
        case "success": return .success
        case "failed", "canceled": return .failure
        case "running", "pending", "waiting_for_resource", "preparing", "scheduled": return .pending
        default: return .none
        }
    }
}
