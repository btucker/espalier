import Foundation

public enum WorktreeState: String, Codable, Sendable {
    case closed
    case running
    case stale
}

public struct WorktreeEntry: Codable, Sendable, Identifiable, Equatable {
    public let id: UUID
    public let path: String
    public var branch: String
    public var state: WorktreeState
    public var attention: Attention?
    public var splitTree: SplitTree
    public var focusedTerminalID: TerminalID?

    public init(
        path: String,
        branch: String,
        state: WorktreeState = .closed,
        attention: Attention? = nil,
        splitTree: SplitTree = SplitTree(root: nil)
    ) {
        self.id = UUID()
        self.path = path
        self.branch = branch
        self.state = state
        self.attention = attention
        self.splitTree = splitTree
        self.focusedTerminalID = nil
    }
}
