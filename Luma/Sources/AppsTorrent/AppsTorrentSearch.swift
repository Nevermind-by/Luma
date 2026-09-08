import Foundation

nonisolated struct AppsTorrentSearchResult: Hashable, Sendable {
    let title: String
    let url: URL
}

nonisolated protocol AppsTorrentSearchProviding: Sendable {
    func search(for query: String) async throws -> [AppsTorrentSearchResult]
}

nonisolated struct URLSessionAppsTorrentSearchProvider: AppsTorrentSearchProviding {
    private let session: URLSession
    private let baseURL: URL
    private let browserProvider: AppsTorrentBrowserSearchProvider

    init(
        session: URLSession = .shared,
        baseURL: URL = URL(string: "https://appstorrent.ru")!,
        browserProvider: AppsTorrentBrowserSearchProvider? = nil
    ) {
        self.session = session
        self.baseURL = baseURL
        self.browserProvider = browserProvider ?? AppsTorrentBrowserSearchProvider(baseURL: baseURL)
    }

    func search(for query: String) async throws -> [AppsTorrentSearchResult] {
        guard let url = searchURL(for: query) else {
            throw AppsTorrentSearchError.invalidSearchURL
        }

        do {
            var request = URLRequest(url: url)
            request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
            request.setValue("Luma/0.1", forHTTPHeaderField: "User-Agent")

            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw AppsTorrentSearchError.invalidResponse
            }

            guard (200..<300).contains(httpResponse.statusCode) else {
                if httpResponse.statusCode == 403 {
                    throw AppsTorrentSearchError.cloudflareChallengeDetected
                }
                throw AppsTorrentSearchError.invalidResponse
            }

            guard let html = String(data: data, encoding: .utf8) else {
                throw AppsTorrentSearchError.invalidResponse
            }

            if html.localizedCaseInsensitiveContains("Just a moment...")
                || html.localizedCaseInsensitiveContains("cf-chl-") {
                throw AppsTorrentSearchError.cloudflareChallengeDetected
            }

            return AppsTorrentSearchParser().parse(html: html, baseURL: baseURL)
        } catch AppsTorrentSearchError.cloudflareChallengeDetected {
            return try await browserProvider.search(for: query)
        }
    }

    private func searchURL(for query: String) -> URL? {
        guard var components = URLComponents(
            url: baseURL.appendingPathComponent("index.php"),
            resolvingAgainstBaseURL: false
        ) else {
            return nil
        }

        components.queryItems = [
            URLQueryItem(name: "do", value: "search"),
            URLQueryItem(name: "subaction", value: "search"),
            URLQueryItem(name: "story", value: query)
        ]

        return components.url
    }
}

nonisolated struct AppsTorrentBrowserSearchProvider: AppsTorrentSearchProviding {
    private let baseURL: URL

    init(baseURL: URL = URL(string: "https://appstorrent.ru")!) {
        self.baseURL = baseURL
    }

    func search(for query: String) async throws -> [AppsTorrentSearchResult] {
        guard var components = URLComponents(
            url: baseURL.appendingPathComponent("index.php"),
            resolvingAgainstBaseURL: false
        ) else {
            throw AppsTorrentSearchError.invalidSearchURL
        }

        components.queryItems = [
            URLQueryItem(name: "do", value: "search"),
            URLQueryItem(name: "subaction", value: "search"),
            URLQueryItem(name: "story", value: query)
        ]

        guard let url = components.url else {
            throw AppsTorrentSearchError.invalidSearchURL
        }

        let session = await MainActor.run {
            AppsTorrentBrowserSession.shared
        }
        let html = try await session.loadAndCaptureHTML(at: url)

        if html.localizedCaseInsensitiveContains("Just a moment...")
            || html.localizedCaseInsensitiveContains("cf-chl-") {
            throw AppsTorrentSearchError.cloudflareChallengeDetected
        }

        return AppsTorrentSearchParser().parse(html: html, baseURL: baseURL)
    }
}

enum AppsTorrentSearchError: Error, Equatable {
    case invalidSearchURL
    case invalidResponse
    case cloudflareChallengeDetected
}

nonisolated struct AppsTorrentSearchParser: Sendable {
    func parse(html: String, baseURL: URL) -> [AppsTorrentSearchResult] {
        let pattern = #"<a\s+[^>]*href=[\"']([^\"']+\.html(?:#[^\"']*)?)[\"'][^>]*>(.*?)</a>"#
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return []
        }

        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        return regex.matches(in: html, options: [], range: range).compactMap { match in
            guard match.numberOfRanges > 2,
                  let urlRange = Range(match.range(at: 1), in: html),
                  let titleRange = Range(match.range(at: 2), in: html) else {
                return nil
            }

            let href = String(html[urlRange])
            let title = String(html[titleRange])
                .replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
                .decodedHTML
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard !title.isEmpty,
                  let url = URL(string: href, relativeTo: baseURL)?.absoluteURL else {
                return nil
            }

            guard url.host?.localizedCaseInsensitiveCompare(baseURL.host ?? "") == .orderedSame else {
                return nil
            }

            return AppsTorrentSearchResult(title: title, url: url)
        }
    }
}

private extension String {
    nonisolated var decodedHTML: String {
        replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
    }
}
