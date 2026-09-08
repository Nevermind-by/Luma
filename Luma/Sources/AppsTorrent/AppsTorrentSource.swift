import Foundation

nonisolated struct AppsTorrentSource: UpdateSource {
    let name = "AppsTorrent"

    private let pageURLsByBundleIdentifier: [String: URL]
    private let pageProvider: any AppsTorrentPageProviding
    private let searchProvider: any AppsTorrentSearchProviding
    private let resolver: AppsTorrentApplicationResolver
    private let parser: AppsTorrentPageParser
    private let versionComparator: VersionComparator

    init(
        pageURLsByBundleIdentifier: [String: URL] = [:],
        pageProvider: any AppsTorrentPageProviding = URLSessionAppsTorrentPageProvider(),
        searchProvider: any AppsTorrentSearchProviding = URLSessionAppsTorrentSearchProvider(),
        resolver: AppsTorrentApplicationResolver? = nil,
        parser: AppsTorrentPageParser = AppsTorrentPageParser(),
        versionComparator: VersionComparator = VersionComparator()
    ) {
        self.pageURLsByBundleIdentifier = pageURLsByBundleIdentifier
        self.pageProvider = pageProvider
        self.searchProvider = searchProvider
        self.resolver = resolver ?? AppsTorrentApplicationResolver(searchProvider: searchProvider)
        self.parser = parser
        self.versionComparator = versionComparator
    }

    func checkForUpdate(for application: InstalledApplication) async throws -> UpdateCandidate? {
        let pageURL = try await pageURL(for: application)
        let html = try await pageProvider.fetchPage(at: pageURL)
        let release = try parser.parse(html: html, pageURL: pageURL)

        guard versionComparator.compare(release.version, application.version) == .orderedDescending else {
            return nil
        }

        return UpdateCandidate(
            application: application.id,
            version: release.version,
            downloadOptions: release.downloadOptions
        )
    }

    private func pageURL(for application: InstalledApplication) async throws -> URL {
        if let mappedURL = pageURLsByBundleIdentifier[application.id.bundleIdentifier] {
            return mappedURL
        }

        return try await resolver.resolve(application: application)
    }
}
