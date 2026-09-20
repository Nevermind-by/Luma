import SwiftUI
import WebKit

struct AppsTorrentBrowserView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var session: AppsTorrentBrowserSession
    @State private var selectedPage: Int

    let url: URL
    let onComplete: () -> Void

    private let exampleURL = URL(string: "https://example.com")!
    private let appsTorrentURL = URL(string: "https://appstorrent.ru")!

    @MainActor
    init(
        url: URL,
        session: AppsTorrentBrowserSession,
        onComplete: @escaping () -> Void = {}
    ) {
        self.url = url
        self._session = ObservedObject(wrappedValue: session)
        self._selectedPage = State(initialValue: url == appsTorrentURL ? 1 : 0)
        self.onComplete = onComplete
    }

    private var currentURL: URL {
        selectedPage == 0 ? exampleURL : appsTorrentURL
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Label("AppsTorrent", systemImage: "person.crop.circle")
                    .font(.headline)

                Picker("Page", selection: testPageBinding) {
                    Text("AppsTorrent").tag(1)
                    Text("Example.com").tag(0)
                }
                .pickerStyle(.segmented)
                .frame(width: 220)

                Spacer()

                statusView

                Button {
                    session.reload()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Reload current page")
                .accessibilityIdentifier("reload-browser-button")

                Button("Continue") {
                    onComplete()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal)
            .padding(.vertical, 10)

            Divider()

            BrowserWebView(webView: session.webView)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack {
                Image(systemName: "lock.shield")
                    .foregroundStyle(.secondary)
                Text("Sign in directly on AppsTorrent. Luma does not store your password.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .frame(minWidth: 900, minHeight: 650)
        .onAppear {
            session.load(currentURL)
        }
    }

    private var testPageBinding: Binding<Int> {
        Binding(
            get: { selectedPage },
            set: { selection in
                selectedPage = selection
                session.load(selection == 0 ? exampleURL : appsTorrentURL)
            }
        )
    }

    @ViewBuilder
    private var statusView: some View {
        switch session.state {
        case .idle:
            Text("Idle")
                .foregroundStyle(.secondary)

        case .loading(let loadedURL):
            hostStatusLabel(
                loadedURL,
                fallback: "Loading…",
                systemImage: "arrow.triangle.2.circlepath"
            )

        case .ready(let loadedURL):
            hostStatusLabel(
                loadedURL,
                fallback: "Ready",
                systemImage: "checkmark.circle.fill"
            )

        case .downloading(let downloadURL):
            hostStatusLabel(
                downloadURL,
                fallback: "Downloading…",
                systemImage: "arrow.down.circle"
            )

        case .failed(let message):
            Label("Navigation failed", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .help(message)

        case .processTerminated:
            Label("Web process crashed", systemImage: "xmark.octagon.fill")
                .foregroundStyle(.red)
                .help("The WebContent process terminated. Reload the page or try again.")
        }
    }

    private func hostStatusLabel(
        _ url: URL,
        fallback: LocalizedStringKey,
        systemImage: String
    ) -> some View {
        if let host = url.host {
            return AnyView(Label(host, systemImage: systemImage).foregroundStyle(.secondary))
        }

        return AnyView(Label(fallback, systemImage: systemImage).foregroundStyle(.secondary))
    }
}

private struct BrowserWebView: NSViewRepresentable {
    let webView: WKWebView

    func makeNSView(context: Context) -> WKWebView {
        webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

#Preview {
    AppsTorrentBrowserView(
        url: URL(string: "https://appstorrent.ru")!,
        session: AppsTorrentBrowserSession.shared
    )
}
