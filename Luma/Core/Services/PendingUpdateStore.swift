import Foundation

nonisolated struct PendingExternalUpdate: Codable, Equatable, Sendable {
    let bundleIdentifier: String
    let version: String
    let fileURL: URL
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

    func save(_ update: PendingExternalUpdate) {
        var updates = all()
        updates[update.bundleIdentifier] = update
        persist(updates)
    }

    func remove(for application: ApplicationIdentity) {
        var updates = all()
        updates.removeValue(forKey: application.bundleIdentifier)
        persist(updates)
    }

    private func all() -> [String: PendingExternalUpdate] {
        guard let data = defaults.data(forKey: storageKey),
              let updates = try? JSONDecoder().decode(
                  [String: PendingExternalUpdate].self,
                  from: data
              ) else {
            return [:]
        }
        return updates
    }

    private func persist(_ updates: [String: PendingExternalUpdate]) {
        guard let data = try? JSONEncoder().encode(updates) else {
            return
        }
        defaults.set(data, forKey: storageKey)
    }
}
