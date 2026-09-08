import Foundation

nonisolated struct InstalledApplication: Identifiable, Hashable, Sendable {
    let id: ApplicationIdentity
    let name: String
    let version: SoftwareVersion
    let bundleURL: URL
    let installationSource: ApplicationInstallationSource

    init(
        id: ApplicationIdentity,
        name: String,
        version: SoftwareVersion,
        bundleURL: URL,
        installationSource: ApplicationInstallationSource = .unknown
    ) {
        self.id = id
        self.name = name
        self.version = version
        self.bundleURL = bundleURL
        self.installationSource = installationSource
    }
}
