import Foundation
import Testing
@testable import Luma

struct DownloadManagerTests {
    @Test
    func rejectsHTTPSDowngradeRedirect() {
        #expect(
            !DownloadManager.isAllowedRedirect(
                from: URL(string: "https://appstorrent.ru/download/file.dmg")!,
                to: URL(string: "http://cdn.example.com/file.dmg")!
            )
        )
    }

    @Test
    func allowsHTTPSRedirect() {
        #expect(
            DownloadManager.isAllowedRedirect(
                from: URL(string: "https://appstorrent.ru/download/file.dmg")!,
                to: URL(string: "https://cdn.example.com/file.dmg")!
            )
        )
    }

    @Test
    func redirectedRequestReplacesCookiesForDestinationHost() throws {
        let sourceCookie = try HTTPCookie(properties: [
            .domain: "appstorrent.ru",
            .path: "/",
            .name: "session",
            .value: "source",
            .secure: "TRUE"
        ]).unwrap()
        let destinationCookie = try HTTPCookie(properties: [
            .domain: "cdn.example.com",
            .path: "/",
            .name: "session",
            .value: "destination",
            .secure: "TRUE"
        ]).unwrap()
        var request = URLRequest(url: URL(string: "https://cdn.example.com/file.dmg")!)
        request.setValue("stale=value", forHTTPHeaderField: "Cookie")

        let redirected = DownloadManager.redirectedRequest(
            request,
            from: URL(string: "https://appstorrent.ru/file.dmg")!,
            to: URL(string: "https://cdn.example.com/file.dmg")!,
            cookies: [sourceCookie, destinationCookie]
        )

        #expect(redirected?.value(forHTTPHeaderField: "Cookie") == "session=destination")
    }

    @Test
    func redirectedRequestRejectsHTTPSDowngrade() {
        let request = URLRequest(url: URL(string: "http://cdn.example.com/file.dmg")!)

        #expect(
            DownloadManager.redirectedRequest(
                request,
                from: URL(string: "https://appstorrent.ru/file.dmg")!,
                to: URL(string: "http://cdn.example.com/file.dmg")!,
                cookies: []
            ) == nil
        )
    }

    @Test
    func filtersCookiesToTheDownloadHost() throws {
        let appstorrentCookie = try HTTPCookie(properties: [
            .domain: "appstorrent.ru",
            .path: "/",
            .name: "session",
            .value: "appstorrent-session",
            .secure: "TRUE"
        ]).unwrap()

        let unrelatedCookie = try HTTPCookie(properties: [
            .domain: "mediafire.com",
            .path: "/",
            .name: "session",
            .value: "mediafire-session",
            .secure: "TRUE"
        ]).unwrap()

        let result = DownloadManager.matchingCookies(
            [appstorrentCookie, unrelatedCookie],
            for: URL(string: "https://downloads.example.com/file/installer.dmg")!
        )

        #expect(result.isEmpty)
    }

    @Test
    func allowsParentDomainCookiesForSecureSubdomains() throws {
        let cookie = try HTTPCookie(properties: [
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
    func rejectsSimilarSuffixHosts() throws {
        let cookie = try HTTPCookie(properties: [
            .domain: ".appstorrent.ru",
            .path: "/",
            .name: "session",
            .value: "session",
            .secure: "TRUE"
        ]).unwrap()

        let result = DownloadManager.matchingCookies(
            [cookie],
            for: URL(string: "https://notappstorrent.ru/installer.dmg")!
        )

        #expect(result.isEmpty)
    }

    @Test
    func matchesCookiePathAndRejectsSimilarPaths() throws {
        let cookie = try HTTPCookie(properties: [
            .domain: "example.com",
            .path: "/downloads",
            .name: "session",
            .value: "session",
            .secure: "TRUE"
        ]).unwrap()

        #expect(
            !DownloadManager.matchingCookies(
                [cookie],
                for: URL(string: "https://example.com/downloads/file.dmg")!
            ).isEmpty
        )
        #expect(
            DownloadManager.matchingCookies(
                [cookie],
                for: URL(string: "https://example.com/downloads-other/file.dmg")!
            ).isEmpty
        )
    }

    @Test
    func rootCookiePathMatchesAnyPath() throws {
        let cookie = try HTTPCookie(properties: [
            .domain: "example.com",
            .path: "/",
            .name: "session",
            .value: "session",
            .secure: "TRUE"
        ]).unwrap()

        #expect(
            !DownloadManager.matchingCookies(
                [cookie],
                for: URL(string: "https://example.com/any/path")!
            ).isEmpty
        )
    }

    @Test
    func rejectsSecureCookiesForHTTPDownloads() throws {
        let cookie = try HTTPCookie(properties: [
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
        let cookie = try HTTPCookie(properties: [
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
