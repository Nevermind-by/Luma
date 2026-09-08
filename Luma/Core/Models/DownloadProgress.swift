import Foundation

nonisolated struct DownloadProgress: Equatable, Sendable {
    let bytesWritten: Int64
    let totalBytes: Int64?

    var fractionCompleted: Double? {
        guard let totalBytes, totalBytes > 0 else {
            return nil
        }

        return min(max(Double(bytesWritten) / Double(totalBytes), 0), 1)
    }
}
