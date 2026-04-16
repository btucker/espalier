import Foundation

public enum SplitDirection: String, Codable, Sendable {
    case horizontal
    case vertical
}

public struct SplitTree: Codable, Sendable, Equatable {
    public let root: Node?

    public init(root: Node?) {
        self.root = root
    }

    public indirect enum Node: Codable, Sendable, Equatable {
        case leaf(TerminalID)
        case split(Split)

        public struct Split: Codable, Sendable, Equatable {
            public let direction: SplitDirection
            public let ratio: Double
            public let left: Node
            public let right: Node

            public init(direction: SplitDirection, ratio: Double, left: Node, right: Node) {
                self.direction = direction
                self.ratio = ratio
                self.left = left
                self.right = right
            }

            public func withRatio(_ newRatio: Double) -> Split {
                Split(direction: direction, ratio: newRatio, left: left, right: right)
            }
        }
    }

    // MARK: - Queries

    public var leafCount: Int {
        guard let root else { return 0 }
        return root.leafCount
    }

    public var allLeaves: [TerminalID] {
        guard let root else { return [] }
        return root.allLeaves
    }

    // MARK: - Mutations (return new trees)

    public func inserting(_ newLeaf: TerminalID, at target: TerminalID, direction: SplitDirection) -> SplitTree {
        guard let root else { return self }
        return SplitTree(root: root.inserting(newLeaf, at: target, direction: direction))
    }

    /// Like `inserting`, but the new leaf becomes the *left/top* child rather
    /// than the *right/bottom*. Used by "Split Left" / "Split Up" from the
    /// context menu — same split, opposite placement.
    public func insertingBefore(_ newLeaf: TerminalID, at target: TerminalID, direction: SplitDirection) -> SplitTree {
        guard let root else { return self }
        return SplitTree(root: root.insertingBefore(newLeaf, at: target, direction: direction))
    }

    public func removing(_ target: TerminalID) -> SplitTree {
        guard let root else { return self }
        return SplitTree(root: root.removing(target))
    }

    public func updatingRatio(for target: TerminalID, ratio: Double) -> SplitTree {
        guard let root else { return self }
        return SplitTree(root: root.updatingRatio(for: target, ratio: ratio))
    }
}

extension SplitTree.Node {
    var leafCount: Int {
        switch self {
        case .leaf:
            return 1
        case .split(let s):
            return s.left.leafCount + s.right.leafCount
        }
    }

    var allLeaves: [TerminalID] {
        switch self {
        case .leaf(let id):
            return [id]
        case .split(let s):
            return s.left.allLeaves + s.right.allLeaves
        }
    }

    func inserting(_ newLeaf: TerminalID, at target: TerminalID, direction: SplitDirection) -> SplitTree.Node {
        switch self {
        case .leaf(let id):
            if id == target {
                return .split(.init(
                    direction: direction,
                    ratio: 0.5,
                    left: .leaf(id),
                    right: .leaf(newLeaf)
                ))
            }
            return self
        case .split(let s):
            return .split(.init(
                direction: s.direction,
                ratio: s.ratio,
                left: s.left.inserting(newLeaf, at: target, direction: direction),
                right: s.right.inserting(newLeaf, at: target, direction: direction)
            ))
        }
    }

    func insertingBefore(_ newLeaf: TerminalID, at target: TerminalID, direction: SplitDirection) -> SplitTree.Node {
        switch self {
        case .leaf(let id):
            if id == target {
                return .split(.init(
                    direction: direction,
                    ratio: 0.5,
                    left: .leaf(newLeaf),
                    right: .leaf(id)
                ))
            }
            return self
        case .split(let s):
            return .split(.init(
                direction: s.direction,
                ratio: s.ratio,
                left: s.left.insertingBefore(newLeaf, at: target, direction: direction),
                right: s.right.insertingBefore(newLeaf, at: target, direction: direction)
            ))
        }
    }

    func removing(_ target: TerminalID) -> SplitTree.Node? {
        switch self {
        case .leaf(let id):
            return id == target ? nil : self
        case .split(let s):
            let newLeft = s.left.removing(target)
            let newRight = s.right.removing(target)
            if newLeft == nil { return newRight }
            if newRight == nil { return newLeft }
            return .split(.init(
                direction: s.direction,
                ratio: s.ratio,
                left: newLeft!,
                right: newRight!
            ))
        }
    }

    func updatingRatio(for target: TerminalID, ratio: Double) -> SplitTree.Node {
        switch self {
        case .leaf:
            return self
        case .split(let s):
            if case .leaf(let leftID) = s.left, leftID == target {
                return .split(s.withRatio(ratio))
            }
            return .split(.init(
                direction: s.direction,
                ratio: s.ratio,
                left: s.left.updatingRatio(for: target, ratio: ratio),
                right: s.right.updatingRatio(for: target, ratio: ratio)
            ))
        }
    }
}
