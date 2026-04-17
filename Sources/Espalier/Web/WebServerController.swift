import Foundation
import EspalierKit
import Combine

/// Owns the `WebServer` lifetime at app scope. Subscribes to
/// `WebAccessSettings` and starts/stops the server accordingly.
@MainActor
final class WebServerController: ObservableObject {

    @Published var status: WebServer.Status = .stopped
    @Published var currentURL: String? = nil

    private var server: WebServer?
    private let settings: WebAccessSettings
    private let zmxExecutable: URL
    private let zmxDir: URL
    private var cancellables = Set<AnyCancellable>()

    init(settings: WebAccessSettings, zmxExecutable: URL, zmxDir: URL) {
        self.settings = settings
        self.zmxExecutable = zmxExecutable
        self.zmxDir = zmxDir
        reconcile()
        settings.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        self?.reconcile()
                    }
                }
            }
            .store(in: &cancellables)
    }

    func stop() {
        server?.stop()
        server = nil
        status = .stopped
    }

    private func reconcile() {
        server?.stop()
        server = nil
        status = .stopped
        guard settings.isEnabled else { return }
        do {
            let api = try TailscaleLocalAPI.autoDetected()
            let tailscaleStatus = try runBlocking { try await api.status() }
            var bind = tailscaleStatus.tailscaleIPs
            bind.append("127.0.0.1")
            var assets: [String: WebStaticResources.Asset] = [:]
            for p in ["/", "/xterm.min.js", "/xterm.min.css", "/xterm-addon-fit.min.js"] {
                assets[p] = try WebStaticResources.asset(for: p)
            }
            let ownerLogin = tailscaleStatus.loginName
            let auth = WebServer.AuthPolicy { peerIP in
                guard let api = try? TailscaleLocalAPI.autoDetected() else { return false }
                guard let whois = try? await api.whois(peerIP: peerIP) else { return false }
                return whois.loginName == ownerLogin
            }
            let s = WebServer(
                config: .init(port: settings.port, allowedPaths: assets,
                              zmxExecutable: zmxExecutable, zmxDir: zmxDir),
                auth: auth,
                bindAddresses: bind
            )
            try s.start()
            server = s
            status = s.status
            if let host = WebURLComposer.chooseHost(from: tailscaleStatus.tailscaleIPs) {
                currentURL = "http://\(host):\(settings.port)/"
            } else {
                currentURL = nil
            }
        } catch TailscaleLocalAPI.Error.socketUnreachable {
            status = .disabledNoTailscale
        } catch {
            status = .error("\(error)")
        }
    }

    /// Bridge async to sync for the one-shot status() at reconcile time.
    private func runBlocking<T>(_ op: @escaping @Sendable () async throws -> T) throws -> T where T: Sendable {
        let sem = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var result: Result<T, Swift.Error> = .failure(CancellationError())
        Task.detached {
            do { result = .success(try await op()) }
            catch { result = .failure(error) }
            sem.signal()
        }
        sem.wait()
        return try result.get()
    }
}
