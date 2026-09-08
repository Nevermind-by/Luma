import Foundation
import Testing
@testable import Luma

struct AppsTorrentSourceTests {
    @Test func returnsCandidateForKnownApplication() async throws {
        let pageURL = URL(string: "https://appstorrent.ru/61-parallels-desktop.html")!
        let html = """
        <h1 itemprop="name">Parallels Desktop 27</h1>
        <span itemprop="softwareVersion">27.0.1-58670</span>
        <!--dle_spoiler Parallels Desktop 27.0.1-58670 -->
        <a href="https://example.com/parallels.dmg">Скачать с MediaFire</a>
        <!--dle_spoiler Parallels Desktop 27.0.0-58628 -->
        """

        let provider = StubPageProvider(pages: [pageURL: html])
        let source = AppsTorrentSource(
            pageURLsByBundleIdentifier: ["com.parallels.desktop.console": pageURL],
            pageProvider: provider,
            searchProvider: StubSearchProvider(results: [])
        )
        let application = makeApplication(version: "27.0.0-58628")

        let candidate = try await source.checkForUpdate(for: application)

        #expect(candidate?.version == SoftwareVersion("27.0.1-58670"))
        #expect(candidate?.application == application.id)
        #expect(candidate?.downloadOptions.count == 1)
    }

    @Test func resolvesPageAutomaticallyWhenNoMappingExists() async throws {
        let pageURL = URL(string: "https://appstorrent.ru/61-parallels-desktop.html")!
        let provider = StubPageProvider(pages: [pageURL: """
        <h1 itemprop="name">Parallels Desktop 27</h1>
        <span itemprop="softwareVersion">27.0.1-58670</span>
        <!--dle_spoiler Parallels Desktop 27.0.1-58670 -->
        <a href="https://example.com/parallels.dmg">Скачать с MediaFire</a>
        """])
        let searchProvider = StubSearchProvider(results: [
            AppsTorrentSearchResult(title: "Parallels Desktop 27", url: pageURL)
        ])
        let source = AppsTorrentSource(
            pageProvider: provider,
            searchProvider: searchProvider
        )

        let candidate = try await source.checkForUpdate(for: makeApplication(version: "27.0.0"))

        #expect(candidate?.version == SoftwareVersion("27.0.1-58670"))
    }

    @Test func resolvesHighestVersionFromMultipleSearchResults() async throws {
        let olderURL = URL(string: "https://appstorrent.ru/parallels-27.html")!
        let newerURL = URL(string: "https://appstorrent.ru/parallels-28.html")!
        let provider = StubPageProvider(pages: [
            olderURL: """
            <h1 itemprop="name">Parallels Desktop 27</h1>
            <span itemprop="softwareVersion">27.0.1</span>
            <!--dle_spoiler Parallels Desktop 27.0.1 -->
            <a href="https://example.com/parallels-27.dmg">Прямая ссылка</a>
            """,
            newerURL: """
            <h1 itemprop="name">Parallels Desktop 28</h1>
            <span itemprop="softwareVersion">28.0.1</span>
            <!--dle_spoiler Parallels Desktop 28.0.1 -->
            <a href="https://example.com/parallels-28.dmg">Прямая ссылка</a>
            """
        ])
        let searchProvider = StubSearchProvider(results: [
            AppsTorrentSearchResult(title: "Parallels Desktop 27", url: olderURL),
            AppsTorrentSearchResult(title: "Parallels Desktop 28", url: newerURL)
        ])
        let source = AppsTorrentSource(
            pageProvider: provider,
            searchProvider: searchProvider
        )
        let application = makeApplication(version: "27.0.0")

        let candidate = try await source.checkForUpdate(for: application)

        #expect(candidate?.version == SoftwareVersion("28.0.1"))
        #expect(candidate?.downloadOptions.first?.url.absoluteString == "https://example.com/parallels-28.dmg")
    }

