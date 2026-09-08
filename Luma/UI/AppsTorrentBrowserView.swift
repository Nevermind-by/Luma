import SwiftUI
import WebKit

struct AppsTorrentBrowserView: View {
    @StateObject private var session = AppsTorrentBrowserSession()
    @Environment(\.dismiss) private var dismiss

    let url: URL

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("AppsTorrent", systemImage: "safari")
                    .font(.headline)

                Spacer()

                Button("Close") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal)
            .padding(.vertical, 10)

            Divider()

            WebViewContainer(webView: session.webView)
        }
        .frame(minWidth: 900, minHeight: 650)
        .task {
            session.load(url)
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
