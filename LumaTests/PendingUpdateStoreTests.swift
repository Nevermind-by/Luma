import Foundation
import Testing
@testable import Luma

struct PendingUpdateStoreTests {
    @Test
    func savesReadsAndRemovesPendingUpdate() {
        let suiteName = "LumaTests.PendingUpdateStore.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = PendingUpdateStore(defaults: defaults)
        let application = ApplicationIdentity(bundleIdentifier: "com.example.fixture")
        let update = PendingExternalUpdate(
            bundleIdentifier: application.bundleIdentifier,
            version: "2.0.0",
            fileURL: URL(fileURLWithPath: "/Users/test/Downloads/Fixture.dmg")
        )

        store.save(update)

        #expect(store.pending(for: application) == update)

        store.remove(for: application)

        #expect(store.pending(for: application) == nil)
    }

    @Test
    func keepsPendingUpdatesForDifferentApplicationsIndependent() {
        let suiteName = "LumaTests.PendingUpdateStore.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = PendingUpdateStore(defaults: defaults)
        let firstApplication = ApplicationIdentity(bundleIdentifier: "com.example.first")
        let secondApplication = ApplicationIdentity(bundleIdentifier: "com.example.second")

        store.save(
            PendingExternalUpdate(
                bundleIdentifier: firstApplication.bundleIdentifier,
                version: "1.0.0",
                fileURL: URL(fileURLWithPath: "/tmp/First.dmg")
            )
        )
        store.save(
            PendingExternalUpdate(
                bundleIdentifier: secondApplication.bundleIdentifier,
                version: "2.0.0",
                fileURL: URL(fileURLWithPath: "/tmp/Second.dmg")
            )
        )

        #expect(store.pending(for: firstApplication)?.version == "1.0.0")
        #expect(store.pending(for: secondApplication)?.version == "2.0.0")
    }
}
