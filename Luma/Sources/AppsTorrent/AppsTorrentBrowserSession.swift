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
        case downloading(URL)
        case failed(String)
        case processTerminated
    }

    private struct PendingCapture {
        let url: URL
        let continuation: CheckedContinuation<String, Error>
    }

    private struct PendingDownload {
        let url: URL
        let destinationDirectory: URL
        let continuation: CheckedContinuation<URL, Error>
    }

    @Published private(set) var state: State = .idle

    let webView: WKWebView
    private var pendingCaptures: [PendingCapture] = []
    private var activeCapture: PendingCapture?
    private var activeTimeoutTask: Task<Void, Never>?
    private var activeDownload: PendingDownload?
    private var activeDownloadDestination: URL?
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

    func download(_ url: URL, to directory: URL) async throws -> URL {
        guard activeDownload == nil else {
            throw BrowserError.downloadInProgress
        }

        return try await withCheckedThrowingContinuation { continuation in
            self.activeDownload = PendingDownload(
                url: url,
                destinationDirectory: directory,
                continuation: continuation
            )
            self.activeDownloadDestination = nil
            self.loadedURL = url
            self.state = .downloading(url)
            self.webView.load(URLRequest(url: url))
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
        guard activeCapture == nil, activeDownload == nil, !pendingCaptures.isEmpty else { return }

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

    private func finishActiveDownload(with result: Result<URL, Error>) {
        guard let activeDownload else { return }
        self.activeDownload = nil
        let destination = activeDownloadDestination
        activeDownloadDestination = nil
        activeDownload.continuation.resume(with: result.map { _ in destination ?? activeDownload.destinationDirectory })
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
        case downloadInProgress
        case downloadFailed

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
            case .downloadInProgress:
                return "An AppsTorrent download is already in progress."
            case .downloadFailed:
                return "The AppsTorrent browser could not download the file."
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

            if self.activeCapture != nil {
                self.state = .ready(url)
                self.captureCurrentHTML()
            } else if self.activeDownload == nil {
                self.state = .ready(url)
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
            self?.finishActiveDownload(with: .failure(error))
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
            self?.finishActiveDownload(with: .failure(error))
        }
    }

    nonisolated func webView(
        _ webView: WKWebView,
        navigationAction: WKNavigationAction,
        didBecome download: WKDownload
    ) {
        Task { @MainActor [weak self] in
            guard let self, self.activeDownload != nil else {
                download.cancel()
                return
            }
            download.delegate = self
        }
    }

    nonisolated func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.state = .processTerminated
            self.finishActiveCapture(with: .failure(BrowserError.processTerminated))
            self.finishActiveDownload(with: .failure(BrowserError.processTerminated))
        }
    }
}

extension AppsTorrentBrowserSession: WKDownloadDelegate {
    nonisolated func download(
        _ download: WKDownload,
        decideDestinationUsing response: URLResponse,
        suggestedFilename: String,
        completionHandler: @escaping (URL?) -> Void
    ) {
        Task { @MainActor [weak self] in
            guard let self, let activeDownload = self.activeDownload else {
                completionHandler(nil)
                return
            }

            let filename = suggestedFilename
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty ? (activeDownload.url.lastPathComponent.isEmpty ? "Luma-Download" : activeDownload.url.lastPathComponent) : suggestedFilename
            let destination = self.uniqueDestinationURL(
                filename: filename,
                directory: activeDownload.destinationDirectory
            )
            self.activeDownloadDestination = destination
            completionHandler(destination)
        }
    }

    nonisolated func downloadDidFinish(_ download: WKDownload) {
        Task { @MainActor [weak self] in
            guard let self, self.activeDownload != nil else { return }
            let destination = self.activeDownloadDestination ?? self.uniqueDestinationURL(
                filename: self.activeDownload?.url.lastPathComponent.isEmpty == false ? self.activeDownload!.url.lastPathComponent : "Luma-Download",
                directory: self.activeDownload!.destinationDirectory
            )
            self.finishActiveDownload(with: .success(destination))
        }
    }

    nonisolated func download(
        _ download: WKDownload,
        didFailWithError error: Error,
        resumeData: Data?
    ) {
        Task { @MainActor [weak self] in
            self?.state = .failed(error.localizedDescription)
            self?.finishActiveDownload(with: .failure(error))
        }
    }

    private func uniqueDestinationURL(filename: String, directory: URL) -> URL {
        let initialURL = directory.appendingPathComponent(filename)
        guard FileManager.default.fileExists(atPath: initialURL.path) else {
            return initialURL
        }

        let base = initialURL.deletingPathExtension().lastPathComponent
        let ext = initialURL.pathExtension

        for index in 2...10_000 {
            let candidateName = ext.isEmpty ? "\(base) (\(index))" : "\(base) (\(index)).\(ext)"
            let candidate = directory.appendingPathComponent(candidateName)
            if !FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }

        return directory.appendingPathComponent("Luma-\(UUID().uuidString).download")
    }
}
