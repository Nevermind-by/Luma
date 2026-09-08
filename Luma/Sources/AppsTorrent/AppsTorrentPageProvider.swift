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

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchPage(at url: URL) async throws -> String {
        var request = URLRequest(url: url)
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        request.setValue("Luma/0.1", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
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
    }
}
