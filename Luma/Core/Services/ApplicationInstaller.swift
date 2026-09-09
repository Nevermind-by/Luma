import AppKit
import Foundation
import OSLog

@MainActor
protocol ApplicationInstalling {
    func install(
        _ preparedUpdate: PreparedUpdate,
        replacing application: InstalledApplication
    ) async throws -> InstallationResult
}

@MainActor
final class ApplicationInstaller: ApplicationInstalling {
    enum InstallationError: LocalizedError, Equatable {
        case applicationNotFound
        case destinationAuthorizationRequired
        case destinationMismatch
        case applicationStillRunning
        case replacementFailed
        case verificationFailed
        case installerOpenFailed
        case cancelled

        var errorDescription: String? {
            switch self {
            case .applicationNotFound:
                return "The installed application could not be found."
            case .destinationAuthorizationRequired:
                return "Luma could not access the application’s installation folder."
            case .destinationMismatch:
                return "The selected folder does not contain the installed application."
            case .applicationStillRunning:
                return "The application is still running. Quit it and try again."
            case .replacementFailed:
                return "Luma could not replace the installed application. The original app was restored when possible."
            case .verificationFailed:
                return "The installed application did not pass the final identity and version check."
            case .installerOpenFailed:
                return "Luma could not open the downloaded installer."
            case .cancelled:
                return "Installation was cancelled."
            }
        }
    }

    private let destinationStore: InstallDestinationStore

    init(destinationStore: InstallDestinationStore) {
        self.destinationStore = destinationStore
    }

    func install(
        _ preparedUpdate: PreparedUpdate,
        replacing application: InstalledApplication
    ) async throws -> InstallationResult {
        switch preparedUpdate.payload {
        case .application:
            return try await replaceApplication(
                preparedUpdate,
                replacing: application
            )
        case .diskImage(let installerURL), .package(let installerURL), .externalInstaller(let installerURL):
            guard FileManager.default.fileExists(atPath: installerURL.path) else {
                throw InstallationError.installerOpenFailed
            }

            LumaLog.updates.info(
                "Opening external installer: \(installerURL.path, privacy: .public)"
            )
            let didOpen = NSWorkspace.shared.open(installerURL)
            guard didOpen else {
                throw InstallationError.installerOpenFailed
            }

            return .userActionRequired
        }
    }

    private func replaceApplication(
        _ preparedUpdate: PreparedUpdate,
        replacing application: InstalledApplication
    ) async throws -> InstallationResult {
        guard let sourceURL = applicationURL(from: preparedUpdate) else {
            throw InstallationError.applicationNotFound
        }

        defer {
            if let stagingDirectoryURL = preparedUpdate.stagingDirectoryURL {
                try? FileManager.default.removeItem(at: stagingDirectoryURL)
            }
        }

        let fileManager = FileManager.default
        let installedURL = application.bundleURL
        let installedDirectory = installedURL.deletingLastPathComponent()

        guard fileManager.fileExists(atPath: sourceURL.path),
              fileManager.fileExists(atPath: installedURL.path) else {
            throw InstallationError.applicationNotFound
        }

        let destinationDirectory = try await authorizedDestinationDirectory(
            expectedDirectory: installedDirectory,
            application: application
        )

        guard destinationDirectory.standardizedFileURL == installedDirectory.standardizedFileURL else {
            throw InstallationError.destinationMismatch
        }

        let scopeStarted = destinationDirectory.startAccessingSecurityScopedResource()
        defer {
            if scopeStarted {
                destinationDirectory.stopAccessingSecurityScopedResource()
            }
        }

        if let runningApplication = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleURL?.standardizedFileURL == installedURL.standardizedFileURL
        }) {
            guard await confirmQuit(runningApplication, applicationName: application.name) else {
                throw InstallationError.cancelled
            }

            runningApplication.terminate()
            for _ in 0..<50 {
                if runningApplication.isTerminated { break }
                try? await Task.sleep(for: .milliseconds(200))
            }

            guard runningApplication.isTerminated else {
                throw InstallationError.applicationStillRunning
            }
        }

        let backupURL = destinationDirectory.appendingPathComponent(
            ".Luma-Backup-\(UUID().uuidString)-\(installedURL.lastPathComponent)",
            isDirectory: true
        )

        do {
            try fileManager.moveItem(at: installedURL, to: backupURL)
            do {
                try fileManager.moveItem(at: sourceURL, to: installedURL)
            } catch {
                try? fileManager.moveItem(at: backupURL, to: installedURL)
                throw error
            }

            guard verifyInstalledApplication(
                at: installedURL,
                expected: preparedUpdate
            ) else {
                try? fileManager.removeItem(at: installedURL)
                try? fileManager.moveItem(at: backupURL, to: installedURL)
                throw InstallationError.verificationFailed
            }

            try? fileManager.removeItem(at: backupURL)
        } catch let error as InstallationError {
            throw error
        } catch {
            throw InstallationError.replacementFailed
        }

        return .completed
    }

    private func applicationURL(from preparedUpdate: PreparedUpdate) -> URL? {
        guard case .application(let url) = preparedUpdate.payload else {
            return nil
        }
        return url
    }

    private func authorizedDestinationDirectory(
        expectedDirectory: URL,
        application: InstalledApplication
    ) async throws -> URL {
        if let savedDirectory = destinationStore.savedDirectory() {
            guard savedDirectory.startAccessingSecurityScopedResource() else {
                destinationStore.clear()
                return try await requestDestinationDirectory(
                    expectedDirectory: expectedDirectory,
                    application: application
                )
            }
            savedDirectory.stopAccessingSecurityScopedResource()
            return savedDirectory
        }

        return try await requestDestinationDirectory(
            expectedDirectory: expectedDirectory,
            application: application
        )
    }

    private func requestDestinationDirectory(
        expectedDirectory: URL,
        application: InstalledApplication
    ) async throws -> URL {
        let selectedDirectory = await chooseInstallationDirectory(
            expectedDirectory: expectedDirectory,
            application: application
        )

        guard let selectedDirectory else {
            throw InstallationError.cancelled
        }

        destinationStore.save(directory: selectedDirectory)
        return selectedDirectory
    }

    private func chooseInstallationDirectory(
        expectedDirectory: URL,
        application: InstalledApplication
    ) async -> URL? {
        await withCheckedContinuation { continuation in
            let panel = NSOpenPanel()
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.allowsMultipleSelection = false
            panel.canCreateDirectories = false
            panel.directoryURL = expectedDirectory
            panel.prompt = "Allow"
            panel.message = "Allow Luma to update \(application.name) in this folder."
            panel.begin { response in
                continuation.resume(returning: response == .OK ? panel.url : nil)
            }
        }
    }

    private func confirmQuit(
        _ runningApplication: NSRunningApplication,
        applicationName: String
    ) async -> Bool {
        await withCheckedContinuation { continuation in
            let alert = NSAlert()
            alert.messageText = "Quit \(applicationName) to install the update?"
            alert.informativeText = "Luma needs to replace the installed application. Unsaved work in \(applicationName) may be lost."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Quit and Install")
            alert.addButton(withTitle: "Cancel")
            let response = alert.runModal()
            continuation.resume(returning: response == .alertFirstButtonReturn)
        }
    }

    private func verifyInstalledApplication(
        at url: URL,
        expected: PreparedUpdate
    ) -> Bool {
        guard let bundle = Bundle(url: url),
              bundle.bundleIdentifier == expected.bundleIdentifier else {
            return false
        }

        guard let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
              !version.isEmpty else {
            return false
        }

        return SoftwareVersion(version) == expected.version
    }
}
