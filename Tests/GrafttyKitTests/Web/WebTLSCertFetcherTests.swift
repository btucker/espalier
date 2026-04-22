import Testing
import Foundation
@testable import GrafttyKit

@Suite("WebTLSCertFetcher")
struct WebTLSCertFetcherTests {

    private func loadPEM(_ name: String) throws -> Data {
        let url = try #require(
            Bundle.module.url(forResource: name, withExtension: "pem",
                              subdirectory: "Fixtures")
        )
        return try Data(contentsOf: url)
    }

    @Test func buildContext_fromValidPEMs_succeeds() throws {
        let cert = try loadPEM("test-tls-cert")
        let key = try loadPEM("test-tls-key")
        _ = try WebTLSCertFetcher.buildContext(certPEM: cert, keyPEM: key)
    }

    @Test func buildContext_garbage_throws() {
        let junk = Data("not pem".utf8)
        #expect(throws: (any Swift.Error).self) {
            _ = try WebTLSCertFetcher.buildContext(certPEM: junk, keyPEM: junk)
        }
    }
}
