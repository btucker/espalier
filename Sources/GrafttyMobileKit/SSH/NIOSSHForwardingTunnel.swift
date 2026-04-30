#if canImport(UIKit)
import CryptoKit
import Foundation
import NIOCore
import NIOPosix
import NIOSSH

public enum SSHTunnelError: Error, Equatable, Sendable {
    case unknownHostKey(target: SSHHostKeyPinTarget, fingerprint: SSHHostKeyFingerprint)
    case changedHostKey(target: SSHHostKeyPinTarget, expected: SSHHostKeyFingerprint, actual: SSHHostKeyFingerprint)
    case invalidChannelType
    case invalidData
    case authenticationUnavailable
    case localBindMissing
}

public final class NIOSSHForwardingTunnelStarter: SSHTunnelStarting, @unchecked Sendable {
    private let keyStore: MobileSSHKeyStore
    private let pinStore: any SSHHostKeyPinStoring

    public init(
        keyStore: MobileSSHKeyStore = MobileSSHKeyStore(),
        pinStore: any SSHHostKeyPinStoring = FileSSHHostKeyPinStore()
    ) {
        self.keyStore = keyStore
        self.pinStore = pinStore
    }

    public func startTunnel(for config: SSHHostConfig) async throws -> any RunningSSHTunnel {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        do {
            let rawKey = try keyStore.privateKeyRawRepresentation()
            let privateKey = NIOSSHPrivateKey(p256Key: try P256.Signing.PrivateKey(rawRepresentation: rawKey))
            let authDelegate = PrivateKeyAuthDelegate(username: config.sshUsername, privateKey: privateKey)
            let hostKeyDelegate = PinnedHostKeyDelegate(
                target: SSHHostKeyPinTarget(host: config.sshHost, port: config.sshPort),
                pinStore: pinStore
            )

            let sshChannel = try await ClientBootstrap(group: group)
                .channelInitializer { channel in
                    channel.eventLoop.makeCompletedFuture {
                        let handler = NIOSSHHandler(
                            role: .client(.init(
                                userAuthDelegate: authDelegate,
                                serverAuthDelegate: hostKeyDelegate
                            )),
                            allocator: channel.allocator,
                            inboundChildChannelInitializer: nil
                        )
                        try channel.pipeline.syncOperations.addHandler(handler)
                    }
                }
                .channelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
                .channelOption(ChannelOptions.socket(SocketOptionLevel(IPPROTO_TCP), TCP_NODELAY), value: 1)
                .connect(host: config.sshHost, port: config.sshPort)
                .get()

            let serverChannel = try await Self.startLocalForwarder(
                group: group,
                sshChannel: sshChannel,
                config: config
            )
            guard let port = serverChannel.localAddress?.port else {
                throw SSHTunnelError.localBindMissing
            }
            return NIOSSHForwardingTunnel(
                localBaseURL: URL(string: "http://127.0.0.1:\(port)/")!,
                group: group,
                sshChannel: sshChannel,
                serverChannel: serverChannel
            )
        } catch {
            try? await group.shutdownGracefully()
            throw error
        }
    }

    private static func startLocalForwarder(
        group: EventLoopGroup,
        sshChannel: Channel,
        config: SSHHostConfig
    ) async throws -> Channel {
        try await ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { inboundChannel in
                createDirectTCPIPChannel(
                    inboundChannel: inboundChannel,
                    sshChannel: sshChannel,
                    config: config
                )
            }
            .bind(host: "127.0.0.1", port: 0)
            .get()
    }

    private static func createDirectTCPIPChannel(
        inboundChannel: Channel,
        sshChannel: Channel,
        config: SSHHostConfig
    ) -> EventLoopFuture<Void> {
        let sshHandlerFuture = sshChannel.pipeline.handler(type: NIOSSHHandler.self)
        return sshHandlerFuture.flatMap { sshHandler in
            let promise = inboundChannel.eventLoop.makePromise(of: Channel.self)
            let originator: SocketAddress
            do {
                originator = try inboundChannel.remoteAddress
                    ?? SocketAddress(ipAddress: "127.0.0.1", port: 0)
            } catch {
                return inboundChannel.eventLoop.makeFailedFuture(error)
            }

            let directTCPIP = SSHChannelType.DirectTCPIP(
                targetHost: config.remoteGrafttyHost,
                targetPort: config.remoteGrafttyPort,
                originatorAddress: originator
            )

            sshHandler.createChannel(
                promise,
                channelType: .directTCPIP(directTCPIP)
            ) { childChannel, channelType in
                guard case .directTCPIP = channelType else {
                    return childChannel.eventLoop.makeFailedFuture(SSHTunnelError.invalidChannelType)
                }
                return childChannel.eventLoop.makeCompletedFuture {
                    let (sshGlue, inboundGlue) = SSHGlueHandler.matchedPair()

                    let childSync = childChannel.pipeline.syncOperations
                    try childSync.addHandler(SSHChannelDataWrapperHandler())
                    try childSync.addHandler(sshGlue)
                    try childSync.addHandler(SSHForwardingErrorHandler())

                    let inboundSync = inboundChannel.pipeline.syncOperations
                    try inboundSync.addHandler(inboundGlue)
                    try inboundSync.addHandler(SSHForwardingErrorHandler())
                }
            }

            return promise.futureResult.map { _ in }
        }
    }
}

private final class NIOSSHForwardingTunnel: RunningSSHTunnel, @unchecked Sendable {
    let localBaseURL: URL
    private let group: EventLoopGroup
    private let sshChannel: Channel
    private let serverChannel: Channel

