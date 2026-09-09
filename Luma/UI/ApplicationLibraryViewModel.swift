import AppKit
import Combine
import Foundation

@MainActor
final class ApplicationLibraryViewModel: ObservableObject {
    @Published private(set) var applications: [InstalledApplication] = []
    @Published private(set) var updateStates: [ApplicationIdentity: ApplicationUpdateState] = [:]
    @Published private(set) var downloadStates: [ApplicationIdentity: ApplicationDownloadState] = [:]
    @Published private(set) var isScanning = false
    @Published private(set) var isCheckingUpdates = false
    @Published private(set) var appsTorrentConnection: UpdateSourceConnection
    @Published private(set) var downloadDirectoryURL: URL?

    private let scanner: any ApplicationScanning
    private let updateCoordinator: any ApplicationUpdateCoordinating
    private let downloadManager: any DownloadManaging
    private let artifactInspector: any UpdateArtifactInspecting
    private let applicationInstaller: any ApplicationInstalling
    private let authenticationManager: AppsTorrentAuthenticationManager
    private let downloadDestinationStore: DownloadDestinationStore
    private let pendingUpdateStore: PendingUpdateStore
    private let installationMonitor: ApplicationInstallationMonitor
    private var externalInstallationWatchTasks: [ApplicationIdentity: Task<Void, Never>] = [:]

    init(
        scanner: any ApplicationScanning = ApplicationScanner(),
        updateCoordinator: any ApplicationUpdateCoordinating = ApplicationUpdateCoordinator(
            checker: UpdateChecker(sources: [AppsTorrentSource()])
        ),
        downloadManager: any DownloadManaging = DownloadManager(),
        artifactInspector: any UpdateArtifactInspecting = UpdateArtifactInspector(),
        applicationInstaller: (any ApplicationInstalling)? = nil,
        authenticationManager: AppsTorrentAuthenticationManager? = nil,
        downloadDestinationStore: DownloadDestinationStore? = nil,
        pendingUpdateStore: PendingUpdateStore? = nil,
        installationMonitor: ApplicationInstallationMonitor = ApplicationInstallationMonitor()
    ) {
        self.scanner = scanner
        self.updateCoordinator = updateCoordinator
        self.downloadManager = downloadManager
        self.artifactInspector = artifactInspector
        self.applicationInstaller = applicationInstaller ?? ApplicationInstaller(
            destinationStore: InstallDestinationStore()
        )
        self.authenticationManager = authenticationManager ?? AppsTorrentAuthenticationManager()
        self.downloadDestinationStore = downloadDestinationStore ?? DownloadDestinationStore()
        self.pendingUpdateStore = pendingUpdateStore ?? PendingUpdateStore()
        self.installationMonitor = installationMonitor
        self.appsTorrentConnection = UpdateSourceConnection(
            id: "appstorrent",
            name: "AppsTorrent",
            state: self.authenticationManager.isLoginCompleted ? .connected : .signInRequired
        )
        self.downloadDirectoryURL = self.downloadDestinationStore.savedDirectory() ?? Self.defaultDownloadDirectory()
    }

    deinit {
        for task in externalInstallationWatchTasks.values {
            task.cancel()
        }
    }

    var canCheckAppsTorrent: Bool { appsTorrentConnection.state == .connected }

    func canCheckApplication(_ application: InstalledApplication) -> Bool {
        canCheckAppsTorrent && !isCheckingUpdates
    }

    func load() async {
        guard !isScanning else { return }
        isScanning = true
        defer { isScanning = false }

        applications = await scanner.scan()
        updateStates = [:]
        downloadStates = [:]
        downloadDirectoryURL = downloadDestinationStore.savedDirectory() ?? Self.defaultDownloadDirectory()
        restorePendingUpdates()
        await refreshAppsTorrentConnection()
    }

    func refreshAppsTorrentConnection() async {
        appsTorrentConnection = UpdateSourceConnection(id: "appstorrent", name: "AppsTorrent", state: .checking)
        let isConnected = await authenticationManager.refreshLoginState()
        appsTorrentConnection = UpdateSourceConnection(
            id: "appstorrent",
            name: "AppsTorrent",
            state: isConnected ? .connected : .signInRequired
        )
    }

