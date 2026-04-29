#if canImport(UIKit)
import CryptoKit
import Foundation

public struct SSHHostKeyFingerprint: Codable, Hashable, Sendable, CustomStringConvertible {
    public let value: String

    public var description: String { value }

    public init(rawSHA256Base64: String) {
        self.value = rawSHA256Base64.hasPrefix("SHA256:")
            ? rawSHA256Base64
            : "SHA256:\(rawSHA256Base64)"
    }

    public init(openSSHPublicKey: String) throws {
        let parts = openSSHPublicKey.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
        guard parts.count >= 2, let blob = Data(base64Encoded: String(parts[1])) else {
            throw SSHHostKeyPinStoreError.invalidOpenSSHPublicKey
        }
        self.init(publicKeyBlob: blob)
    }

    public init(publicKeyBlob: Data) {
        let digest = SHA256.hash(data: publicKeyBlob)
        let base64 = Data(digest).base64EncodedString().trimmingCharacters(in: CharacterSet(charactersIn: "="))
        self.value = "SHA256:\(base64)"
    }
}

public struct SSHHostKeyPinTarget: Codable, Hashable, Sendable {
    public let host: String
    public let port: Int

    public init(host: String, port: Int) {
        self.host = host.lowercased()
        self.port = port
    }
}

public enum SSHHostKeyTrustState: Equatable, Sendable {
    case trusted
    case unknown(fingerprint: SSHHostKeyFingerprint)
    case changed(expected: SSHHostKeyFingerprint, actual: SSHHostKeyFingerprint)
}

public enum SSHHostKeyPinStoreError: Error, Equatable {
    case invalidOpenSSHPublicKey
    case io(String)
}

public protocol SSHHostKeyPinStoring: Sendable {
    func trustState(for target: SSHHostKeyPinTarget, fingerprint: SSHHostKeyFingerprint) throws -> SSHHostKeyTrustState
    func trust(_ fingerprint: SSHHostKeyFingerprint, for target: SSHHostKeyPinTarget) throws
}

public final class InMemorySSHHostKeyPinStore: SSHHostKeyPinStoring, @unchecked Sendable {
    private var pins: [SSHHostKeyPinTarget: SSHHostKeyFingerprint]

    public init(pins: [SSHHostKeyPinTarget: SSHHostKeyFingerprint] = [:]) {
        self.pins = pins
    }

    public func trustState(
        for target: SSHHostKeyPinTarget,
        fingerprint: SSHHostKeyFingerprint
    ) -> SSHHostKeyTrustState {
        guard let expected = pins[target] else {
            return .unknown(fingerprint: fingerprint)
        }
        return expected == fingerprint ? .trusted : .changed(expected: expected, actual: fingerprint)
    }

    public func trust(_ fingerprint: SSHHostKeyFingerprint, for target: SSHHostKeyPinTarget) {
        pins[target] = fingerprint
    }
}

public final class FileSSHHostKeyPinStore: SSHHostKeyPinStoring, @unchecked Sendable {
    private let storeURL: URL

    public init(storeURL: URL = FileSSHHostKeyPinStore.defaultStoreURL()) {
        self.storeURL = storeURL
    }

    public static func defaultStoreURL() -> URL {
        let fm = FileManager.default
        let base = (try? fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? fm.temporaryDirectory
        let dir = base.appendingPathComponent(
            Bundle.main.bundleIdentifier ?? "net.graftty.GrafttyMobile",
            isDirectory: true
        )
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("ssh-host-key-pins.json")
    }

    public func trustState(
        for target: SSHHostKeyPinTarget,
        fingerprint: SSHHostKeyFingerprint
    ) throws -> SSHHostKeyTrustState {
        let pins = try readPins()
        guard let expected = pins[target] else {
            return .unknown(fingerprint: fingerprint)
        }
        return expected == fingerprint ? .trusted : .changed(expected: expected, actual: fingerprint)
    }

    public func trust(_ fingerprint: SSHHostKeyFingerprint, for target: SSHHostKeyPinTarget) throws {
        var pins = try readPins()
        pins[target] = fingerprint
        try writePins(pins)
    }

    private func readPins() throws -> [SSHHostKeyPinTarget: SSHHostKeyFingerprint] {
        guard FileManager.default.fileExists(atPath: storeURL.path) else { return [:] }
        do {
            let data = try Data(contentsOf: storeURL)
            return try JSONDecoder().decode([SSHHostKeyPinTarget: SSHHostKeyFingerprint].self, from: data)
        } catch {
            throw SSHHostKeyPinStoreError.io("\(error)")
        }
    }

    private func writePins(_ pins: [SSHHostKeyPinTarget: SSHHostKeyFingerprint]) throws {
        do {
            let data = try JSONEncoder().encode(pins)
            try data.write(to: storeURL, options: [.atomic])
        } catch {
            throw SSHHostKeyPinStoreError.io("\(error)")
        }
    }
}
#endif
