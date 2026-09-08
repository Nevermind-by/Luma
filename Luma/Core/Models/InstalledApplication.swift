import Foundation

nonisolated struct InstalledApplication: Identifiable, Hashable, Sendable {
    let id: ApplicationIdentity
    let name: String
    let version: SoftwareVersion
    let bundleURL: URL
    let installationSource: ApplicationInstallationSource
}
