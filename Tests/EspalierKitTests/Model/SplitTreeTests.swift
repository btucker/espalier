import Foundation
import Testing
@testable import EspalierKit

@Suite("SplitTree Tests")
struct SplitTreeTests {

    @Test func singleLeaf() {
        let id = TerminalID()
        let tree = SplitTree(root: .leaf(id))
        #expect(tree.root != nil)
        if case .leaf(let leafID) = tree.root {
            #expect(leafID == id)
        } else {
            Issue.record("Expected leaf node")
        }
    }

    @Test func horizontalSplit() {
        let left = TerminalID()
        let right = TerminalID()
        let tree = SplitTree(root: .split(.init(
            direction: .horizontal,
            ratio: 0.5,
            left: .leaf(left),
            right: .leaf(right)
        )))
        #expect(tree.leafCount == 2)
    }

    @Test func insertSplitAtLeaf() {
        let original = TerminalID()
        let tree = SplitTree(root: .leaf(original))
        let newID = TerminalID()
        let updated = tree.inserting(newID, at: original, direction: .horizontal)
        #expect(updated.leafCount == 2)
    }

    @Test func removeLeaf() {
        let left = TerminalID()
        let right = TerminalID()
        let tree = SplitTree(root: .split(.init(
            direction: .horizontal,
            ratio: 0.5,
            left: .leaf(left),
            right: .leaf(right)
        )))
        let updated = tree.removing(left)
        #expect(updated.leafCount == 1)
        if case .leaf(let remaining) = updated.root {
            #expect(remaining == right)
        } else {
            Issue.record("Expected single leaf after removal")
        }
    }

    @Test func removeLastLeafReturnsNilRoot() {
        let id = TerminalID()
        let tree = SplitTree(root: .leaf(id))
        let updated = tree.removing(id)
        #expect(updated.root == nil)
    }

    @Test func allLeaves() {
        let a = TerminalID()
        let b = TerminalID()
        let c = TerminalID()
        let tree = SplitTree(root: .split(.init(
            direction: .horizontal,
            ratio: 0.5,
            left: .leaf(a),
            right: .split(.init(
                direction: .vertical,
                ratio: 0.5,
                left: .leaf(b),
                right: .leaf(c)
            ))
        )))
        let leaves = tree.allLeaves
        #expect(leaves.count == 3)
        #expect(leaves.contains(a))
        #expect(leaves.contains(b))
        #expect(leaves.contains(c))
    }

    @Test func codableRoundTrip() throws {
        let a = TerminalID()
        let b = TerminalID()
        let tree = SplitTree(root: .split(.init(
            direction: .horizontal,
            ratio: 0.6,
            left: .leaf(a),
            right: .leaf(b)
        )))
        let data = try JSONEncoder().encode(tree)
        let decoded = try JSONDecoder().decode(SplitTree.self, from: data)
        #expect(decoded.leafCount == 2)
        #expect(decoded.allLeaves.contains(a))
        #expect(decoded.allLeaves.contains(b))
    }
}
