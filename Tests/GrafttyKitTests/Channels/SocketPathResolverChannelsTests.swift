import XCTest
@testable import GrafttyKit

final class SocketPathResolverChannelsTests: XCTestCase {
    func testChannelsPathDefaultsToApplicationSupportSubdirectory() {
        let tempDir = URL(fileURLWithPath: "/tmp/GrafttyTest")
        let path = SocketPathResolver.resolveChannels(
            environment: [:],
            defaultDirectory: tempDir
        )
        XCTAssertEqual(path, "/tmp/GrafttyTest/graftty-channels.sock")
    }

    func testChannelsPathHonorsGRAFTTYChannelsSockEnvironment() {
        let path = SocketPathResolver.resolveChannels(
            environment: ["GRAFTTY_CHANNELS_SOCK": "/custom/chan.sock"],
            defaultDirectory: URL(fileURLWithPath: "/unused")
        )
        XCTAssertEqual(path, "/custom/chan.sock")
    }

    func testEmptyEnvironmentValueFallsBackToDefault() {
        let path = SocketPathResolver.resolveChannels(
            environment: ["GRAFTTY_CHANNELS_SOCK": ""],
            defaultDirectory: URL(fileURLWithPath: "/tmp/GrafttyTest")
        )
        XCTAssertEqual(path, "/tmp/GrafttyTest/graftty-channels.sock")
    }
}
