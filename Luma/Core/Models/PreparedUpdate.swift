import Foundation

nonisolated struct PreparedUpdate: Identifiable, Equatable, Sendable {
    let id: UUID
    let application: ApplicationIdentity
    let version: SoftwareVersion
    let artifactURL: URL
    let applicationURL: URL
    let bundleIdentifier: String

    init(
        id: UUID = UUID(),
        application: ApplicationIdentity,
        version: SoftwareVersion,
        artifactURL: URL,
        applicationURL: URL,
        bundleIdentifier: String
    ) {
        self.id = id
        self.application = application
        self.version = version
        self.artifactURL = artifactURL
        self.applicationURL = applicationURL
        self.bundleIdentifier = bundleIdentifier
    }
}
