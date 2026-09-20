import Foundation
import Testing
@testable import Luma

struct InstallDestinationStoreTests {
    @Test
    func ignoresInvalidStoredBookmark() {
        let suiteName = "LumaTests.InstallDestinationStore.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(Data([0x01, 0x02, 0x03]), forKey: "Luma.installDestinationBookmark")

        let store = InstallDestinationStore(defaults: defaults)

        #expect(store.savedDirectory() == nil)
        #expect(defaults.data(forKey: "Luma.installDestinationBookmark") == nil)
    }
}
