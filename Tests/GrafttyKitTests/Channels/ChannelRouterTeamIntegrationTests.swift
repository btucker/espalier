import XCTest
@testable import GrafttyKit

@MainActor
final class ChannelRouterTeamIntegrationTests: XCTestCase {

    private var socketPath: String!

    override func setUp() async throws {
        socketPath = "/tmp/graftty-channel-test-\(UUID().uuidString).sock"
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(atPath: socketPath)
    }

    func testProviderReceivesPerWorktreeContext() async throws {
        var calls: [String] = []
        let router = ChannelRouter(
            socketPath: socketPath,
            promptProvider: { wt in
                calls.append(wt)
                return "prompt-for-\(wt)"
            }
        )
        try router.start()
        defer { router.stop() }

        let client1 = try ChannelTestClient.connect(path: socketPath)
        try client1.send(#"{"type":"subscribe","worktree":"/r/a","version":1}\#n"#)
        let client2 = try ChannelTestClient.connect(path: socketPath)
        try client2.send(#"{"type":"subscribe","worktree":"/r/b","version":1}\#n"#)

        try await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertTrue(calls.contains("/r/a"))
        XCTAssertTrue(calls.contains("/r/b"))
    }

    func testInitialInstructionsContainWorktreePath() async throws {
        let router = ChannelRouter(
            socketPath: socketPath,
            // Use a prompt that doesn't contain "/" so JSON encoding doesn't
            // escape slashes, making assertions straightforward.
            promptProvider: { wt in "prompt-for-wt1" }
        )
        try router.start()
        defer { router.stop() }

        let client = try ChannelTestClient.connect(path: socketPath)
        try client.send(#"{"type":"subscribe","worktree":"/r/wt1","version":1}\#n"#)

        let line = try client.readLine(timeout: 2.0)
        XCTAssertTrue(line.contains("\"type\":\"instructions\""))
        XCTAssertTrue(line.contains("prompt-for-wt1"))
    }

    func testBroadcastInstructionsRendersPerSubscriber() async throws {
        // Use worktree identifiers that don't contain "/" to avoid JSON
        // slash-escaping in raw string comparisons.
        let router = ChannelRouter(
            socketPath: socketPath,
            promptProvider: { wt in "body-\(wt.replacingOccurrences(of: "/", with: "-"))" }
        )
        try router.start()
        defer { router.stop() }

        let c1 = try ChannelTestClient.connect(path: socketPath)
        try c1.send(#"{"type":"subscribe","worktree":"/r/a","version":1}\#n"#)
        _ = try c1.readLine(timeout: 2.0)  // drain initial instructions

        let c2 = try ChannelTestClient.connect(path: socketPath)
        try c2.send(#"{"type":"subscribe","worktree":"/r/b","version":1}\#n"#)
        _ = try c2.readLine(timeout: 2.0)

        try await Task.sleep(nanoseconds: 200_000_000)

        router.broadcastInstructions()

        let r1 = try c1.readLine(timeout: 2.0)
        let r2 = try c2.readLine(timeout: 2.0)
        XCTAssertTrue(r1.contains("body--r-a"), "c1 got: \(r1)")
        XCTAssertTrue(r2.contains("body--r-b"), "c2 got: \(r2)")
    }
}
