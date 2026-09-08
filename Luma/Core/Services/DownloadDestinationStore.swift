import Foundation

nonisolated struct DownloadDestinationStore: Sendable {
    private let defaults: UserDefaults
    private let bookmarkKey = "Luma.downloadDestinationBookmark"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func savedDirectory() -> URL? {
        guard let data = defaults.data(forKey: bookmarkKey) else {
            return nil
        }

        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope, .withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            defaults.removeObject(forKey: bookmarkKey)
            return nil
        }

        if isStale {
            save(directory: url)
        }

        return url
    }

    func save(directory: URL) {
        guard let data = try? directory.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) else {
            return
        }

        defaults.set(data, forKey: bookmarkKey)
    }

    func clear() {
        defaults.removeObject(forKey: bookmarkKey)
    }
}
