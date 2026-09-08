import SwiftUI
import WebKit

struct AppsTorrentBrowserView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedPage = 0
    @State private var reloadID = UUID()

    let url: URL

    private let exampleURL = URL(string: "https://example.com")!
    private let appsTorrentURL = URL(string: "https://appstorrent.ru")!

    private var currentURL: URL {
        selectedPage == 0 ? exampleURL : appsTorrentURL
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Label("WebKit Diagnostic", systemImage: "safari")
                    .font(.headline)

                Picker("Test Page", selection: $selectedPage) {
                    Text("Example.com").tag(0)
                    Text("AppsTorrent").tag(1)
                }
                .pickerStyle(.segmented)
                .frame(width: 260)

                Spacer()

                Text(currentURL.host ?? "Web")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button {
                    reloadID = UUID()
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

            WebView(url: currentURL)
                .id(reloadID)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 900, minHeight: 650)
        .onAppear {
            selectedPage = url == appsTorrentURL ? 1 : 0
        }
    }
}

private struct WebView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            webView.reload()
        }
    }
}

#Preview {
    AppsTorrentBrowserView(
        url: URL(string: "https://appstorrent.ru")!
    )
}
