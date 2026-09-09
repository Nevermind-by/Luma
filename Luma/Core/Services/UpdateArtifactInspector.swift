import Foundation
import OSLog

nonisolated protocol UpdateArtifactInspecting: Sendable {
    func inspect(
        artifact: DownloadedArtifact,
        expectedApplication: ApplicationIdentity,
        expectedVersion: SoftwareVersion
    ) async throws -> PreparedUpdate
}

final class UpdateArtifactInspector: UpdateArtifactInspecting, @unchecked Sendable {
    enum InspectionError: LocalizedError, Equatable {
        case invalidDownloadedResponse
        case unsupportedArtifactType(ArtifactType)
        case extractionFailed
        case applicationNotFound
        case bundleIdentifierMismatch(expected: String, actual: String)
        case versionMismatch(expected: String, actual: String)

        var errorDescription: String? {
            switch self {
            case .invalidDownloadedResponse:
                return "The downloaded response is not an application update."
            case .unsupportedArtifactType(let type):
                return "Luma recognized the downloaded file as \(type.rawValue), but that installer format is not supported yet."
            case .extractionFailed:
                return "Luma could not extract the downloaded update."
            case .applicationNotFound:
                return "No application bundle was found inside the downloaded update."
            case .bundleIdentifierMismatch(let expected, let actual):
                return "The downloaded application is not the expected app (bundle ID \(actual), expected \(expected))."
            case .versionMismatch(let expected, let actual):
                return "The downloaded application reports version \(actual), expected \(expected)."
            }
        }
    }

    private let classifier: any ArtifactClassifying

    init(classifier: any ArtifactClassifying = ArtifactClassifier()) {
        self.classifier = classifier
    }

    func inspect(
        artifact: DownloadedArtifact,
        expectedApplication: ApplicationIdentity,
        expectedVersion: SoftwareVersion
    ) async throws -> PreparedUpdate {
        let artifactType = classifier.classify(artifact)
        LumaLog.updates.info(
            "Downloaded artifact: filename=\(artifact.filename, privacy: .public), type=\(artifactType.rawValue, privacy: .public), mime=\(artifact.mimeType ?? "unknown", privacy: .public), bytes=\(artifact.byteCount, privacy: .public), finalURL=\(artifact.finalURL.absoluteString, privacy: .public)"
        )

        if artifactType == .html || (artifactType == .unknown && artifact.byteCount == 0) {
            throw InspectionError.invalidDownloadedResponse
        }

        let stagingDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Luma-Update-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)

        var keepStagingDirectory = false
        defer {
            if !keepStagingDirectory {
                try? FileManager.default.removeItem(at: stagingDirectory)
            }
        }

        switch artifactType {
        case .zip:
            try extractZip(artifact.fileURL, to: stagingDirectory)
        case .app:
            let destination = stagingDirectory.appendingPathComponent(artifact.fileURL.lastPathComponent)
            try FileManager.default.copyItem(at: artifact.fileURL, to: destination)
        case .pkg, .dmg, .iso, .html, .unknown:
            throw InspectionError.unsupportedArtifactType(artifactType)
        }

        guard let applicationURL = findApplication(in: stagingDirectory) else {
            throw InspectionError.applicationNotFound
        }

        guard let bundle = Bundle(url: applicationURL),
              let actualIdentifier = bundle.bundleIdentifier else {
            throw InspectionError.bundleIdentifierMismatch(
                expected: expectedApplication.bundleIdentifier,
                actual: "unknown"
            )
        }

        guard actualIdentifier == expectedApplication.bundleIdentifier else {
            throw InspectionError.bundleIdentifierMismatch(
                expected: expectedApplication.bundleIdentifier,
                actual: actualIdentifier
            )
        }

        let actualVersionString = (bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String)
            ?? ""
        let actualVersion = SoftwareVersion(actualVersionString)
        guard actualVersion == expectedVersion else {
            throw InspectionError.versionMismatch(
                expected: expectedVersion.rawValue,
                actual: actualVersionString.isEmpty ? "unknown" : actualVersionString
            )
        }

        keepStagingDirectory = true
        return PreparedUpdate(
            application: expectedApplication,
            version: expectedVersion,
            artifactURL: artifact.fileURL,
            applicationURL: applicationURL,
            bundleIdentifier: actualIdentifier,
            stagingDirectoryURL: stagingDirectory
        )
    }

    private func extractZip(_ archive: URL, to directory: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", archive.path, directory.path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw InspectionError.extractionFailed
        }
    }

    private func findApplication(in directory: URL) -> URL? {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        for case let url as URL in enumerator {
            if url.pathExtension.lowercased() == "app" {
                return url
            }
        }

        return nil
    }
}
