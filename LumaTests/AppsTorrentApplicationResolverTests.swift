import Foundation
import Testing
@testable import Luma

struct AppsTorrentApplicationResolverTests {
    @Test func resolvesExactApplicationName() async throws {
        let appURL = URL(string: "https://appstorrent.ru/parallels-desktop.html")!
        let provider = StubSearchProvider(results: [
            AppsTorrentSearchResult(title: "Other App", url: URL(string: "https://appstorrent.ru/other.html")!),
            AppsTorrentSearchResult(title: "Parallels Desktop", url: appURL)
        ])
        let resolver = AppsTorrentApplicationResolver(searchProvider: provider)
        let application = makeApplication(name: "Parallels Desktop")

        #expect(try await resolver.resolve(application: application) == appURL)
    }

    @Test func resolvesVersionSuffixedTitle() async throws {
        let appURL = URL(string: "https://appstorrent.ru/parallels-desktop.html")!
        let provider = StubSearchProvider(results: [
            AppsTorrentSearchResult(title: "Parallels Desktop 27", url: appURL)
        ])
        let resolver = AppsTorrentApplicationResolver(searchProvider: provider)
        let application = makeApplication(name: "Parallels Desktop")

        #expect(try await resolver.resolve(application: application) == appURL)
    }

    @Test func prefersMASForAppStoreInstallation() async throws {
        let masURL = URL(string: "https://appstorrent.ru/app-mas.html")!
        let standardURL = URL(string: "https://appstorrent.ru/app.html")!
        let provider = StubSearchProvider(results: [
            AppsTorrentSearchResult(title: "Test App", url: standardURL),
            AppsTorrentSearchResult(title: "Test App [MAS]", url: masURL)
        ])
        let resolver = AppsTorrentApplicationResolver(searchProvider: provider)
        let application = makeApplication(
            name: "Test App",
            installationSource: .appStore
        )

        #expect(try await resolver.resolve(application: application) == masURL)
    }

    @Test func prefersStandardForDirectInstallation() async throws {
        let masURL = URL(string: "https://appstorrent.ru/app-mas.html")!
        let standardURL = URL(string: "https://appstorrent.ru/app.html")!
        let provider = StubSearchProvider(results: [
            AppsTorrentSearchResult(title: "Test App [MAS]", url: masURL),
            AppsTorrentSearchResult(title: "Test App", url: standardURL)
        ])
        let resolver = AppsTorrentApplicationResolver(searchProvider: provider)
        let application = makeApplication(
            name: "Test App",
            installationSource: .direct
        )

        #expect(try await resolver.resolve(application: application) == standardURL)
    }

    @Test func rejectsAmbiguousMatches() async throws {
        let provider = StubSearchProvider(results: [
            AppsTorrentSearchResult(title: "Parallels Desktop 27", url: URL(string: "https://appstorrent.ru/one.html")!),
            AppsTorrentSearchResult(title: "Parallels Desktop 28", url: URL(string: "https://appstorrent.ru/two.html")!)
        ])
        let resolver = AppsTorrentApplicationResolver(searchProvider: provider)
        let application = makeApplication(name: "Parallels Desktop")

        await #expect(throws: AppsTorrentApplicationResolver.ResolverError.ambiguousMatch) {
            try await resolver.resolve(application: application)
        }
    }

    @Test func rejectsUnrelatedTitles() async throws {
        let provider = StubSearchProvider(results: [
            AppsTorrentSearchResult(title: "Parallels Toolbox", url: URL(string: "https://appstorrent.ru/toolbox.html")!),
            AppsTorrentSearchResult(title: "Desktop Organizer", url: URL(string: "https://appstorrent.ru/organizer.html")!)
        ])
        let resolver = AppsTorrentApplicationResolver(searchProvider: provider)
        let application = makeApplication(name: "Parallels Desktop")

        await #expect(throws: AppsTorrentApplicationResolver.ResolverError.noMatch) {
            try await resolver.resolve(application: application)
        }
    }

    @Test func parserExtractsLocalSearchResults() {
        let baseURL = URL(string: "https://appstorrent.ru")!
        let html = """
        <a href="/61-parallels-desktop.html">Parallels Desktop 27</a>
        <a href="https://appstorrent.ru/other.html"><span>Other App</span></a>
        <a href="https://example.com/external.html">External App</a>
        """

        let results = AppsTorrentSearchParser().parse(html: html, baseURL: baseURL)

        #expect(results.count == 2)
        #expect(results.map(\.title) == ["Parallels Desktop 27", "Other App"])
        #expect(results[0].url.absoluteString == "https://appstorrent.ru/61-parallels-desktop.html")
    }

    private func makeApplication(
        name: String,
        installationSource: ApplicationInstallationSource = .unknown
    ) -> InstalledApplication {
        InstalledApplication(
            id: ApplicationIdentity(bundleIdentifier: "com.example.test"),
            name: name,
            version: SoftwareVersion("1.0"),
            bundleURL: URL(fileURLWithPath: "/Applications/Test.app"),
            installationSource: installationSource
        )
    }

    private struct StubSearchProvider: AppsTorrentSearchProviding {
        let results: [AppsTorrentSearchResult]

        func search(for query: String) async throws -> [AppsTorrentSearchResult] {
            results
        }
    }
}
