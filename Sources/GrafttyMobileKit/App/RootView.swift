#if canImport(UIKit)
import GhosttyTerminal
import GrafttyProtocol
import SwiftUI

public struct RootView: View {

    @State private var hostStore = HostStore()
    @State private var gate = BiometricGate()
    @State private var navigationPath = NavigationPath()
    @Environment(\.scenePhase) private var scenePhase

    public init() {}

    public var body: some View {
        ZStack {
            NavigationStack(path: $navigationPath) {
                HostPickerView(store: hostStore)
                    .navigationDestination(for: Host.self) { host in
                        WorktreePickerView(host: host) { wt in
                            navigationPath.append(WorktreeStep(host: host, worktree: wt))
                        }
                    }
                    .navigationDestination(for: WorktreeStep.self) { step in
                        WorktreeDetailView(
                            host: step.host,
                            worktree: step.worktree
                        ) { sessionName in
                            navigationPath.append(SessionStep(
                                host: step.host,
                                sessionName: sessionName,
                                title: step.worktree.layout?.title(for: sessionName) ?? sessionName
                            ))
                        }
                    }
                    .navigationDestination(for: SessionStep.self) { step in
                        SingleSessionView(step: step, navigationPath: $navigationPath)
                    }
            }
            if gate.state == .locked {
                lockOverlay
            }
        }
        .task { await gate.authenticate() }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .background:
                gate.applicationDidEnterBackground()
            case .active:
                gate.applicationWillEnterForeground()
                if gate.state == .locked {
                    Task { await gate.authenticate() }
                }
            default:
                break
            }
        }
    }

    private var lockOverlay: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.shield").font(.system(size: 64))
            Text("Graftty is locked").font(.title2)
            Button("Unlock") { Task { await gate.authenticate() } }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
    }

    static func makeWebSocketURL(base: URL, session: String) -> URL {
        var components = URLComponents(url: base, resolvingAgainstBaseURL: false) ?? URLComponents()
        components.scheme = (base.scheme?.lowercased() == "https") ? "wss" : "ws"
        components.path = "/ws"
        components.queryItems = [URLQueryItem(name: "session", value: session)]
        return components.url ?? base
    }
}

/// Second-level nav: picked a worktree, now show its pane tree.
struct WorktreeStep: Hashable {
    let host: Host
    let worktree: WorktreePanes
}

/// Third-level nav: picked a pane, now show its terminal fullscreen.
struct SessionStep: Hashable {
    let host: Host
    let sessionName: String
    let title: String
}

/// Fullscreen terminal view for one session. Owns the WebSocket and
/// InMemoryTerminalSession for its lifetime; both are torn down when
/// the view pops from the stack.
struct SingleSessionView: View {
    let step: SessionStep
    @Binding var navigationPath: NavigationPath

    @State private var client: SessionClient
    @State private var isKeyboardVisible: Bool = false

    init(step: SessionStep, navigationPath: Binding<NavigationPath>) {
        self.step = step
        self._navigationPath = navigationPath
        let wsURL = RootView.makeWebSocketURL(base: step.host.baseURL, session: step.sessionName)
        let ws = URLSessionWebSocketClient(url: wsURL)
        self._client = State(initialValue: SessionClient(sessionName: step.sessionName, webSocket: ws))
    }

    var body: some View {
        TerminalPaneView(session: client.session)
            .ignoresSafeArea(edges: .top)
            .toolbar(.hidden, for: .navigationBar)
            .overlay(alignment: .bottomTrailing) {
                if isKeyboardVisible {
                    Button {
                        UIApplication.shared.sendAction(
                            #selector(UIResponder.resignFirstResponder),
                            to: nil, from: nil, for: nil
                        )
                    } label: {
                        Image(systemName: "keyboard.chevron.compact.down")
                            .font(.title2)
                            .foregroundStyle(.primary)
                            .padding(10)
                            .background(.ultraThinMaterial, in: Circle())
                            .shadow(radius: 1)
                    }
                    .padding(.trailing, 12)
                    .padding(.bottom, 12)
                    .accessibilityLabel("Hide keyboard")
                    .transition(.opacity.combined(with: .scale))
                }
            }
            .animation(.easeInOut(duration: 0.15), value: isKeyboardVisible)
            .onReceive(NotificationCenter.default.publisher(
                for: UIResponder.keyboardWillShowNotification
            )) { _ in isKeyboardVisible = true }
            .onReceive(NotificationCenter.default.publisher(
                for: UIResponder.keyboardWillHideNotification
            )) { _ in isKeyboardVisible = false }
            .task { client.start() }
            .task(id: step.host.id) {
                if let text = await GhosttyConfigFetcher.fetch(baseURL: step.host.baseURL) {
                    TerminalController.shared.updateConfigSource(.generated(text))
                }
            }
            .onDisappear { client.stop() }
    }
}

extension PaneLayoutNode {
    /// Walk the tree to find the title of the leaf whose `sessionName`
    /// matches. Used by SessionStep construction so the terminal view
    /// shows a human title (falls back to session name on miss).
    func title(for sessionName: String) -> String? {
        switch self {
        case let .leaf(name, title):
            return name == sessionName ? title : nil
        case let .split(_, _, left, right):
            return left.title(for: sessionName) ?? right.title(for: sessionName)
        }
    }
}
#endif
