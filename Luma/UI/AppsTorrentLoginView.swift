import SwiftUI
import WebKit

struct AppsTorrentLoginView: View {
    @ObservedObject private var session: AppsTorrentBrowserSession
    let onLoginCompleted: () -> Void
    let onLogout: () -> Void

    private let appsTorrentURL = URL(string: "https://appstorrent.ru")!

    @MainActor
    init(
        session: AppsTorrentBrowserSession,
        onLoginCompleted: @escaping () -> Void,
        onLogout: @escaping () -> Void = {}
    ) {
        self._session = ObservedObject(wrappedValue: session)
        self.onLoginCompleted = onLoginCompleted
        self.onLogout = onLogout
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Connect AppsTorrent")
                    .font(.title2.weight(.semibold))

                Text("Log in to AppsTorrent in the browser below. Luma does not read or store your password. The website session is kept by WebKit on this Mac so you can stay signed in between launches.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                HStack {
                    Label(sessionStatusText, systemImage: sessionStatusSymbol)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button("Open AppsTorrent") {
                        session.load(appsTorrentURL)
                    }
                    .controlSize(.small)
                }
            }
            .padding(20)

            Divider()

            LoginBrowserWebView(webView: session.webView)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            HStack {
                Button("Clear Session") {
                    Task {
                        await session.clearAppsTorrentData()
                        session.load(appsTorrentURL)
                        onLogout()
                    }
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)

                Spacer()

                Button("I’m Logged In") {
                    onLoginCompleted()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(minWidth: 980, minHeight: 700)
        .onAppear {
            session.load(appsTorrentURL)
        }
    }

    private var sessionStatusText: String {
        switch session.state {
        case .idle:
            return "Opening AppsTorrent…"
        case .loading(let url):
            return "Loading \(url.host ?? "AppsTorrent")…"
        case .ready:
            return "Browser ready"
        case .failed(let message):
            return message
        case .processTerminated:
            return "Browser process terminated"
        }
    }

    private var sessionStatusSymbol: String {
        switch session.state {
        case .ready:
            return "checkmark.circle"
        case .failed, .processTerminated:
            return "exclamationmark.triangle"
        default:
            return "globe"
        }
    }
}

private struct LoginBrowserWebView: NSViewRepresentable {
    let webView: WKWebView

    func makeNSView(context: Context) -> WKWebView {
        webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

#Preview {
    AppsTorrentLoginView(
        session: AppsTorrentBrowserSession.shared,
        onLoginCompleted: {}
    )
}
