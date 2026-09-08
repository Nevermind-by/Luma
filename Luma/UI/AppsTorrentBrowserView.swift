import SwiftUI
import WebKit

struct AppsTorrentBrowserView: View {
    @StateObject private var session = AppsTorrentBrowserSession()
    @Environment(\.dismiss) private var dismiss

    let url: URL

    private let exampleURL = URL(string: "https://example.com")!
    private let appsTorrentURL = URL(string: "https://appstorrent.ru")!

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Label("WebKit Diagnostic", systemImage: "safari")
                    .font(.headline)

                Picker("Test Page", selection: testPageSelection) {
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
                .help("Reload current test page")

                Button("Close") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal)
            .padding(.vertical, 10)

            Divider()

            WebViewContainer(webView: session.webView)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 900, minHeight: 650)
        .task {
            session.load(url)
        }
    }

    private var testPageSelection: Binding<Int> {
        Binding(
            get: {
                currentURL == exampleURL ? 0 : 1
            },
            set: { selection in
                session.load(selection == 0 ? exampleURL : appsTorrentURL)
            }
        )
    }

    private var currentURL: URL {
        switch session.state {
        case .idle:
            return url
        case .loading(let loadedURL), .ready(let loadedURL):
            return loadedURL
        case .failed, .processTerminated:
            return url
        }
    }

    @ViewBuilder
    private var statusView: some View {
        switch session.state {
        case .idle:
            Text("Idle")
                .foregroundStyle(.secondary)

        case .loading:
            Label("Loading…", systemImage: "arrow.triangle.2.circlepath")
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
                .help("WKWebView's WebContent process terminated. Reload the page or switch to another test page.")
        }
    }
}

private struct WebViewContainer: NSViewRepresentable {
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
