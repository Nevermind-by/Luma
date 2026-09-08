import SwiftUI
import WebKit

struct AppsTorrentBrowserView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var session: AppsTorrentBrowserSession
    @State private var selectedPage: Int

    let url: URL

    private let exampleURL = URL(string: "https://example.com")!
    private let appsTorrentURL = URL(string: "https://appstorrent.ru")!

    init(
        url: URL,
        session: AppsTorrentBrowserSession = .shared
    ) {
        self.url = url
        self._session = ObservedObject(wrappedValue: session)
        self._selectedPage = State(initialValue: url == appsTorrentURL ? 1 : 0)
    }

    private var currentURL: URL {
        selectedPage == 0 ? exampleURL : appsTorrentURL
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Label("WebKit Diagnostic", systemImage: "safari")
                    .font(.headline)

                Picker("Test Page", selection: testPageBinding) {
                    Text("Example.com").tag(0)
                    Text("AppsTorrent").tag(1)
                }
                .pickerStyle(.segmented)
                .frame(width: 260)

                Spacer()

                statusView

                Button {
                    session.reload()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Reload current page")

                Button("Close") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal)
            .padding(.vertical, 10)

            Divider()

            BrowserWebView(webView: session.webView)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            Label(loadedURL.host ?? "Loading…", systemImage: "arrow.triangle.2.circlepath")
                .foregroundStyle(.secondary)

        case .ready(let loadedURL):
            Label(loadedURL.host ?? "Ready", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.secondary)

        case .failed(let message):
            Label("Navigation failed", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .help(message)

        case .processTerminated:
            Label("Web process crashed", systemImage: "xmark.octagon.fill")
                .foregroundStyle(.red)
                .help("The WebContent process terminated. Reload the page or try another test page.")
        }
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
        url: URL(string: "https://appstorrent.ru")!
    )
}
