import Foundation

nonisolated struct AppsTorrentRelease: Hashable, Sendable {
    let title: String
    let version: SoftwareVersion
    let pageURL: URL
    let downloadOptions: [DownloadOption]
}
