import Foundation

/// Image bytes travel on the control carrier, never through the PTY.
/// A chunk's base64 JSON remains below both transports' frame limits.
public enum ImagePasteMessage: Codable, Equatable, Sendable {
    // NIO's WebSocket upgrader accepts 16 KiB frames. Four KiB also
    // fits when every base64 slash is JSON-escaped.
    public static let chunkSize = 4 * 1024
    public static let maxImageBytes = 10 * 1024 * 1024

    case available
    case begin(id: UUID, byteCount: Int)
    case chunk(id: UUID, offset: Int, data: Data)
    case commit(id: UUID)
    case cancel(id: UUID)
    case result(id: UUID, error: String?)
}

/// One bounded upload per terminal attachment. The caller serializes access
/// and discards this state when the attachment closes or loses ownership.
public struct ImagePasteUpload {
    private var id: UUID?
    private var byteCount = 0
    private var data = Data()

    public enum UploadError: Error { case invalidUpload }
    public init() {}

    public mutating func begin(id: UUID, byteCount: Int) throws {
        guard byteCount > 0, byteCount <= ImagePasteMessage.maxImageBytes else {
            throw UploadError.invalidUpload
        }
        self.id = id
        self.byteCount = byteCount
        data = Data()
    }

    public mutating func append(id: UUID, offset: Int, data chunk: Data) throws {
        guard self.id == id, offset == data.count, !chunk.isEmpty,
              chunk.count <= ImagePasteMessage.chunkSize,
              chunk.count <= byteCount - data.count else {
            throw UploadError.invalidUpload
        }
        data.append(chunk)
    }

    public mutating func finish(id: UUID) throws -> Data {
        guard self.id == id, data.count == byteCount else { throw UploadError.invalidUpload }
        let result = data
        self = .init()
        return result
    }

    public mutating func cancel(id: UUID) {
        if self.id == id { self = .init() }
    }
}
