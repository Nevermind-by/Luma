import Combine
import Foundation
import WebKit

@MainActor
final class AppsTorrentAuthenticationManager: ObservableObject {
    private enum Keys {
        static let loginCompleted = "AppsTorrent.loginCompleted"
    }

    private let defaults: UserDefaults
    private let session: AppsTorrentBrowserSession
    private let appsTorrentURL = URL(string: "https://appstorrent.ru")!

    @Published private(set) var isLoginCompleted: Bool

    init(
        defaults: UserDefaults = .standard,
        session: AppsTorrentBrowserSession? = nil
    ) {
        self.defaults = defaults
        self.session = session ?? AppsTorrentBrowserSession.shared
        self.isLoginCompleted = defaults.bool(forKey: Keys.loginCompleted)
    }

    func markLoginCompleted() {
        defaults.set(true, forKey: Keys.loginCompleted)
        isLoginCompleted = true
    }

    func refreshLoginState() async -> Bool {
        guard defaults.bool(forKey: Keys.loginCompleted) else {
            isLoginCompleted = false
            return false
        }

        let cookies = await session.cookies(for: appsTorrentURL)
        let now = Date()
        let hasLiveSessionCookie = cookies.contains { cookie in
            guard !cookie.isExpired(at: now) else { return false }
            return !cookie.value.isEmpty
        }

        if !hasLiveSessionCookie {
            defaults.removeObject(forKey: Keys.loginCompleted)
            isLoginCompleted = false
            return false
        }

        isLoginCompleted = true
        return true
    }

    func cookies(for url: URL) async -> [HTTPCookie] {
        await session.cookies(for: url)
    }

    func logout() async {
        await session.clearAppsTorrentData()
        defaults.removeObject(forKey: Keys.loginCompleted)
        isLoginCompleted = false
    }
}

private extension HTTPCookie {
    func isExpired(at date: Date) -> Bool {
        guard let expiresDate else { return false }
        return expiresDate <= date
    }
}
