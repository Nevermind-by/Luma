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
            pageProvider: provider
        )
        let application = InstalledApplication(
            id: ApplicationIdentity(bundleIdentifier: "com.parallels.desktop.console"),
            name: "Parallels Desktop",
            version: SoftwareVersion("27.0.0-58628"),
            bundleURL: URL(fileURLWithPath: "/Applications/Parallels Desktop.app")
        )

        let candidate = try await source.checkForUpdate(for: application)

        #expect(candidate?.version == SoftwareVersion("27.0.1-58670"))
        #expect(candidate?.application == application.id)
        #expect(candidate?.downloadOptions.count == 1)
    }

    @Test func returnsNilForUnknownApplication() async throws {
        let source = AppsTorrentSource(
            pageURLsByBundleIdentifier: [:],
            pageProvider: StubPageProvider(pages: [:])
        )
        let application = InstalledApplication(
            id: ApplicationIdentity(bundleIdentifier: "com.example.unknown"),
            name: "Unknown",
            version: SoftwareVersion("1.0"),
            bundleURL: URL(fileURLWithPath: "/Applications/Unknown.app")
        )

        let candidate = try await source.checkForUpdate(for: application)

        #expect(candidate == nil)
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

    private enum TestError: Error {
        case missingPage
    }
}
