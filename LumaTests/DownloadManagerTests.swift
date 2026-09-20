import Foundation
import Testing
@testable import Luma

struct DownloadManagerTests {
    @Test
    func filtersCookiesToTheDownloadHost() throws {
        let appstorrentCookie = HTTPCookie(properties: [
            .domain: "appstorrent.ru",
            .path: "/",
            .name: "session",
            .value: "appstorrent-session",
            .secure: "TRUE"
        ]).unwrap()

        let unrelatedCookie = HTTPCookie(properties: [
            .domain: "mediafire.com",
            .path: "/",
            .name: "session",
            .value: "mediafire-session",
            .secure: "TRUE"
        ]).unwrap()

        let result = DownloadManager.matchingCookies(
            [appstorrentCookie, unrelatedCookie],
            for: URL(string: "https://mediafire.com/file/installer.dmg")!
        )

        #expect(result.isEmpty)
    }

    @Test
    func allowsParentDomainCookiesForSecureSubdomains() throws {
        let cookie = HTTPCookie(properties: [
            .domain: ".appstorrent.ru",
            .path: "/",
            .name: "session",
            .value: "session",
            .secure: "TRUE"
        ]).unwrap()

        let result = DownloadManager.matchingCookies(
            [cookie],
            for: URL(string: "https://cdn.appstorrent.ru/installer.dmg")!
        )

        #expect(result.count == 1)
    }

    @Test
    func rejectsSecureCookiesForHTTPDownloads() throws {
        let cookie = HTTPCookie(properties: [
            .domain: "example.com",
            .path: "/",
            .name: "session",
            .value: "session",
            .secure: "TRUE"
        ]).unwrap()

        let result = DownloadManager.matchingCookies(
            [cookie],
            for: URL(string: "http://example.com/file.dmg")!
        )

        #expect(result.isEmpty)
    }

    @Test
    func ignoresExpiredCookies() throws {
        let cookie = HTTPCookie(properties: [
            .domain: "example.com",
            .path: "/",
            .name: "session",
            .value: "session",
            .expires: Date(timeIntervalSince1970: 1),
            .secure: "TRUE"
        ]).unwrap()

        let result = DownloadManager.matchingCookies(
            [cookie],
            for: URL(string: "https://example.com/file.dmg")!
        )

        #expect(result.isEmpty)
    }
}

private extension Optional where Wrapped == HTTPCookie {
    func unwrap() throws -> HTTPCookie {
        guard let value = self else {
            throw TestCookieError.invalidCookie
        }
        return value
    }
}

private enum TestCookieError: Error {
    case invalidCookie
}
