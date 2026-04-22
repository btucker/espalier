import Foundation
import NIOSSL

/// Turns PEM bytes (cert chain + key) into an `NIOSSLContext` suitable
/// for `WebServer`'s child-channel initializer. Factored out of
/// `WebServerController` so the integration-test path can stub the
/// NIOSSL construction step without standing up Tailscale LocalAPI.
/// WEB-8.2.
public enum WebTLSCertFetcher {

    /// Build an `NIOSSLContext` from a concatenated cert-chain PEM and
    /// a separate private-key PEM. Matches what
    /// `TailscaleLocalAPI.parseCertPair` produces.
    public static func buildContext(certPEM: Data, keyPEM: Data) throws -> NIOSSLContext {
        let certs = try NIOSSLCertificate.fromPEMBytes(Array(certPEM))
        let key = try NIOSSLPrivateKey(bytes: Array(keyPEM), format: .pem)
        var cfg = TLSConfiguration.makeServerConfiguration(
            certificateChain: certs.map { .certificate($0) },
            privateKey: .privateKey(key)
        )
        cfg.minimumTLSVersion = .tlsv12
        return try NIOSSLContext(configuration: cfg)
    }
}
