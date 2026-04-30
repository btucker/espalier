import Foundation

public enum MacHostKind: String, Codable, Sendable, Equatable {
    case local
    case ssh
}

public struct SSHHostConfig: Codable, Sendable, Equatable {
    public var sshHost: String
    public var sshUsername: String?
    public var sshPort: Int
    public var remoteGrafttyPort: Int

    public init(
        sshHost: String,
        sshUsername: String? = nil,
        sshPort: Int = 22,
        remoteGrafttyPort: Int = 8799
    ) {
        self.sshHost = sshHost
        self.sshUsername = sshUsername
        self.sshPort = sshPort
        self.remoteGrafttyPort = remoteGrafttyPort
    }
}

public struct MacHost: Codable, Identifiable, Sendable, Equatable {
    public static let localID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    public static let local = MacHost(
        id: localID,
        kind: .local,
        label: "This Mac",
        sshConfig: nil,
        addedAt: Date(timeIntervalSince1970: 0)
    )

    public var id: UUID
    public var kind: MacHostKind
    public var label: String
    public var sshConfig: SSHHostConfig?
    public var addedAt: Date

    public init(
        id: UUID = UUID(),
        kind: MacHostKind,
        label: String,
        sshConfig: SSHHostConfig? = nil,
        addedAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.label = label
        self.sshConfig = sshConfig
        self.addedAt = addedAt
    }

    public static func ssh(
        id: UUID = UUID(),
        label: String? = nil,
        sshHost: String,
        username: String?,
        sshPort: Int = 22,
        remoteGrafttyPort: Int = 8799,
        addedAt: Date = Date()
    ) -> MacHost {
        let trimmedHost = sshHost.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedLabel = label?.trimmingCharacters(in: .whitespacesAndNewlines)
        return MacHost(
            id: id,
            kind: .ssh,
            label: trimmedLabel?.nilIfEmpty ?? trimmedHost,
            sshConfig: SSHHostConfig(
                sshHost: trimmedHost,
                sshUsername: username?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                sshPort: sshPort,
                remoteGrafttyPort: remoteGrafttyPort
            ),
            addedAt: addedAt
        )
    }
}

public struct AddHostFormModel: Sendable, Equatable {
    public var label: String
    public var host: String
    public var username: String
    public var sshPort: Int
    public var remoteGrafttyPort: Int

    public init(
        label: String = "",
        host: String = "",
        username: String = "",
        sshPort: Int = 22,
        remoteGrafttyPort: Int = 8799
    ) {
        self.label = label
        self.host = host
        self.username = username
        self.sshPort = sshPort
        self.remoteGrafttyPort = remoteGrafttyPort
    }

    public func makeHost() -> MacHost? {
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedHost.isEmpty, sshPort > 0, remoteGrafttyPort > 0 else { return nil }

        return MacHost.ssh(
            label: label,
            sshHost: trimmedHost,
            username: username,
            sshPort: sshPort,
            remoteGrafttyPort: remoteGrafttyPort
        )
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
