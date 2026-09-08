import Foundation
import Testing
@testable import GrafttyProtocol

struct ImagePasteTests {
    @Test("""
    @spec IOS-11.15: When a clipboard image is transferred, the application shall carry bounded image chunks separately from PTY bytes and require a complete, ordered upload before committing the paste.
    """)
    func transferRoundTrip() throws {
        let id = UUID()
        let bytes = Data(repeating: 0xff, count: ImagePasteMessage.chunkSize + 7)
        var upload = ImagePasteUpload()
        try upload.begin(id: id, byteCount: bytes.count)
        for offset in stride(from: 0, to: bytes.count, by: ImagePasteMessage.chunkSize) {
            let chunk = bytes.subdata(in: offset..<min(offset + ImagePasteMessage.chunkSize, bytes.count))
            let envelope = WebControlEnvelope.imagePaste(.chunk(id: id, offset: offset, data: chunk))
            let wire = envelope.encoded()
            #expect(wire.utf8.count < 16 * 1024)
            #expect(wire.utf8.count < StdErrControlFraming.maxFrameLength)
            #expect(try WebControlEnvelope.parse(Data(wire.utf8)) == envelope)
            try upload.append(id: id, offset: offset, data: chunk)
        }
        #expect(try upload.finish(id: id) == bytes)
        #expect(throws: (any Error).self) { try upload.finish(id: id) }
    }

    @Test(arguments: ["null", "true", "42", "\"invalid\"", "[]"])
    func malformedImageMessageIsRejected(_ message: String) {
        let wire = "{\"type\":\"imagePaste\",\"message\":\(message)}"
        #expect(throws: (any Error).self) {
            try WebControlEnvelope.parse(Data(wire.utf8))
        }
    }

    @Test("""
    @spec IOS-11.16: If an image upload is oversized, incomplete, out of order, or belongs to another request, then the application shall reject it without pasting.
    """)
    func rejectsInvalidTransfers() throws {
        let id = UUID()
        var upload = ImagePasteUpload()
        #expect(throws: (any Error).self) { try upload.begin(id: id, byteCount: ImagePasteMessage.maxImageBytes + 1) }
        #expect(throws: (any Error).self) { try upload.begin(id: id, byteCount: 0) }
        try upload.begin(id: id, byteCount: 2)
        #expect(throws: (any Error).self) { try upload.append(id: UUID(), offset: 0, data: Data([1])) }
        #expect(throws: (any Error).self) { try upload.append(id: id, offset: 1, data: Data([1])) }
        #expect(throws: (any Error).self) { try upload.append(id: id, offset: 0, data: Data([1, 2, 3])) }
        try upload.append(id: id, offset: 0, data: Data([1]))
        #expect(throws: (any Error).self) { try upload.finish(id: id) }
    }
}
