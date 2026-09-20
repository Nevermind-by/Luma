import Foundation
import Testing
@testable import Luma

struct DownloadDestinationStoreTests {
    @Test
    func ignoresInvalidStoredBookmark() {
        let suiteName = "LumaTests.DownloadDestinationStore.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(Data([0x01, 0x02, 0x03]), forKey: "Luma.downloadDestinationBookmark")

        let store = DownloadDestinationStore(defaults: defaults)

        #expect(store.savedDirectory() == nil)
        #expect(defaults.data(forKey: "Luma.downloadDestinationBookmark") == nil)
    }
}
