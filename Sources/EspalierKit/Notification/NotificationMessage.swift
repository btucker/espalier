import Foundation

public enum NotificationMessage: Sendable {
    case notify(path: String, text: String, clearAfter: TimeInterval? = nil)
    case clear(path: String)
}

extension NotificationMessage: Codable {
    private enum CodingKeys: String, CodingKey {
        case type, path, text, clearAfter
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .notify(let path, let text, let clearAfter):
            try container.encode("notify", forKey: .type)
            try container.encode(path, forKey: .path)
            try container.encode(text, forKey: .text)
            try container.encodeIfPresent(clearAfter, forKey: .clearAfter)
        case .clear(let path):
            try container.encode("clear", forKey: .type)
            try container.encode(path, forKey: .path)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "notify":
            let path = try container.decode(String.self, forKey: .path)
            let text = try container.decode(String.self, forKey: .text)
            let clearAfter = try container.decodeIfPresent(TimeInterval.self, forKey: .clearAfter)
            self = .notify(path: path, text: text, clearAfter: clearAfter)
        case "clear":
            let path = try container.decode(String.self, forKey: .path)
            self = .clear(path: path)
        default:
            throw DecodingError.dataCorrupted(.init(codingPath: [CodingKeys.type], debugDescription: "Unknown message type: \(type)"))
        }
    }
}
