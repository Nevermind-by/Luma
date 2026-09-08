import Combine
import Foundation
import WebKit

@MainActor
final class AppsTorrentBrowserSession: NSObject, ObservableObject {
    static let shared = AppsTorrentBrowserSession()

    enum State: Equatable {
        case idle
        case loading(URL)
        case ready(URL)
        case failed(String)
        case processTerminated
    }

    private struct PendingCapture {
        let url: URL
        let continuation: CheckedContinuation<String, Error>
    }

    @Published private(set) var state: State = .idle

    let webView: WKWebView
    private var pendingCaptures: [PendingCapture] = []
    private var activeCapture: PendingCapture?
    private var activeTimeoutTask: Task<Void, Never>?
    private var loadedURL: URL?
    private let captureTimeoutNanoseconds: UInt64 = 30_000_000_000

    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        self.webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.navigationDelegate = self
    }

    deinit {
        activeTimeoutTask?.cancel()
    }

    func load(_ url: URL) {
        loadedURL = url
        state = .loading(url)
        webView.load(URLRequest(url: url))
    }

    func reload() {
        guard let url = loadedURL else { return }
        state = .loading(url)
        webView.reload()
    }

    func loadAndCaptureHTML(at url: URL) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            pendingCaptures.append(
                PendingCapture(url: url, continuation: continuation)
            )
            processNextCaptureIfNeeded()
        }
    }

    func cookies(for url: URL) async -> [HTTPCookie] {
        await withCheckedContinuation { continuation in
            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
                let host = url.host?.lowercased()
                let matching = cookies.filter { cookie in
                    guard let host else { return false }
                    let domain = cookie.domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
                    return host == domain || host.hasSuffix(".\(domain)")
                }
                continuation.resume(returning: matching)
            }
        }
    }

    func clearAppsTorrentData() async {
        let dataStore = webView.configuration.websiteDataStore
        await withCheckedContinuation { continuation in
            let types = WKWebsiteDataStore.allWebsiteDataTypes()
            dataStore.fetchDataRecords(ofTypes: types) { records in
                let matchingRecords = records.filter { record in
                    let name = record.displayName.lowercased()
                    return name.contains("appstorrent.ru")
                }

                guard !matchingRecords.isEmpty else {
                    continuation.resume()
                    return
                }

                dataStore.removeData(
                    ofTypes: types,
                    for: matchingRecords
                ) {
                    continuation.resume()
                }
            }
        }
    }

    private func processNextCaptureIfNeeded() {
        guard activeCapture == nil, !pendingCaptures.isEmpty else { return }

        let request = pendingCaptures.removeFirst()
        activeCapture = request
        loadedURL = request.url
        state = .loading(request.url)

        activeTimeoutTask?.cancel()
        activeTimeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: self?.captureTimeoutNanoseconds ?? 30_000_000_000)
            guard !Task.isCancelled else { return }

            await MainActor.run {
                self?.finishActiveCapture(with: .failure(BrowserError.timeout))
            }
        }

        webView.load(URLRequest(url: request.url))
    }

    private func finishActiveCapture(with result: Result<String, Error>) {
        guard let activeCapture else { return }
        self.activeCapture = nil
        activeTimeoutTask?.cancel()
        activeTimeoutTask = nil
        activeCapture.continuation.resume(with: result)
        processNextCaptureIfNeeded()
    }

    private func captureCurrentHTML() {
        webView.evaluateJavaScript("document.documentElement.outerHTML") { [weak self] value, error in
            guard let self else { return }

            Task { @MainActor in
                if let error {
                    self.finishActiveCapture(with: .failure(error))
                    return
                }

                guard let html = value as? String else {
                    self.finishActiveCapture(with: .failure(BrowserError.invalidHTML))
                    return
                }

                self.finishActiveCapture(with: .success(html))
            }
        }
    }

    enum BrowserError: Error, LocalizedError, Equatable {
        case pageNotLoaded
        case invalidHTML
        case processTerminated
        case timeout

        var errorDescription: String? {
            switch self {
            case .pageNotLoaded:
                return "The AppsTorrent page is not loaded yet."
            case .invalidHTML:
                return "The browser did not return page HTML."
            case .processTerminated:
                return "The AppsTorrent browser process terminated."
            case .timeout:
                return "The AppsTorrent page did not finish loading within 30 seconds."
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

            if self.activeCapture != nil {
                self.captureCurrentHTML()
            }
        }
    }

    nonisolated func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: Error
    ) {
        Task { @MainActor [weak self] in
            self?.state = .failed(error.localizedDescription)
            self?.finishActiveCapture(with: .failure(error))
        }
    }

    nonisolated func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        Task { @MainActor [weak self] in
            self?.state = .failed(error.localizedDescription)
            self?.finishActiveCapture(with: .failure(error))
        }
    }

    nonisolated func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.state = .processTerminated
            self.finishActiveCapture(with: .failure(BrowserError.processTerminated))
        }
    }
}
