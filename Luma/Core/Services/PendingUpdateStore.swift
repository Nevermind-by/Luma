import Foundation

nonisolated struct PendingExternalUpdate: Codable, Equatable, Sendable {
    let bundleIdentifier: String
    let version: String
    let fileURL: URL
    let fileBookmarkData: Data?
    let installerOpened: Bool

    init(
        bundleIdentifier: String,
        version: String,
        fileURL: URL,
        fileBookmarkData: Data? = nil,
        installerOpened: Bool = false
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.version = version
        self.fileURL = fileURL
        self.fileBookmarkData = fileBookmarkData
        self.installerOpened = installerOpened
    }
}

nonisolated struct PendingExternalFileAccess {
    let url: URL
    private let startedSecurityScope: Bool

    init(url: URL, startedSecurityScope: Bool) {
        self.url = url
        self.startedSecurityScope = startedSecurityScope
    }

    func stop() {
        guard startedSecurityScope else { return }
        url.stopAccessingSecurityScopedResource()
    }
}

struct PendingUpdateStore {
    private let defaults: UserDefaults
    private let storageKey = "Luma.pendingExternalUpdates"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func pending(for application: ApplicationIdentity) -> PendingExternalUpdate? {
        all()[application.bundleIdentifier]
    }

    func resolvedFileURL(for application: ApplicationIdentity) -> URL? {
        guard let pending = pending(for: application) else { return nil }
        guard let bookmarkData = pending.fileBookmarkData else {
            return pending.fileURL
        }

        var isStale = false
        guard let resolvedURL = try? URL(
            resolvingBookmarkData: bookmarkData,
            options: [.withSecurityScope, .withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            return pending.fileURL
        }

        if isStale {
            save(
                PendingExternalUpdate(
                    bundleIdentifier: pending.bundleIdentifier,
                    version: pending.version,
                    fileURL: resolvedURL,
                    fileBookmarkData: bookmarkData,
                    installerOpened: pending.installerOpened
                )
            )
        }

        return resolvedURL
    }

    func beginFileAccess(for application: ApplicationIdentity) -> PendingExternalFileAccess? {
        guard let pending = pending(for: application),
              let resolvedURL = resolvedFileURL(for: application) else {
            return nil
        }

        let startedSecurityScope: Bool
        if pending.fileBookmarkData != nil {
            startedSecurityScope = resolvedURL.startAccessingSecurityScopedResource()
        } else {
            startedSecurityScope = false
        }

        return PendingExternalFileAccess(
            url: resolvedURL,
            startedSecurityScope: startedSecurityScope
        )
    }

    func markInstallerOpened(for application: ApplicationIdentity) {
        guard let pending = pending(for: application) else { return }
        save(
            PendingExternalUpdate(
                bundleIdentifier: pending.bundleIdentifier,
                version: pending.version,
                fileURL: pending.fileURL,
                fileBookmarkData: pending.fileBookmarkData,
                installerOpened: true
            )
        )
    }

    func save(_ update: PendingExternalUpdate) {
        let bookmarkData = update.fileBookmarkData ?? (try? update.fileURL.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ))

        let persistedUpdate = PendingExternalUpdate(
            bundleIdentifier: update.bundleIdentifier,
            version: update.version,
            fileURL: update.fileURL,
            fileBookmarkData: bookmarkData,
            installerOpened: update.installerOpened
        )

        var updates = all()
        updates[update.bundleIdentifier] = persistedUpdate
        persist(updates)
    }

    func remove(for application: ApplicationIdentity) {
        var updates = all()
        updates.removeValue(forKey: application.bundleIdentifier)
        persist(updates)
    }

    private func all() -> [String: PendingExternalUpdate] {
        guard let data = defaults.data(forKey: storageKey),
              let updates = try? JSONDecoder().decode([String: PendingExternalUpdate].self, from: data) else {
            return [:]
        }
        return updates
    }

    private func persist(_ updates: [String: PendingExternalUpdate]) {
        guard let data = try? JSONEncoder().encode(updates) else { return }
        defaults.set(data, forKey: storageKey)
    }
}
