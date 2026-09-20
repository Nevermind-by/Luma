import Testing
@testable import Luma

struct AppsTorrentBrowserSessionTests {
    @Test
    func matchesAppsTorrentHostAndItsSubdomains() {
        #expect(AppsTorrentBrowserSession.matchesAppsTorrentDataRecordName("appstorrent.ru"))
        #expect(AppsTorrentBrowserSession.matchesAppsTorrentDataRecordName("www.appstorrent.ru"))
        #expect(AppsTorrentBrowserSession.matchesAppsTorrentDataRecordName("cdn.appstorrent.ru"))
        #expect(AppsTorrentBrowserSession.matchesAppsTorrentDataRecordName("  APPSTORRENT.RU  "))
    }

    @Test
    func rejectsSimilarWebsiteDataRecordNames() {
        #expect(!AppsTorrentBrowserSession.matchesAppsTorrentDataRecordName("notappstorrent.ru"))
        #expect(!AppsTorrentBrowserSession.matchesAppsTorrentDataRecordName("appstorrent.ru.example.com"))
        #expect(!AppsTorrentBrowserSession.matchesAppsTorrentDataRecordName("appstorrent.ru.evil"))
    }
}