    func checkForUpdates() async {
        guard canCheckAppsTorrent, !isCheckingUpdates, !applications.isEmpty else { return }
        isCheckingUpdates = true
        defer { isCheckingUpdates = false }

        updateStates = Dictionary(uniqueKeysWithValues: applications.map { ($0.id, .checking) })
        applyUpdateResults(await updateCoordinator.checkForUpdates(for: applications))
    }

    func checkForUpdate(for application: InstalledApplication) async {
        guard canCheckAppsTorrent, !isCheckingUpdates else { return }
        isCheckingUpdates = true
        updateStates[application.id] = .checking
        defer { isCheckingUpdates = false }

        let results = await updateCoordinator.checkForUpdates(for: [application])
        if let status = results[application.id] {
            applyUpdateResult(status, for: application)
        } else {
            updateStates[application.id] = .unavailable
            restorePendingUpdate(for: application)
        }
    }

    func markAppsTorrentLoginCompleted() {
        authenticationManager.markLoginCompleted()
        appsTorrentConnection = UpdateSourceConnection(id: "appstorrent", name: "AppsTorrent", state: .connected)
    }

    func logoutAppsTorrent() async {
        await authenticationManager.logout()
        appsTorrentConnection = UpdateSourceConnection(id: "appstorrent", name: "AppsTorrent", state: .signInRequired)
        updateStates = [:]
        downloadStates = [:]
    }

    func downloadUpdate(for application: InstalledApplication) async {
        guard canCheckAppsTorrent,
              case .updateAvailable(let candidate)? = updateStates[application.id] else { return }

        guard let option = candidate.downloadOptions.first(where: { $0.kind == .direct }) else {
            downloadStates[application.id] = .failed("A direct download is not available for this update.")
            return
        }

        let destinationDirectory: URL
        if let savedDirectory = downloadDestinationStore.savedDirectory() {
            destinationDirectory = savedDirectory
        } else if let selectedDirectory = await chooseDownloadDirectoryForFirstUse() {
            downloadDestinationStore.save(directory: selectedDirectory)
            destinationDirectory = selectedDirectory
            downloadDirectoryURL = selectedDirectory
        } else {
            downloadStates[application.id] = .failed("Luma needs access to a folder where it can save the update.")
            return
        }

        guard destinationDirectory.startAccessingSecurityScopedResource() else {
            downloadDestinationStore.clear()
            downloadDirectoryURL = Self.defaultDownloadDirectory()
            downloadStates[application.id] = .failed("Luma could not access the saved download folder. Choose another folder in Settings.")
            return
        }
        defer { destinationDirectory.stopAccessingSecurityScopedResource() }

        let cookies = await authenticationManager.cookies(for: option.url)
        downloadStates[application.id] = .downloading(DownloadProgress(bytesWritten: 0, totalBytes: nil))

        do {
            let artifact = try await downloadManager.download(
                option,
                to: destinationDirectory,
                cookies: cookies
            ) { [weak self] progress in
                Task { @MainActor [weak self] in
                    self?.downloadStates[application.id] = .downloading(progress)
                }
            }

            let preparedUpdate = PreparedUpdate(
                application: application.id,
                version: candidate.version,
                artifactURL: artifact.fileURL,
                payload: .externalInstaller(artifact.fileURL)
            )
            pendingUpdateStore.save(
                PendingExternalUpdate(
                    bundleIdentifier: application.id.bundleIdentifier,
                    version: candidate.version.rawValue,
                    fileURL: artifact.fileURL
                )
            )
            downloadStates[application.id] = .readyToInstall(preparedUpdate)
        } catch is CancellationError {
            downloadStates[application.id] = .notStarted
        } catch let error as DownloadManager.DownloadError where error == .cancelled {
            downloadStates[application.id] = .notStarted
        } catch {
            downloadStates[application.id] = .failed(error.localizedDescription)
        }
    }

    func cancelDownload(for application: InstalledApplication) {
        guard case .downloading = downloadStates[application.id],
              case .updateAvailable(let candidate)? = updateStates[application.id],
              let option = candidate.downloadOptions.first(where: { $0.kind == .direct }) else {
            return
        }

        downloadManager.cancelDownload(for: option.url)
        downloadStates[application.id] = .notStarted
    }

