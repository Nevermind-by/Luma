import Combine
import Foundation
import OSLog
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
        let continuation: CheckedContinuation<DownloadedArtifact, Error>
    }

    @Published private(set) var state: State = .idle

    let webView: WKWebView
    private var pendingCaptures: [PendingCapture] = []
    private var activeCapture: PendingCapture?
    private var activeTimeoutTask: Task<Void, Never>?
    private var activeDownload: PendingDownload?
    private var activeDownloadDestination: URL?
    private var activeDownloadResponse: URLResponse?
    private var activeDownloadFinalURL: URL?
    private var downloadDidBecomeActive = false
    private var downloadFailureFallbackTask: Task<Void, Never>?
    private var loadedURL: URL?
    private let captureTimeoutNanoseconds: UInt64 = 30_000_000_000

    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        self.webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        self.webView.navigationDelegate = self
    }

    deinit {
        self.activeTimeoutTask?.cancel()
        self.downloadFailureFallbackTask?.cancel()
    }

    func load(_ url: URL) {
        self.loadedURL = url
        self.state = .loading(url)
        self.webView.load(URLRequest(url: url))
    }

    func reload() {
        guard let url = self.loadedURL else { return }
        self.state = .loading(url)
        self.webView.reload()
    }

    func loadAndCaptureHTML(at url: URL) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            self.pendingCaptures.append(
                PendingCapture(url: url, continuation: continuation)
            )
            self.processNextCaptureIfNeeded()
        }
    }

    func download(_ url: URL, to directory: URL) async throws -> DownloadedArtifact {
        guard self.activeDownload == nil else {
            throw BrowserError.downloadInProgress
        }

        return try await withCheckedThrowingContinuation { continuation in
            self.downloadDidBecomeActive = false
            self.downloadFailureFallbackTask?.cancel()
            self.downloadFailureFallbackTask = nil
            self.activeDownload = PendingDownload(
                url: url,
                destinationDirectory: directory,
                continuation: continuation
            )
            self.activeDownloadDestination = nil
            self.activeDownloadResponse = nil
            self.activeDownloadFinalURL = nil
            self.loadedURL = url
            self.state = .downloading(url)
            self.webView.load(URLRequest(url: url))
        }
    }

    func cookies(for url: URL) async -> [HTTPCookie] {
        await withCheckedContinuation { continuation in
            self.webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
                let host = url.host?.lowercased()
                let matching = cookies.filter { cookie in
                    guard let host else { return false }
                    let domain = cookie.domain
                        .lowercased()
                        .trimmingCharacters(in: CharacterSet(charactersIn: "."))
                    return host == domain || host.hasSuffix(".\(domain)")
                }
                continuation.resume(returning: matching)
            }
        }
    }

    func clearAppsTorrentData() async {
        let dataStore = self.webView.configuration.websiteDataStore
        await withCheckedContinuation { continuation in
            let types = WKWebsiteDataStore.allWebsiteDataTypes()
            dataStore.fetchDataRecords(ofTypes: types) { records in
                let matchingRecords = records.filter { record in
                    record.displayName.lowercased().contains("appstorrent.ru")
                }

                guard !matchingRecords.isEmpty else {
                    continuation.resume()
                    return
                }

                dataStore.removeData(ofTypes: types, for: matchingRecords) {
                    continuation.resume()
                }
            }
        }
    }

    private func processNextCaptureIfNeeded() {
        guard self.activeCapture == nil,
              self.activeDownload == nil,
              !self.pendingCaptures.isEmpty else {
            return
        }

        let request = self.pendingCaptures.removeFirst()
        self.activeCapture = request
        self.loadedURL = request.url
        self.state = .loading(request.url)

        self.activeTimeoutTask?.cancel()
        self.activeTimeoutTask = Task { [weak self] in
            let timeout: UInt64 = await MainActor.run {
                self?.captureTimeoutNanoseconds ?? 30_000_000_000
            }
            try? await Task.sleep(nanoseconds: timeout)
            guard !Task.isCancelled else { return }

            await MainActor.run {
                self?.finishActiveCapture(with: .failure(BrowserError.timeout))
            }
        }

        self.webView.load(URLRequest(url: request.url))
    }

    private func finishActiveCapture(with result: Result<String, Error>) {
        guard let activeCapture = self.activeCapture else { return }
        self.activeCapture = nil
        self.activeTimeoutTask?.cancel()
        self.activeTimeoutTask = nil
        activeCapture.continuation.resume(with: result)
        self.processNextCaptureIfNeeded()
    }

    private func finishActiveDownload(with result: Result<DownloadedArtifact, Error>) {
        guard let activeDownload = self.activeDownload else { return }
        self.activeDownload = nil
        self.downloadFailureFallbackTask?.cancel()
        self.downloadFailureFallbackTask = nil

        let destination = self.activeDownloadDestination
        let response = self.activeDownloadResponse
        let finalURL = self.activeDownloadFinalURL ?? response?.url ?? activeDownload.url
        self.activeDownloadDestination = nil
        self.activeDownloadResponse = nil
        self.activeDownloadFinalURL = nil
        self.downloadDidBecomeActive = false

        switch result {
        case .failure(let error):
            activeDownload.continuation.resume(throwing: error)
        case .success:
            guard let destination else {
                activeDownload.continuation.resume(throwing: BrowserError.downloadFailed)
                self.processNextCaptureIfNeeded()
                return
            }

            let resourceValues = try? destination.resourceValues(forKeys: [.fileSizeKey])
            let byteCount = Int64(resourceValues?.fileSize ?? 0)
            activeDownload.continuation.resume(returning: DownloadedArtifact(
                originalURL: activeDownload.url,
                finalURL: finalURL,
                fileURL: destination,
                filename: destination.lastPathComponent,
                mimeType: response?.mimeType,
                byteCount: byteCount
            ))
        }

        self.processNextCaptureIfNeeded()
    }

    private func scheduleDownloadFailureFallback(for error: Error) {
        self.downloadFailureFallbackTask?.cancel()
        self.downloadFailureFallbackTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }

            await MainActor.run {
                guard let self,
                      self.activeDownload != nil,
                      !self.downloadDidBecomeActive else {
                    return
                }
                self.finishActiveDownload(with: .failure(error))
            }
        }
    }

    private func captureCurrentHTML() {
        self.webView.evaluateJavaScript("document.documentElement.outerHTML") { [weak self] value, error in
            Task { @MainActor [weak self] in
                guard let self else { return }

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
    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
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
            guard let self else { return }
            self.state = .failed(error.localizedDescription)
            self.finishActiveCapture(with: .failure(error))

            if self.activeDownload != nil {
                if self.downloadDidBecomeActive {
                    self.finishActiveDownload(with: .failure(error))
                } else {
                    self.scheduleDownloadFailureFallback(for: error)
                }
            }
        }
    }

    nonisolated func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.state = .failed(error.localizedDescription)
            self.finishActiveCapture(with: .failure(error))

            // A direct file navigation often reports "Frame load interrupted"
            // when WebKit hands the navigation off to WKDownload. Do not fail
            // the logical download before the download delegate has a chance
            // to claim it.
            if self.activeDownload != nil {
                if self.downloadDidBecomeActive {
                    self.finishActiveDownload(with: .failure(error))
                } else {
                    self.scheduleDownloadFailureFallback(for: error)
                }
            }
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
            self.downloadDidBecomeActive = true
            self.downloadFailureFallbackTask?.cancel()
            self.downloadFailureFallbackTask = nil
            download.delegate = self
            LumaLog.appsTorrent.info("AppsTorrent WKDownload became active")
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

            let trimmed = suggestedFilename.trimmingCharacters(in: .whitespacesAndNewlines)
            let filename = trimmed.isEmpty
                ? (activeDownload.url.lastPathComponent.isEmpty ? "Luma-Download" : activeDownload.url.lastPathComponent)
                : trimmed

            let destination = self.uniqueDestinationURL(
                filename: filename,
                directory: activeDownload.destinationDirectory
            )
            self.activeDownloadResponse = response
            if let responseURL = response.url {
                self.activeDownloadFinalURL = responseURL
            }
            self.activeDownloadDestination = destination
            completionHandler(destination)

            LumaLog.appsTorrent.info(
                "AppsTorrent download response: filename=\(filename, privacy: .public), mime=\(response.mimeType ?? "unknown", privacy: .public), url=\((response.url ?? activeDownload.url).absoluteString, privacy: .public)"
            )
        }
    }

    nonisolated func download(_ download: WKDownload, didReceiveFinalURL url: URL) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.activeDownloadFinalURL = url
            LumaLog.appsTorrent.info("AppsTorrent download final URL: \(url.absoluteString, privacy: .public)")
        }
    }

    nonisolated func downloadDidFinish(_ download: WKDownload) {
        Task { @MainActor [weak self] in
            guard let self,
                  let activeDownload = self.activeDownload,
                  let destination = self.activeDownloadDestination else {
                return
            }

            let resourceValues = try? destination.resourceValues(forKeys: [.fileSizeKey])
            let byteCount = Int64(resourceValues?.fileSize ?? 0)
            LumaLog.appsTorrent.info(
                "AppsTorrent download finished: path=\(destination.path, privacy: .public), bytes=\(byteCount, privacy: .public)"
            )
            self.finishActiveDownload(with: .success(DownloadedArtifact(
                originalURL: activeDownload.url,
                finalURL: self.activeDownloadFinalURL ?? self.activeDownloadResponse?.url ?? activeDownload.url,
                fileURL: destination,
                filename: destination.lastPathComponent,
                mimeType: self.activeDownloadResponse?.mimeType,
                byteCount: byteCount
            )))
        }
    }

    nonisolated func download(
        _ download: WKDownload,
        didFailWithError error: Error,
        resumeData: Data?
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.state = .failed(error.localizedDescription)
            LumaLog.appsTorrent.error("AppsTorrent WKDownload failed: \(error.localizedDescription, privacy: .public)")
            self.finishActiveDownload(with: .failure(error))
        }
    }

    private func uniqueDestinationURL(filename: String, directory: URL) -> URL {
        let initialURL = directory.appendingPathComponent(filename)
        if !FileManager.default.fileExists(atPath: initialURL.path) {
            return initialURL
        }

        let base = initialURL.deletingPathExtension().lastPathComponent
        let ext = initialURL.pathExtension
        for index in 2...10_000 {
            let candidateName = ext.isEmpty
                ? "\(base) (\(index))"
                : "\(base) (\(index)).\(ext)"
            let candidate = directory.appendingPathComponent(candidateName)
            if !FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }

        return directory.appendingPathComponent("Luma-\(UUID().uuidString).download")
    }
}
