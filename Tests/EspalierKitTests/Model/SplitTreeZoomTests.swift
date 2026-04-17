import Testing
import Foundation
@testable import EspalierKit

@Suite("SplitTree — zoom state")
struct SplitTreeZoomTests {
    @Test func newTreeHasNoZoom() {
        let id = TerminalID()
        let tree = SplitTree(root: .leaf(id))
        #expect(tree.zoomed == nil)
    }

    @Test func initWithZoomedSetsZoomedField() {
        let id = TerminalID()
        let tree = SplitTree(root: .leaf(id), zoomed: id)
        #expect(tree.zoomed == id)
    }

    @Test func codableRoundTripPreservesZoom() throws {
        let id = TerminalID()
        let tree = SplitTree(root: .leaf(id), zoomed: id)
        let data = try JSONEncoder().encode(tree)
        let decoded = try JSONDecoder().decode(SplitTree.self, from: data)
        #expect(decoded.zoomed == id)
    }

    @Test func codableBackwardsCompatibleWithLegacyPayload() throws {
        // Payloads written before this feature have no `zoomed` key.
        let legacy = #"{"root":{"leaf":{"_0":{"id":"\#(UUID().uuidString)"}}}}"#
        let decoded = try JSONDecoder().decode(
            SplitTree.self,
            from: legacy.data(using: .utf8)!
        )
        #expect(decoded.zoomed == nil)
    }
}
