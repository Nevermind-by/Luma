import Combine
import Foundation
import WebKit

@MainActor
final class AppsTorrentBrowserSession: NSObject, ObservableObject {
    enum State: Equatable {
        case idle
        case loading(URL)
        case ready(URL)
        case failed(String)
    }

    @Published private(set) var state: State = .idle

    let webView: WKWebView
    private var continuation: CheckedContinuation<String, Error>?
    private var loadedURL: URL?

    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        self.webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.navigationDelegate = self
    }

    func load(_ url: URL) {
        loadedURL = url
        state = .loading(url)
        webView.load(URLRequest(url: url))
    }

    func captureHTML() async throws -> String {
        guard loadedURL != nil else {
            throw BrowserError.pageNotLoaded
        }

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            webView.evaluateJavaScript("document.documentElement.outerHTML") { [weak self] value, error in
                guard let self else { return }

                if let error {
                    self.resume(with: .failure(error))
                    return
                }

                guard let html = value as? String else {
                    self.resume(with: .failure(BrowserError.invalidHTML))
                    return
                }

                self.resume(with: .success(html))
            }
        }
    }

    private func resume(with result: Result<String, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(with: result)
    }

    enum BrowserError: Error, LocalizedError, Equatable {
        case pageNotLoaded
        case invalidHTML

        var errorDescription: String? {
            switch self {
            case .pageNotLoaded:
                return "The AppsTorrent page is not loaded yet."
            case .invalidHTML:
                return "The browser did not return page HTML."
            }
        }
    }
}

extension AppsTorrentBrowserSession: WKNavigationDelegate {
    nonisolated func webView(
        _ webView: WKWebView,
        didFinish navigation: WKNavigation!
    ) {
        Task { @MainActor [weak self] in
            guard let self, let url = webView.url else { return }
            self.loadedURL = url
            self.state = .ready(url)
        }
    }

    nonisolated func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: Error
    ) {
        Task { @MainActor [weak self] in
            self?.state = .failed(error.localizedDescription)
        }
    }

    nonisolated func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        Task { @MainActor [weak self] in
            self?.state = .failed(error.localizedDescription)
        }
    }
}