    init(localBaseURL: URL, group: EventLoopGroup, sshChannel: Channel, serverChannel: Channel) {
        self.localBaseURL = localBaseURL
        self.group = group
        self.sshChannel = sshChannel
        self.serverChannel = serverChannel
    }

    func close() async {
        _ = try? await serverChannel.close().get()
        _ = try? await sshChannel.close().get()
        try? await group.shutdownGracefully()
    }
}

private final class PrivateKeyAuthDelegate: NIOSSHClientUserAuthenticationDelegate, @unchecked Sendable {
    private let username: String
    private let privateKey: NIOSSHPrivateKey

    init(username: String, privateKey: NIOSSHPrivateKey) {
        self.username = username
        self.privateKey = privateKey
    }

    func nextAuthenticationType(
        availableMethods: NIOSSHAvailableUserAuthenticationMethods,
        nextChallengePromise: EventLoopPromise<NIOSSHUserAuthenticationOffer?>
    ) {
        guard availableMethods.contains(.publicKey) else {
            nextChallengePromise.fail(SSHTunnelError.authenticationUnavailable)
            return
        }
        nextChallengePromise.succeed(NIOSSHUserAuthenticationOffer(
            username: username,
            serviceName: "ssh-connection",
            offer: .privateKey(.init(privateKey: privateKey))
        ))
    }
}

private final class PinnedHostKeyDelegate: NIOSSHClientServerAuthenticationDelegate, @unchecked Sendable {
    private let target: SSHHostKeyPinTarget
    private let pinStore: any SSHHostKeyPinStoring

    init(target: SSHHostKeyPinTarget, pinStore: any SSHHostKeyPinStoring) {
        self.target = target
        self.pinStore = pinStore
    }

    func validateHostKey(hostKey: NIOSSHPublicKey, validationCompletePromise: EventLoopPromise<Void>) {
        do {
            let fingerprint = try SSHHostKeyFingerprint(openSSHPublicKey: String(openSSHPublicKey: hostKey))
            switch try pinStore.trustState(for: target, fingerprint: fingerprint) {
            case .trusted:
                validationCompletePromise.succeed(())
            case .unknown(let fingerprint):
                validationCompletePromise.fail(SSHTunnelError.unknownHostKey(
                    target: target,
                    fingerprint: fingerprint
                ))
            case .changed(let expected, let actual):
                validationCompletePromise.fail(SSHTunnelError.changedHostKey(
                    target: target,
                    expected: expected,
                    actual: actual
                ))
            }
        } catch {
            validationCompletePromise.fail(error)
        }
    }
}

private final class SSHForwardingErrorHandler: ChannelInboundHandler {
    typealias InboundIn = Any

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        context.close(promise: nil)
    }
}

private final class SSHChannelDataWrapperHandler: ChannelDuplexHandler {
    typealias InboundIn = SSHChannelData
    typealias InboundOut = ByteBuffer
    typealias OutboundIn = ByteBuffer
    typealias OutboundOut = SSHChannelData

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let data = unwrapInboundIn(data)
        guard case .channel = data.type, case .byteBuffer(let buffer) = data.data else {
            context.fireErrorCaught(SSHTunnelError.invalidData)
            return
        }
        context.fireChannelRead(wrapInboundOut(buffer))
    }

    func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        let data = unwrapOutboundIn(data)
        context.write(wrapOutboundOut(SSHChannelData(type: .channel, data: .byteBuffer(data))), promise: promise)
    }
}

private final class SSHGlueHandler {
    private var partner: SSHGlueHandler?
    private var context: ChannelHandlerContext?
    private var pendingRead = false

    private init() {}

    static func matchedPair() -> (SSHGlueHandler, SSHGlueHandler) {
        let first = SSHGlueHandler()
        let second = SSHGlueHandler()
        first.partner = second
        second.partner = first
        return (first, second)
    }

    private func partnerWrite(_ data: NIOAny) {
        context?.write(data, promise: nil)
    }

    private func partnerFlush() {
        context?.flush()
    }

    private func partnerWriteEOF() {
        context?.close(mode: .output, promise: nil)
    }

    private func partnerCloseFull() {
        context?.close(promise: nil)
    }

    private func partnerBecameWritable() {
        if pendingRead {
            pendingRead = false
            context?.read()
        }
    }

    private var partnerWritable: Bool {
        context?.channel.isWritable ?? false
    }
}

extension SSHGlueHandler: ChannelDuplexHandler {
    typealias InboundIn = NIOAny
    typealias OutboundIn = NIOAny
    typealias OutboundOut = NIOAny

    func handlerAdded(context: ChannelHandlerContext) {
        self.context = context
        if context.channel.isWritable {
            partner?.partnerBecameWritable()
        }
    }

    func handlerRemoved(context: ChannelHandlerContext) {
        self.context = nil
        self.partner = nil
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        partner?.partnerWrite(data)
    }

    func channelReadComplete(context: ChannelHandlerContext) {
        partner?.partnerFlush()
    }

    func channelInactive(context: ChannelHandlerContext) {
        partner?.partnerCloseFull()
    }

    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        if let event = event as? ChannelEvent, case .inputClosed = event {
            partner?.partnerWriteEOF()
        }
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        partner?.partnerCloseFull()
    }

    func channelWritabilityChanged(context: ChannelHandlerContext) {
        if context.channel.isWritable {
            partner?.partnerBecameWritable()
        }
    }

    func read(context: ChannelHandlerContext) {
        if let partner, partner.partnerWritable {
            context.read()
        } else {
            pendingRead = true
        }
    }
}

private extension EventLoopGroup {
    func shutdownGracefully() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            shutdownGracefully { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }
}
#endif
