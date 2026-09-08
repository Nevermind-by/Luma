import Foundation

nonisolated struct UpdateCandidate: Identifiable, Hashable, Sendable {
    let id: UUID
    let application: ApplicationIdentity
    let version: SoftwareVersion
    let distributionVariant: AppsTorrentDistributionVariant?
    let downloadOptions: [DownloadOption]

    init(
        id: UUID = UUID(),
        application: ApplicationIdentity,
        version: SoftwareVersion,
        distributionVariant: AppsTorrentDistributionVariant? = nil,
        downloadOptions: [DownloadOption]
    ) {
        self.id = id
        self.application = application
        self.version = version
        self.distributionVariant = distributionVariant
        self.downloadOptions = downloadOptions
    }
}
