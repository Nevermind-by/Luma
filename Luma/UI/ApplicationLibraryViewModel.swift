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

    private let scanner: any ApplicationScanning
    private let updateCoordinator: any ApplicationUpdateCoordinating
    private let downloadManager: any DownloadManaging
    private let authenticationManager: AppsTorrentAuthenticationManager

    init(
        scanner: any ApplicationScanning = ApplicationScanner(),
        updateCoordinator: any ApplicationUpdateCoordinating = ApplicationUpdateCoordinator(
            checker: UpdateChecker(
                sources: [AppsTorrentSource()]
            )
        ),
        downloadManager: any DownloadManaging = DownloadManager(),
        authenticationManager: AppsTorrentAuthenticationManager? = nil
    ) {
        self.scanner = scanner
        self.updateCoordinator = updateCoordinator
        self.downloadManager = downloadManager
        self.authenticationManager = authenticationManager ?? AppsTorrentAuthenticationManager()
        self.appsTorrentConnection = UpdateSourceConnection(
            id: "appstorrent",
            name: "AppsTorrent",
            state: self.authenticationManager.isLoginCompleted ? .connected : .signInRequired
        )
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

        guard let destinationDirectory = await chooseDownloadDirectory() else {
            return
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

            downloadStates[application.id] = .completed(destinationURL)
        } catch {
            downloadStates[application.id] = .failed(error.localizedDescription)
        }
    }

    func showDownloadedFile(for application: InstalledApplication) {
        guard case .completed(let url)? = downloadStates[application.id] else {
            return
        }

        NSWorkspace.shared.activateFileViewerSelecting([url])
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
            panel.message = "Choose where Luma should save the update."
            panel.begin { response in
                continuation.resume(returning: response == .OK ? panel.url : nil)
            }
        }
    }
}
