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

    @Published private(set) var isLoginCompleted: Bool

    init(
        defaults: UserDefaults = .standard,
        session: AppsTorrentBrowserSession = .shared
    ) {
        self.defaults = defaults
        self.session = session
        self.isLoginCompleted = defaults.bool(forKey: Keys.loginCompleted)
    }

    func markLoginCompleted() {
        defaults.set(true, forKey: Keys.loginCompleted)
        isLoginCompleted = true
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
