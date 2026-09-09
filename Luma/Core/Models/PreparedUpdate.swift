import Foundation

nonisolated struct PreparedUpdate: Identifiable, Equatable, Sendable {
    let id: UUID
    let application: ApplicationIdentity
    let version: SoftwareVersion
    let artifactURL: URL
    let payload: PreparedUpdatePayload
    let bundleIdentifier: String?
    let stagingDirectoryURL: URL?

    init(
        id: UUID = UUID(),
        application: ApplicationIdentity,
        version: SoftwareVersion,
        artifactURL: URL,
        payload: PreparedUpdatePayload,
        bundleIdentifier: String? = nil,
        stagingDirectoryURL: URL? = nil
    ) {
        self.id = id
        self.application = application
        self.version = version
        self.artifactURL = artifactURL
        self.payload = payload
        self.bundleIdentifier = bundleIdentifier
        self.stagingDirectoryURL = stagingDirectoryURL
    }

    var installerURL: URL {
        payload.url
    }

    var isApplicationBundle: Bool {
        if case .application = payload {
            return true
        }
        return false
    }
}
