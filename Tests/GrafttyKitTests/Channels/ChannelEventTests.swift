import XCTest
@testable import GrafttyKit

final class ChannelEventTests: XCTestCase {
    func testSubscribeMessageRoundTrip() throws {
        let original = ChannelClientMessage.subscribe(
            worktree: "/repos/acme-web/feature/login",
            version: 1
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ChannelClientMessage.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testPRStateChangedEventRoundTrip() throws {
        let original = ChannelServerMessage.event(
            type: "pr_state_changed",
            attrs: [
                "pr_number": "42",
                "from": "open",
                "to": "merged",
                "provider": "github",
                "repo": "acme/web",
                "worktree": "/repos/acme-web/feature/login",
                "pr_url": "https://github.com/acme/web/pull/42",
            ],
            body: "PR #42 merged by @alice"
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ChannelServerMessage.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testInstructionsEventRoundTrip() throws {
        let original = ChannelServerMessage.event(
            type: "instructions",
            attrs: [:],
            body: "You receive events from Graftty..."
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ChannelServerMessage.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testUnknownClientMessageTypeRejected() {
        let json = #"{"type": "nonsense", "worktree": "/x"}"#.data(using: .utf8)!
        XCTAssertThrowsError(try JSONDecoder().decode(ChannelClientMessage.self, from: json))
    }
}
