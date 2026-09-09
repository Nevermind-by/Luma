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
        case installerNotFound
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
            case .installerNotFound:
                return "No installer disk image was found inside the downloaded ISO."
            case .bundleIdentifierMismatch(let expected, let actual):
                return "The downloaded application is not the expected app (bundle ID \(actual), expected \(expected))."
            case .versionMismatch(let expected, let actual):
                return "The downloaded application reports version \(actual), expected \(expected)."
            }
        }
    }

    private let classifier: any ArtifactClassifying
    private let isoExtractor: any ISOImageExtracting

    init(
        classifier: any ArtifactClassifying = ArtifactClassifier(),
        isoExtractor: any ISOImageExtracting = ISOImageExtractor()
    ) {
        self.classifier = classifier
        self.isoExtractor = isoExtractor
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

        if artifactType == .html || artifactType == .unknown {
            throw InspectionError.invalidDownloadedResponse
        }

        switch artifactType {
        case .zip:
            return try inspectZip(
                artifact: artifact,
                expectedApplication: expectedApplication,
                expectedVersion: expectedVersion
            )
        case .app:
            return try prepareApplication(
                sourceURL: artifact.fileURL,
                artifactURL: artifact.fileURL,
                expectedApplication: expectedApplication,
                expectedVersion: expectedVersion
            )
        case .dmg:
            return PreparedUpdate(
                application: expectedApplication,
                version: expectedVersion,
                artifactURL: artifact.fileURL,
                payload: .diskImage(artifact.fileURL)
            )
        case .iso:
            let destinationDirectory = artifact.fileURL.deletingLastPathComponent()
            do {
                let dmgURL = try isoExtractor.extractFirstDiskImage(
                    from: artifact.fileURL,
                    to: destinationDirectory
                )
                LumaLog.updates.info(
                    "Extracted installer disk image from ISO: \(dmgURL.path, privacy: .public)"
                )
                return PreparedUpdate(
                    application: expectedApplication,
                    version: expectedVersion,
                    artifactURL: artifact.fileURL,
                    payload: .diskImage(dmgURL)
                )
            } catch let error as ISOImageExtractor.ExtractionError where error == .diskImageNotFound {
                throw InspectionError.installerNotFound
            } catch {
                LumaLog.updates.error(
                    "ISO extraction failed: \(error.localizedDescription, privacy: .public)"
                )
                throw InspectionError.extractionFailed
            }
        case .pkg:
            return PreparedUpdate(
                application: expectedApplication,
                version: expectedVersion,
                artifactURL: artifact.fileURL,
                payload: .package(artifact.fileURL)
            )
        case .html, .unknown:
            throw InspectionError.invalidDownloadedResponse
        }
    }

    private func inspectZip(
        artifact: DownloadedArtifact,
        expectedApplication: ApplicationIdentity,
        expectedVersion: SoftwareVersion
    ) throws -> PreparedUpdate {
        let stagingDirectory = try makeStagingDirectory()
        var keepStagingDirectory = false
        defer {
            if !keepStagingDirectory {
                try? FileManager.default.removeItem(at: stagingDirectory)
            }
        }

        try extractZip(artifact.fileURL, to: stagingDirectory)
        guard let applicationURL = findApplication(in: stagingDirectory) else {
            throw InspectionError.applicationNotFound
        }

        try verifyApplication(
            at: applicationURL,
            expectedApplication: expectedApplication,
            expectedVersion: expectedVersion
        )

        keepStagingDirectory = true
        return PreparedUpdate(
            application: expectedApplication,
            version: expectedVersion,
            artifactURL: artifact.fileURL,
            payload: .application(applicationURL),
            bundleIdentifier: expectedApplication.bundleIdentifier,
            stagingDirectoryURL: stagingDirectory
        )
    }

    private func prepareApplication(
        sourceURL: URL,
        artifactURL: URL,
        expectedApplication: ApplicationIdentity,
        expectedVersion: SoftwareVersion
    ) throws -> PreparedUpdate {
        try verifyApplication(
            at: sourceURL,
            expectedApplication: expectedApplication,
            expectedVersion: expectedVersion
        )

        return PreparedUpdate(
            application: expectedApplication,
            version: expectedVersion,
            artifactURL: artifactURL,
            payload: .application(sourceURL),
            bundleIdentifier: expectedApplication.bundleIdentifier
        )
    }

    private func makeStagingDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Luma-Update-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
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

    private func verifyApplication(
        at url: URL,
        expectedApplication: ApplicationIdentity,
        expectedVersion: SoftwareVersion
    ) throws {
        guard let bundle = Bundle(url: url),
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
