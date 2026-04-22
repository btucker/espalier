import Testing
import Foundation
import NIOSSL
@testable import GrafttyKit

@Suite("WebTLSContextProvider")
struct WebTLSContextProviderTests {

    private func loadContext() throws -> NIOSSLContext {
        let certURL = try #require(
            Bundle.module.url(forResource: "test-tls-cert", withExtension: "pem",
                              subdirectory: "Fixtures")
        )
        let keyURL = try #require(
            Bundle.module.url(forResource: "test-tls-key", withExtension: "pem",
                              subdirectory: "Fixtures")
        )
        let cert = try NIOSSLCertificate.fromPEMFile(certURL.path)
        let key = try NIOSSLPrivateKey(file: keyURL.path, format: .pem)
        var cfg = TLSConfiguration.makeServerConfiguration(
            certificateChain: cert.map { .certificate($0) },
            privateKey: .privateKey(key)
        )
        cfg.minimumTLSVersion = .tlsv12
        return try NIOSSLContext(configuration: cfg)
    }

    @Test func currentReturnsInitialContext() throws {
        let ctx = try loadContext()
        let provider = WebTLSContextProvider(initial: ctx)
        #expect(provider.current() === ctx)
    }

    @Test func swapReplacesContext() throws {
        let a = try loadContext()
        let b = try loadContext()
        let provider = WebTLSContextProvider(initial: a)
        provider.swap(b)
        #expect(provider.current() === b)
    }

    @Test func concurrentReadsDoNotCrash() async throws {
        let ctx = try loadContext()
        let provider = WebTLSContextProvider(initial: ctx)
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<100 {
                group.addTask { _ = provider.current() }
            }
        }
    }
}
