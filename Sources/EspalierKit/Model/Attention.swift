import Foundation

public struct Attention: Codable, Sendable, Equatable {
    public let text: String
    public let timestamp: Date
    public let clearAfter: TimeInterval?

    public init(text: String, timestamp: Date, clearAfter: TimeInterval? = nil) {
        self.text = text
        self.timestamp = timestamp
        self.clearAfter = clearAfter
    }
}
