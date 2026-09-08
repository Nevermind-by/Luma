import Foundation

nonisolated struct AppsTorrentSource: UpdateSource {
    let name = "AppsTorrent"

    private let pageURLsByBundleIdentifier: [String: URL]
    private let pageProvider: any AppsTorrentPageProviding
    private let parser: AppsTorrentPageParser

    init(
        pageURLsByBundleIdentifier: [String: URL],
        pageProvider: any AppsTorrentPageProviding = URLSessionAppsTorrentPageProvider(),
        parser: AppsTorrentPageParser = AppsTorrentPageParser()
    ) {
        self.pageURLsByBundleIdentifier = pageURLsByBundleIdentifier
        self.pageProvider = pageProvider
        self.parser = parser
    }

    func checkForUpdate(for application: InstalledApplication) async throws -> UpdateCandidate? {
        guard let pageURL = pageURLsByBundleIdentifier[application.id.bundleIdentifier] else {
            return nil
        }

        let html = try await pageProvider.fetchPage(at: pageURL)
        let release = try parser.parse(html: html, pageURL: pageURL)

        guard release.version != application.version else {
            return nil
        }

        return UpdateCandidate(
            application: application.id,
            version: release.version,
            downloadOptions: release.downloadOptions
        )
    }
}