    func installUpdate(for application: InstalledApplication) async {
        guard case .readyToInstall(let preparedUpdate)? = downloadStates[application.id] else { return }
        downloadStates[application.id] = .installing(preparedUpdate.version)

        do {
            let fileAccess = pendingUpdateStore.beginFileAccess(for: application.id)
            let installerUpdate = fileAccess.map { preparedUpdate.replacingArtifactURL(with: $0.url) } ?? preparedUpdate
            defer { fileAccess?.stop() }

            let result = try await applicationInstaller.install(installerUpdate, replacing: application)
            switch result {
            case .completed:
                applications = await scanner.scan()
                pendingUpdateStore.remove(for: application.id)
                updateStates[application.id] = .upToDate
                downloadStates[application.id] = .installed(preparedUpdate.version)
            case .userActionRequired:
                pendingUpdateStore.markInstallerOpened(for: application.id)
                downloadStates[application.id] = .awaitingUserInstallation(preparedUpdate.version)
                startExternalInstallationWatch(
                    for: application,
                    expectedVersion: preparedUpdate.version
                )
            }
        } catch {
            downloadStates[application.id] = .failed(error.localizedDescription)
        }
    }

    func reopenInstaller(for application: InstalledApplication) async {
        guard case .awaitingUserInstallation(let version)? = downloadStates[application.id],
              let pending = pendingUpdateStore.pending(for: application.id),
              let resolvedURL = pendingUpdateStore.resolvedFileURL(for: application.id),
              FileManager.default.fileExists(atPath: resolvedURL.path) else {
            return
        }

        let preparedUpdate = PreparedUpdate(
            application: application.id,
            version: version,
            artifactURL: resolvedURL,
            payload: .externalInstaller(resolvedURL)
        )

        do {
            pendingUpdateStore.markInstallerOpened(for: application.id)
            let fileAccess = pendingUpdateStore.beginFileAccess(for: application.id)
            let installerUpdate = fileAccess.map { preparedUpdate.replacingArtifactURL(with: $0.url) } ?? preparedUpdate
            defer { fileAccess?.stop() }

            downloadStates[application.id] = .installing(version)
            let result = try await applicationInstaller.install(installerUpdate, replacing: application)
            switch result {
            case .completed, .userActionRequired:
                downloadStates[application.id] = .awaitingUserInstallation(version)
                startExternalInstallationWatch(for: application, expectedVersion: version)
            }
        } catch {
            downloadStates[application.id] = .failed(error.localizedDescription)
        }
    }

    func chooseDownloadDirectoryForFutureUpdates() async {
        guard let selectedDirectory = await chooseDownloadDirectory() else { return }
        downloadDestinationStore.save(directory: selectedDirectory)
        downloadDirectoryURL = downloadDestinationStore.savedDirectory() ?? selectedDirectory
    }

    func showDownloadedFile(for application: InstalledApplication) {
        guard case .readyToInstall(let preparedUpdate)? = downloadStates[application.id] else { return }
        let fileAccess = pendingUpdateStore.beginFileAccess(for: application.id)
        NSWorkspace.shared.activateFileViewerSelecting([fileAccess?.url ?? preparedUpdate.artifactURL])
        fileAccess?.stop()
    }

    private func applyUpdateResults(_ results: [ApplicationIdentity: UpdateStatus]) {
        for application in applications {
            guard let status = results[application.id] else {
                updateStates[application.id] = .unavailable
                restorePendingUpdate(for: application)
                continue
            }
            applyUpdateResult(status, for: application)
        }
    }

    private func applyUpdateResult(_ status: UpdateStatus, for application: InstalledApplication) {
        switch status {
        case .updateAvailable(let candidate):
            updateStates[application.id] = .updateAvailable(candidate)
            if let pending = pendingUpdateStore.pending(for: application.id),
               pending.version == candidate.version.rawValue,
               let resolvedURL = pendingUpdateStore.resolvedFileURL(for: application.id),
               FileManager.default.fileExists(atPath: resolvedURL.path) {
                downloadStates[application.id] = preparedUpdateState(from: pending, fileURL: resolvedURL, for: application)
            } else {
                if pendingUpdateStore.pending(for: application.id) != nil {
                    pendingUpdateStore.remove(for: application.id)
                }
                downloadStates[application.id] = .notStarted
            }
        case .upToDate:
            cancelExternalInstallationWatch(for: application.id)
            pendingUpdateStore.remove(for: application.id)
            updateStates[application.id] = .upToDate
            downloadStates[application.id] = nil
        case .unavailable:
            updateStates[application.id] = .unavailable
            restorePendingUpdate(for: application)
        }
    }

