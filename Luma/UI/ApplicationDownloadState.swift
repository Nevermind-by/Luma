import Foundation

nonisolated enum ApplicationDownloadState: Equatable, Sendable {
    case notStarted
    case downloading(DownloadProgress)
    case readyToInstall(PreparedUpdate)
    case installing(SoftwareVersion)
    case installed(SoftwareVersion)
    case failed(String)
}
