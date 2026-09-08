import Foundation
import Testing
@testable import Luma

struct DownloadProgressTests {
    @Test func calculatesFractionCompleted() {
        let progress = DownloadProgress(bytesWritten: 25, totalBytes: 100)

        #expect(progress.fractionCompleted == 0.25)
    }

    @Test func clampsFractionToValidRange() {
        #expect(DownloadProgress(bytesWritten: 150, totalBytes: 100).fractionCompleted == 1)
        #expect(DownloadProgress(bytesWritten: -10, totalBytes: 100).fractionCompleted == 0)
    }

    @Test func returnsNilWhenTotalIsUnknown() {
        let progress = DownloadProgress(bytesWritten: 25, totalBytes: nil)

        #expect(progress.fractionCompleted == nil)
    }
}
