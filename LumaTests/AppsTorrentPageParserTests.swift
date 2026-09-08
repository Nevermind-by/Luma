import Foundation
import Testing
@testable import Luma

struct AppsTorrentPageParserTests {
    private let parser = AppsTorrentPageParser()

    @Test func parsesCurrentReleaseAndDownloadOptions() throws {
        let pageURL = URL(string: "https://appstorrent.ru/61-parallels-desktop.html")!
        let html = """
        <html>
        <body>
            <h1 itemprop="name">Parallels Desktop 27</h1>
            <span class="body-2" itemprop="softwareVersion">27.0.1-58670</span>
            <p><!--dle_spoiler Parallels Desktop 27.0.1-58670 (QiuChenly Crack Team) -->
                <div class="text_spoiler">
                    <p><a href="https://example.com/direct.iso">Прямая ссылка</a></p>
                    <p><a href="https://cloud.mail.ru/public/test/path">Скачать с Mail.ru</a></p>
                    <p><a href="https://www.mediafire.com/file/test/file">Скачать с MediaFire</a></p>
                </div>
            </p>
            <!--dle_spoiler Parallels Desktop 27.0.0-58628 -->
            <p><a href="https://example.com/old.iso">Прямая ссылка</a></p>
        </body>
        </html>
        """

        let release = try parser.parse(html: html, pageURL: pageURL)

        #expect(release.title == "Parallels Desktop 27")
        #expect(release.version == SoftwareVersion("27.0.1-58670"))
        #expect(release.pageURL == pageURL)
        #expect(release.downloadOptions.count == 3)
        #expect(release.downloadOptions.map(\.title) == ["Direct link", "Mail.ru", "MediaFire"])
        #expect(release.downloadOptions[0].url.absoluteString == "https://example.com/direct.iso")
        #expect(release.downloadOptions[1].url.absoluteString == "https://cloud.mail.ru/public/test/path")
        #expect(release.downloadOptions[2].url.absoluteString == "https://www.mediafire.com/file/test/file")
    }

    @Test func rejectsPageWithoutVersion() {
        let html = "<h1 itemprop=\"name\">Some App</h1>"
        let pageURL = URL(string: "https://appstorrent.ru/some-app.html")!

        #expect(throws: AppsTorrentPageParser.ParserError.missingVersion) {
            try parser.parse(html: html, pageURL: pageURL)
        }
    }

    @Test func rejectsPageWithoutCurrentReleaseBlock() {
        let html = """
        <h1 itemprop="name">Some App</h1>
        <span itemprop="softwareVersion">1.2.3</span>
        """
        let pageURL = URL(string: "https://appstorrent.ru/some-app.html")!

        #expect(throws: AppsTorrentPageParser.ParserError.missingCurrentReleaseBlock) {
            try parser.parse(html: html, pageURL: pageURL)
        }
    }
}
