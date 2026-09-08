import Foundation

nonisolated protocol AppsTorrentPageProviding: Sendable {
    func fetchPage(at url: URL) async throws -> String
}

nonisolated struct URLSessionAppsTorrentPageProvider: AppsTorrentPageProviding {
    enum ProviderError: Error, Equatable {
        case invalidResponse
        case cloudflareChallengeDetected
    }

    private let session: URLSession
    private let browserProvider: AppsTorrentBrowserPageProvider

    init(
        session: URLSession = .shared,
        browserProvider: AppsTorrentBrowserPageProvider = AppsTorrentBrowserPageProvider()
    ) {
        self.session = session
        self.browserProvider = browserProvider
    }

    func fetchPage(at url: URL) async throws -> String {
        do {
            LumaLog.appsTorrent.info("Fetching AppsTorrent page via URLSession host=\(url.host ?? "unknown", privacy: .public)")

            var request = URLRequest(url: url)
            request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
            request.setValue("Luma/0.1", forHTTPHeaderField: "User-Agent")

            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw ProviderError.invalidResponse
            }

            guard (200..<300).contains(httpResponse.statusCode) else {
                if httpResponse.statusCode == 403 {
                    throw ProviderError.cloudflareChallengeDetected
                }
                throw ProviderError.invalidResponse
            }

            guard let html = String(data: data, encoding: .utf8) else {
                throw ProviderError.invalidResponse
            }

            if html.localizedCaseInsensitiveContains("Just a moment...")
                || html.localizedCaseInsensitiveContains("cf-chl-") {
                throw ProviderError.cloudflareChallengeDetected
            }

            return html
        } catch ProviderError.cloudflareChallengeDetected {
            LumaLog.appsTorrent.info("Falling back to authenticated WebKit for AppsTorrent page host=\(url.host ?? "unknown", privacy: .public)")
            return try await browserProvider.fetchPage(at: url)
        }
    }
}

nonisolated struct AppsTorrentBrowserPageProvider: AppsTorrentPageProviding {
    func fetchPage(at url: URL) async throws -> String {
        let session = await MainActor.run {
            AppsTorrentBrowserSession.shared
        }
        let html = try await session.loadAndCaptureHTML(at: url)

        if html.localizedCaseInsensitiveContains("Just a moment...")
            || html.localizedCaseInsensitiveContains("cf-chl-") {
            throw URLSessionAppsTorrentPageProvider.ProviderError.cloudflareChallengeDetected
        }

        return html
    }
}
