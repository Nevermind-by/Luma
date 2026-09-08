import Foundation

struct UpdateCandidate: Identifiable, Hashable, Sendable {
    let id: UUID
    let application: ApplicationIdentity
    let version: SoftwareVersion
    let downloadOptions: [DownloadOption]

    init(
        id: UUID = UUID(),
        application: ApplicationIdentity,
        version: SoftwareVersion,
        downloadOptions: [DownloadOption]
    ) {
        self.id = id
        self.application = application
        self.version = version
        self.downloadOptions = downloadOptions
    }
}
