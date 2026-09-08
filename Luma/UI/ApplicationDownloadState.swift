import Foundation

nonisolated enum ApplicationDownloadState: Equatable, Sendable {
    case notStarted
    case downloading(DownloadProgress)
    case readyToInstall(PreparedUpdate)
    case failed(String)
}
