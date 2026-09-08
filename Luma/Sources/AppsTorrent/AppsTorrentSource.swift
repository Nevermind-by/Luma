import Foundation
import OSLog

nonisolated struct AppsTorrentSource: UpdateSource {
    let name = "AppsTorrent"

    private let pageURLsByBundleIdentifier: [String: URL]
    private let pageProvider: any AppsTorrentPageProviding
    private let searchProvider: any AppsTorrentSearchProviding
    private let resolver: AppsTorrentApplicationResolver
    private let parser: AppsTorrentPageParser
    private let versionComparator: VersionComparator
    private let maxCandidatePages = 8

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
        LumaLog.appsTorrent.info("Checking \(application.name, privacy: .public) version \(application.version.rawValue, privacy: .public)")

        let pageURLs = try await pageURLs(for: application)
        LumaLog.appsTorrent.info("Resolved \(pageURLs.count, privacy: .public) AppsTorrent candidate pages for \(application.name, privacy: .public)")

        var releases: [AppsTorrentRelease] = []
        var firstPageError: Error?

        for pageURL in pageURLs.prefix(maxCandidatePages) {
            do {
                let html = try await pageProvider.fetchPage(at: pageURL)
                let release = try parser.parse(html: html, pageURL: pageURL)
                releases.append(release)
                LumaLog.appsTorrent.info("Parsed release \(release.version.rawValue, privacy: .public) [\(release.distributionVariant.rawValue, privacy: .public)]")
            } catch {
                firstPageError = firstPageError ?? error
                LumaLog.appsTorrent.error("Failed to parse AppsTorrent candidate: \(error.localizedDescription, privacy: .public)")
            }
        }

        guard !releases.isEmpty else {
            if let firstPageError {
                throw firstPageError
            }
            throw AppsTorrentApplicationResolver.ResolverError.noMatch
        }

        let releasesForInstallation = preferredReleases(
            releases,
            installationSource: application.installationSource
        )

        guard let latestRelease = releasesForInstallation.max(by: isReleaseOlder) else {
            return nil
        }

        let comparison = versionComparator.compare(latestRelease.version, application.version)
        LumaLog.appsTorrent.info(
            "Selected release \(latestRelease.version.rawValue, privacy: .public); comparison result \(comparisonDescription(comparison), privacy: .public)"
        )

        guard comparison == .orderedDescending else {
            return nil
        }

        return UpdateCandidate(
            application: application.id,
            version: latestRelease.version,
            distributionVariant: latestRelease.distributionVariant,
            downloadOptions: latestRelease.downloadOptions
        )
    }

    private func pageURLs(for application: InstalledApplication) async throws -> [URL] {
        if let mappedURL = pageURLsByBundleIdentifier[application.id.bundleIdentifier] {
            LumaLog.appsTorrent.info("Using mapped AppsTorrent page for \(application.name, privacy: .public)")
            return [mappedURL]
        }

        return try await resolver.resolveCandidates(for: application).map(\.url)
    }

    private func preferredReleases(
        _ releases: [AppsTorrentRelease],
        installationSource: ApplicationInstallationSource
    ) -> [AppsTorrentRelease] {
        guard let preferredVariant = preferredVariant(for: installationSource) else {
            return releases
        }

        let matching = releases.filter { $0.distributionVariant == preferredVariant }
        return matching.isEmpty ? releases : matching
    }

    private func preferredVariant(
        for installationSource: ApplicationInstallationSource
    ) -> AppsTorrentDistributionVariant? {
        switch installationSource {
        case .appStore:
            return .mas
        case .direct:
            return .standard
        case .unknown:
            return nil
        }
    }

    private func isReleaseOlder(
        _ lhs: AppsTorrentRelease,
        _ rhs: AppsTorrentRelease
    ) -> Bool {
        versionComparator.compare(lhs.version, rhs.version) == .orderedAscending
    }

    private func comparisonDescription(_ result: VersionComparator.Result) -> String {
        switch result {
        case .orderedAscending:
            return "ascending"
        case .orderedSame:
            return "same"
        case .orderedDescending:
            return "descending"
        }
    }
}
