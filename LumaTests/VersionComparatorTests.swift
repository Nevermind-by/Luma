import Testing
@testable import Luma

struct VersionComparatorTests {
    private let comparator = VersionComparator()

    @Test func comparesNumericVersions() {
        #expect(comparator.compare(SoftwareVersion("27.0.1"), SoftwareVersion("26.2.2")) == .orderedDescending)
        #expect(comparator.compare(SoftwareVersion("26.2.2"), SoftwareVersion("27.0.1")) == .orderedAscending)
        #expect(comparator.compare(SoftwareVersion("27.0.1"), SoftwareVersion("27.0.1")) == .orderedSame)
    }

    @Test func handlesBuildSuffixes() {
        #expect(comparator.compare(SoftwareVersion("27.0.1-58670"), SoftwareVersion("27.0.1-58000")) == .orderedDescending)
    }

    @Test func ignoresSeparators() {
        #expect(comparator.compare(SoftwareVersion("1.2.3"), SoftwareVersion("1-2-3")) == .orderedSame)
    }
}
