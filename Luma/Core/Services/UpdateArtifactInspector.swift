import Foundation
import OSLog

nonisolated protocol UpdateArtifactInspecting: Sendable {
    func inspect(
        artifactURL: URL,
        expectedApplication: ApplicationIdentity,
        expectedVersion: SoftwareVersion
    ) async throws -> PreparedUpdate
}

final class UpdateArtifactInspector: UpdateArtifactInspecting, @unchecked Sendable {
    enum InspectionError: LocalizedError, Equatable {
        case unsupportedArtifact
        case extractionFailed
        case applicationNotFound
        case bundleIdentifierMismatch(expected: String, actual: String)
        case versionMismatch(expected: String, actual: String)

        var errorDescription: String? {
            switch self {
            case .unsupportedArtifact:
                return "Luma downloaded an unsupported update format."
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

    func inspect(
        artifactURL: URL,
        expectedApplication: ApplicationIdentity,
        expectedVersion: SoftwareVersion
    ) async throws -> PreparedUpdate {
        let stagingDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Luma-Update-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)

        var keepStagingDirectory = false
        defer {
            if !keepStagingDirectory {
                try? FileManager.default.removeItem(at: stagingDirectory)
            }
        }

        switch artifactFormat(for: artifactURL) {
        case .zip:
            try extractZip(artifactURL, to: stagingDirectory)
        case .dmg:
            try extractDMG(artifactURL, to: stagingDirectory)
        case .iso:
            try extractISO(artifactURL, to: stagingDirectory)
        case .unknown:
            throw InspectionError.unsupportedArtifact
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
            artifactURL: artifactURL,
            applicationURL: applicationURL,
            bundleIdentifier: actualIdentifier,
            stagingDirectoryURL: stagingDirectory
        )
    }

    private enum ArtifactFormat {
        case zip
        case dmg
        case iso
        case unknown
    }

    private func artifactFormat(for artifactURL: URL) -> ArtifactFormat {
        switch artifactURL.pathExtension.lowercased() {
        case "zip":
            return .zip
        case "dmg":
            return .dmg
        case "iso":
            return .iso
        default:
            break
        }

        if hasZipSignature(at: artifactURL) {
            return .zip
        }

        if isDiskImage(at: artifactURL) {
            return .dmg
        }

        return .unknown
    }

    private func hasZipSignature(at url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return false
        }
        defer { try? handle.close() }

        guard let header = try? handle.read(upToCount: 4), header.count >= 4 else {
            return false
        }

        return header[0] == 0x50
            && header[1] == 0x4B
            && header[2] == 0x03
            && (header[3] == 0x04 || header[3] == 0x05 || header[3] == 0x06)
    }

    private func isDiskImage(at url: URL) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        process.arguments = ["imageinfo", url.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
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

    private func extractISO(_ image: URL, to directory: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = ["-xf", image.path, "-C", directory.path]
        process.standardOutput = FileHandle.nullDevice

        let errorPipe = Pipe()
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let message = String(
                data: errorPipe.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            )?.trimmingCharacters(in: .whitespacesAndNewlines)
            LumaLog.updates.error(
                "ISO extraction failed: \(message ?? "unknown tar error", privacy: .public)"
            )
            throw InspectionError.extractionFailed
        }
    }

    private func extractDMG(_ image: URL, to directory: URL) throws {
        let mountPoint = FileManager.default.temporaryDirectory
            .appendingPathComponent("Luma-DMG-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: mountPoint, withIntermediateDirectories: true)
        defer {
            unmount(mountPoint)
            try? FileManager.default.removeItem(at: mountPoint)
        }

        let attach = Process()
        attach.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        attach.arguments = ["attach", "-nobrowse", "-readonly", "-mountpoint", mountPoint.path, image.path]
        try attach.run()
        attach.waitUntilExit()
        guard attach.terminationStatus == 0 else {
            throw InspectionError.extractionFailed
        }

        guard let applicationURL = findApplication(in: mountPoint) else {
            throw InspectionError.applicationNotFound
        }

        let destination = directory.appendingPathComponent(applicationURL.lastPathComponent)
        try FileManager.default.copyItem(at: applicationURL, to: destination)
    }

    private func unmount(_ mountPoint: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        process.arguments = ["detach", mountPoint.path, "-force"]
        try? process.run()
        process.waitUntilExit()
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
