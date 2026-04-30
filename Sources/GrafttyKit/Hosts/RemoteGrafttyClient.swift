import Foundation

public protocol RemoteGrafttyProbing: Sendable {
    func probe(baseURL: URL) async throws
}

public struct RemoteGrafttyClient: RemoteGrafttyProbing, Sendable {
    public enum Error: Swift.Error, Equatable {
        case grafttyUnavailable
        case transport
    }

    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func probe(baseURL: URL) async throws {
        do {
            let (_, response) = try await session.data(from: baseURL.appending(path: "repos"))
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw Error.grafttyUnavailable
            }
        } catch let error as Error {
            throw error
        } catch {
            throw Error.transport
        }
    }

    public func fetchRepositorySnapshot(baseURL: URL) async throws -> [RepoEntry] {
        let repos = try await fetchRepos(baseURL: baseURL)
        return repos.map { repo in
            RepoEntry(
                path: repo.path,
                displayName: repo.displayName,
                worktrees: [WorktreeEntry(path: repo.path, branch: "remote")]
            )
        }
    }

    private func fetchRepos(baseURL: URL) async throws -> [RemoteRepoInfo] {
        do {
            let (data, response) = try await session.data(from: baseURL.appending(path: "repos"))
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw Error.grafttyUnavailable
            }
            return try JSONDecoder().decode([RemoteRepoInfo].self, from: data)
        } catch let error as Error {
            throw error
        } catch is DecodingError {
            throw Error.grafttyUnavailable
        } catch {
            throw Error.transport
        }
    }
}

private struct RemoteRepoInfo: Codable, Sendable, Equatable {
    var path: String
    var displayName: String
}

public enum AddHostConnectionResult: Equatable {
    case success(localBaseURL: URL)
    case sshFailed(String)
    case grafttyUnavailable(String)
}

public struct AddHostConnectionTester: Sendable {
    private let forwarder: any SSHLocalForwarding
    private let client: any RemoteGrafttyProbing

    public init(
        forwarder: any SSHLocalForwarding = SystemSSHLocalForwarder(),
        client: any RemoteGrafttyProbing = RemoteGrafttyClient()
    ) {
        self.forwarder = forwarder
        self.client = client
    }

    public func test(config: SSHHostConfig) async -> AddHostConnectionResult {
        let tunnel: any SSHLocalForwardProcess
        do {
            tunnel = try await forwarder.start(config: config)
        } catch {
            return .sshFailed("SSH could not connect to \(config.sshHost). Check the host, username, port, and your SSH configuration.")
        }

        let baseURL = URL(string: "http://127.0.0.1:\(tunnel.localPort)/")!
        do {
            try await client.probe(baseURL: baseURL)
            return .success(localBaseURL: baseURL)
        } catch {
            tunnel.stop()
            return .grafttyUnavailable("SSH connected, but Graftty did not respond on the remote Mac. Open Graftty on \(config.sshHost) and enable SSH Tunnel mode.")
        }
    }
}
