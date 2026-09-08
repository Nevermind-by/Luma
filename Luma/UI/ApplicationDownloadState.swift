import Foundation

nonisolated enum ApplicationDownloadState: Equatable, Sendable {
    case notStarted
    case downloading(DownloadProgress)
    case completed(URL)
    case failed(String)
}
