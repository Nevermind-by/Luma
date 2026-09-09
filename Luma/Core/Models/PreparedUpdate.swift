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

    func replacingArtifactURL(with url: URL) -> PreparedUpdate {
        let updatedPayload: PreparedUpdatePayload
        switch payload {
        case .application:
            updatedPayload = .application(url)
        case .diskImage:
            updatedPayload = .diskImage(url)
        case .package:
            updatedPayload = .package(url)
        case .externalInstaller:
            updatedPayload = .externalInstaller(url)
        }

        return PreparedUpdate(
            id: id,
            application: application,
            version: version,
            artifactURL: url,
            payload: updatedPayload,
            bundleIdentifier: bundleIdentifier,
            stagingDirectoryURL: stagingDirectoryURL
        )
    }
}
