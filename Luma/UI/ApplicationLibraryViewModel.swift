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

    init(
        scanner: any ApplicationScanning = ApplicationScanner(),
        updateCoordinator: any ApplicationUpdateCoordinating = ApplicationUpdateCoordinator(
            checker: UpdateChecker(
                sources: [AppsTorrentSource()]
            )
        ),
        downloadManager: any DownloadManaging = DownloadManager(),
        artifactInspector: any UpdateArtifactInspecting = UpdateArtifactInspector(),
        applicationInstaller: (any ApplicationInstalling)? = nil,
        authenticationManager: AppsTorrentAuthenticationManager? = nil,
        downloadDestinationStore: DownloadDestinationStore = DownloadDestinationStore()
    ) {
        self.scanner = scanner
        self.updateCoordinator = updateCoordinator
        self.downloadManager = downloadManager
        self.artifactInspector = artifactInspector
        self.applicationInstaller = applicationInstaller ?? ApplicationInstaller(
            destinationStore: InstallDestinationStore()
        )
        self.authenticationManager = authenticationManager ?? AppsTorrentAuthenticationManager()
        self.downloadDestinationStore = downloadDestinationStore
        self.appsTorrentConnection = UpdateSourceConnection(
            id: "appstorrent",
            name: "AppsTorrent",
            state: self.authenticationManager.isLoginCompleted ? .connected : .signInRequired
        )
        self.downloadDirectoryURL = downloadDestinationStore.savedDirectory() ?? Self.defaultDownloadDirectory()
    }

    var canCheckAppsTorrent: Bool {
        appsTorrentConnection.state == .connected
    }

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
        await refreshAppsTorrentConnection()
    }

    func refreshAppsTorrentConnection() async {
        appsTorrentConnection = UpdateSourceConnection(
            id: "appstorrent",
            name: "AppsTorrent",
            state: .checking
        )

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

        updateStates = Dictionary(
            uniqueKeysWithValues: applications.map {
                ($0.id, .checking)
            }
        )

        let results = await updateCoordinator.checkForUpdates(for: applications)
        applyUpdateResults(results)
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
            downloadStates[application.id] = nil
        }
    }

    func markAppsTorrentLoginCompleted() {
        authenticationManager.markLoginCompleted()
        appsTorrentConnection = UpdateSourceConnection(
            id: "appstorrent",
            name: "AppsTorrent",
            state: .connected
        )
    }

    func logoutAppsTorrent() async {
        await authenticationManager.logout()
        appsTorrentConnection = UpdateSourceConnection(
            id: "appstorrent",
            name: "AppsTorrent",
            state: .signInRequired
        )
        updateStates = [:]
        downloadStates = [:]
    }

    func downloadUpdate(for application: InstalledApplication) async {
        guard canCheckAppsTorrent, case .updateAvailable(let candidate)? = updateStates[application.id] else {
            return
        }

        guard let option = candidate.downloadOptions.first(where: { $0.kind == .direct }) else {
            downloadStates[application.id] = .failed("A direct download is not available for this update.")
            return
        }

        let savedDirectory = downloadDestinationStore.savedDirectory()
        let destinationDirectory = savedDirectory ?? Self.defaultDownloadDirectory()

        guard let destinationDirectory else {
            downloadStates[application.id] = .failed("Luma could not find your Downloads folder. Choose another folder in Settings.")
            return
        }
        downloadDirectoryURL = destinationDirectory

        let requiresSecurityScope = savedDirectory != nil
        if requiresSecurityScope && !destinationDirectory.startAccessingSecurityScopedResource() {
            downloadDestinationStore.clear()
            downloadDirectoryURL = Self.defaultDownloadDirectory()
            downloadStates[application.id] = .failed("Luma could not access the saved download folder. Choose another folder in Settings.")
            return
        }
        defer {
            if requiresSecurityScope {
                destinationDirectory.stopAccessingSecurityScopedResource()
            }
        }

        let cookies = await authenticationManager.cookies(for: option.url)
        downloadStates[application.id] = .downloading(
            DownloadProgress(bytesWritten: 0, totalBytes: nil)
        )

        do {
            let destinationURL = try await downloadManager.download(
                option,
                to: destinationDirectory,
                cookies: cookies
            ) { [weak self] progress in
                Task { @MainActor [weak self] in
                    self?.downloadStates[application.id] = .downloading(progress)
                }
            }

            do {
                let preparedUpdate = try await artifactInspector.inspect(
                    artifactURL: destinationURL,
                    expectedApplication: application.id,
                    expectedVersion: candidate.version
                )
                downloadStates[application.id] = .readyToInstall(preparedUpdate)
            } catch {
                downloadStates[application.id] = .failed(error.localizedDescription)
            }
        } catch {
            downloadStates[application.id] = .failed(error.localizedDescription)
        }
    }

    func installUpdate(for application: InstalledApplication) async {
        guard case .readyToInstall(let preparedUpdate)? = downloadStates[application.id] else {
            return
        }

        downloadStates[application.id] = .installing(preparedUpdate.version)

        do {
            try await applicationInstaller.install(
                preparedUpdate,
                replacing: application
            )

            applications = await scanner.scan()
            updateStates[application.id] = .upToDate
            downloadStates[application.id] = .installed(preparedUpdate.version)
        } catch {
            downloadStates[application.id] = .failed(error.localizedDescription)
        }
    }

    func chooseDownloadDirectoryForFutureUpdates() async {
        guard let selectedDirectory = await chooseDownloadDirectory() else {
            return
        }

        downloadDestinationStore.save(directory: selectedDirectory)
        downloadDirectoryURL = downloadDestinationStore.savedDirectory() ?? selectedDirectory
    }

    func showDownloadedFile(for application: InstalledApplication) {
        guard let state = downloadStates[application.id] else { return }

        let url: URL?
        switch state {
        case .readyToInstall(let preparedUpdate):
            url = preparedUpdate.artifactURL
        default:
            url = nil
        }

        if let url {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    private func applyUpdateResults(
        _ results: [ApplicationIdentity: UpdateStatus]
    ) {
        for application in applications {
            guard let status = results[application.id] else {
                updateStates[application.id] = .unavailable
                continue
            }

            applyUpdateResult(status, for: application)
        }
    }

    private func applyUpdateResult(
        _ status: UpdateStatus,
        for application: InstalledApplication
    ) {
        switch status {
        case .updateAvailable(let candidate):
            updateStates[application.id] = .updateAvailable(candidate)
            downloadStates[application.id] = .notStarted
        case .upToDate:
            updateStates[application.id] = .upToDate
            downloadStates[application.id] = nil
        case .unavailable:
            updateStates[application.id] = .unavailable
            downloadStates[application.id] = nil
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
            panel.begin { response in
                continuation.resume(returning: response == .OK ? panel.url : nil)
            }
        }
    }

    private static func defaultDownloadDirectory() -> URL? {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
    }
}