    @Test func prefersMatchingDistributionVariantBeforeComparingVersion() async throws {
        let standardURL = URL(string: "https://appstorrent.ru/app-standard.html")!
        let masURL = URL(string: "https://appstorrent.ru/app-mas.html")!
        let provider = StubPageProvider(pages: [
            standardURL: """
            <h1 itemprop="name">Test App</h1>
            <span itemprop="softwareVersion">5.0</span>
            <!--dle_spoiler Test App 5.0 -->
            <a href="https://example.com/standard.dmg">Прямая ссылка</a>
            """,
            masURL: """
            <h1 itemprop="name">Test App [MAS]</h1>
            <span itemprop="softwareVersion">4.0</span>
            <!--dle_spoiler Test App [MAS] 4.0 -->
            <a href="https://example.com/mas.dmg">Прямая ссылка</a>
            """
        ])
        let searchProvider = StubSearchProvider(results: [
            AppsTorrentSearchResult(title: "Test App", url: standardURL),
            AppsTorrentSearchResult(title: "Test App [MAS]", url: masURL)
        ])
        let source = AppsTorrentSource(
            pageProvider: provider,
            searchProvider: searchProvider
        )
        let application = makeApplication(
            version: "3.0",
            installationSource: .appStore
        )

        let candidate = try await source.checkForUpdate(for: application)

        #expect(candidate?.version == SoftwareVersion("4.0"))
        #expect(candidate?.distributionVariant == .mas)
    }

    @Test func doesNotOfferDowngrade() async throws {
        let pageURL = URL(string: "https://appstorrent.ru/app.html")!
        let provider = StubPageProvider(pages: [pageURL: """
        <h1 itemprop="name">Test App</h1>
        <span itemprop="softwareVersion">1.9</span>
        <!--dle_spoiler Test App 1.9 -->
        <a href="https://example.com/test.dmg">Скачать с MediaFire</a>
        """])
        let source = AppsTorrentSource(
            pageURLsByBundleIdentifier: ["com.example.test": pageURL],
            pageProvider: provider,
            searchProvider: StubSearchProvider(results: [])
        )
        let application = InstalledApplication(
            id: ApplicationIdentity(bundleIdentifier: "com.example.test"),
            name: "Test App",
            version: SoftwareVersion("2.0"),
            bundleURL: URL(fileURLWithPath: "/Applications/Test App.app")
        )

        let candidate = try await source.checkForUpdate(for: application)

        #expect(candidate == nil)
    }

    @Test func returnsNilForUnknownApplication() async throws {
        let source = AppsTorrentSource(
            pageURLsByBundleIdentifier: [:],
            pageProvider: StubPageProvider(pages: [:]),
            searchProvider: StubSearchProvider(results: [])
        )
        let application = InstalledApplication(
            id: ApplicationIdentity(bundleIdentifier: "com.example.unknown"),
            name: "Unknown",
            version: SoftwareVersion("1.0"),
            bundleURL: URL(fileURLWithPath: "/Applications/Unknown.app")
        )

        await #expect(throws: AppsTorrentApplicationResolver.ResolverError.noMatch) {
            try await source.checkForUpdate(for: application)
        }
    }

    private func makeApplication(
        version: String,
        installationSource: ApplicationInstallationSource = .unknown
    ) -> InstalledApplication {
        InstalledApplication(
            id: ApplicationIdentity(bundleIdentifier: "com.parallels.desktop.console"),
            name: "Parallels Desktop",
            version: SoftwareVersion(version),
            bundleURL: URL(fileURLWithPath: "/Applications/Parallels Desktop.app"),
            installationSource: installationSource
        )
    }

    private struct StubPageProvider: AppsTorrentPageProviding {
        let pages: [URL: String]

        func fetchPage(at url: URL) async throws -> String {
            guard let page = pages[url] else {
                throw TestError.missingPage
            }
            return page
        }
    }

    private struct StubSearchProvider: AppsTorrentSearchProviding {
        let results: [AppsTorrentSearchResult]

        func search(for query: String) async throws -> [AppsTorrentSearchResult] {
            results
        }
    }

    private enum TestError: Error {
        case missingPage
    }
}