    private func restorePendingUpdates() {
        for application in applications {
            restorePendingUpdate(for: application)
        }
    }

    private func restorePendingUpdate(for application: InstalledApplication) {
        guard let pending = pendingUpdateStore.pending(for: application.id),
              let resolvedURL = pendingUpdateStore.resolvedFileURL(for: application.id) else {
            return
        }

        guard FileManager.default.fileExists(atPath: resolvedURL.path) else {
            pendingUpdateStore.remove(for: application.id)
            downloadStates[application.id] = nil
            return
        }

        let pendingVersion = SoftwareVersion(pending.version)
        if let installedVersion = BundleApplicationVersionProvider().installedVersion(for: application),
           VersionComparator().compare(installedVersion, pendingVersion) != .orderedAscending {
            pendingUpdateStore.remove(for: application.id)
            downloadStates[application.id] = nil
            return
        }

        if pending.installerOpened {
            downloadStates[application.id] = .awaitingUserInstallation(pendingVersion)
            startExternalInstallationWatch(for: application, expectedVersion: pendingVersion)
        } else {
            downloadStates[application.id] = preparedUpdateState(from: pending, fileURL: resolvedURL, for: application)
        }
    }

    private func preparedUpdateState(
        from pending: PendingExternalUpdate,
        fileURL: URL,
        for application: InstalledApplication
    ) -> ApplicationDownloadState {
        .readyToInstall(
            PreparedUpdate(
                application: application.id,
                version: SoftwareVersion(pending.version),
                artifactURL: fileURL,
                payload: .externalInstaller(fileURL)
            )
        )
    }

    private func startExternalInstallationWatch(
        for application: InstalledApplication,
        expectedVersion: SoftwareVersion
    ) {
        cancelExternalInstallationWatch(for: application.id)

        let applicationID = application.id
        externalInstallationWatchTasks[applicationID] = Task { [weak self] in
            guard let self else { return }

            let completed = await installationMonitor.waitForInstallation(
                of: application,
                expectedVersion: expectedVersion
            )
            guard !Task.isCancelled, completed else {
                self.externalInstallationWatchTasks[applicationID] = nil
                return
            }

            self.applications = await self.scanner.scan()
            self.pendingUpdateStore.remove(for: applicationID)
            self.updateStates[applicationID] = .upToDate
            self.downloadStates[applicationID] = .installed(expectedVersion)
            self.externalInstallationWatchTasks[applicationID] = nil
        }
    }

    private func cancelExternalInstallationWatch(for applicationID: ApplicationIdentity) {
        externalInstallationWatchTasks[applicationID]?.cancel()
        externalInstallationWatchTasks[applicationID] = nil
    }

    private func chooseDownloadDirectoryForFirstUse() async -> URL? {
        await withCheckedContinuation { continuation in
            let panel = NSOpenPanel()
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.allowsMultipleSelection = false
            panel.canCreateDirectories = true
            panel.directoryURL = Self.defaultDownloadDirectory()
            panel.prompt = "Allow Access"
            panel.message = "Choose where Luma should save updates. Downloads is selected by default."
            panel.begin { response in continuation.resume(returning: response == .OK ? panel.url : nil) }
        }
    }

    private func chooseDownloadDirectory() async -> URL? {
        await withCheckedContinuation { continuation in
            let panel = NSOpenPanel()
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.allowsMultipleSelection = false
            panel.canCreateDirectories = true
            panel.prompt = "Choose"
            panel.message = "Choose where Luma should save updates."
            panel.begin { response in continuation.resume(returning: response == .OK ? panel.url : nil) }
        }
    }

    private static func defaultDownloadDirectory() -> URL? {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
    }
}
