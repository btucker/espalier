import Foundation

@MainActor
enum TerminalLinkResolver {
    private static let detector = try? NSDataDetector(
        types: NSTextCheckingResult.CheckingType.link.rawValue
    )

    static func webURL(_ value: String?) -> URL? {
        guard let value, let url = URL(string: value),
              let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              let host = url.host, !host.isEmpty else { return nil }
        return url
    }

    /// The terminal supplies the pressed word's UTF-16 range. Match that
    /// range against complete URLs so punctuation and query strings survive,
    /// and repeated words in other links do not select the wrong destination.
    static func url(in text: String, anchorRange: NSRange?) -> URL? {
        let count = text.utf16.count
        guard let anchorRange,
              anchorRange.location != NSNotFound,
              anchorRange.location >= 0, anchorRange.location <= count,
              anchorRange.length > 0,
              anchorRange.length <= count - anchorRange.location else { return nil }
        let matches = detector?.matches(
            in: text, range: NSRange(location: 0, length: count)
        ) ?? []
        return matches.first {
            NSIntersectionRange($0.range, anchorRange).length > 0
        }.flatMap { webURL($0.url?.absoluteString) }
    }
}
