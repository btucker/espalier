#if canImport(UIKit)
import Foundation
import Testing
@testable import GrafttyMobileKit

@Suite
struct ReposFetcherTests {

    @Test
    func buildsRequestAgainstBaseURL() throws {
        let base = URL(string: "http://mac.ts.net:8799/")!
        let request = try ReposFetcher.request(baseURL: base)
        #expect(request.url?.absoluteString == "http://mac.ts.net:8799/repos")
        #expect(request.httpMethod == "GET")
    }

    @Test
    func appendsReposPathEvenWhenBaseURLHasNoTrailingSlash() throws {
        let base = URL(string: "http://mac.ts.net:8799")!
        let request = try ReposFetcher.request(baseURL: base)
        #expect(request.url?.absoluteString == "http://mac.ts.net:8799/repos")
    }

    @Test
    func decodesReposResponse() throws {
        let raw = #"""
        [
          {"path":"/Users/a/projects/alpha","displayName":"alpha"},
          {"path":"/Users/a/projects/beta","displayName":"beta"}
        ]
        """#
        let result = try ReposFetcher.decode(Data(raw.utf8))
        #expect(result.count == 2)
        #expect(result.map(\.displayName) == ["alpha", "beta"])
        #expect(result.first?.path == "/Users/a/projects/alpha")
    }
}
#endif
