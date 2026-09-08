import Combine
import Foundation

@MainActor
final class ApplicationLibraryViewModel: ObservableObject {
    @Published private(set) var applications: [InstalledApplication] = []
    @Published private(set) var updateStates: [ApplicationIdentity: ApplicationUpdateState] = [:]
    @Published private(set) var isScanning = false
    @Published private(set) var isCheckingUpdates = false

    private let scanner: any ApplicationScanning
    private let updateCoordinator: any ApplicationUpdateCoordinating

    init(
        scanner: any ApplicationScanning = ApplicationScanner(),
        updateCoordinator: any ApplicationUpdateCoordinating = ApplicationUpdateCoordinator(
            checker: UpdateChecker(
                sources: [AppsTorrentSource()]
            )
        )
    ) {
        self.scanner = scanner
        self.updateCoordinator = updateCoordinator
    }

    func load() async {
        guard !isScanning else { return }

        isScanning = true
        defer { isScanning = false }

        applications = await scanner.scan()
        updateStates = [:]
    }

    func checkForUpdates() async {
        guard !isCheckingUpdates, !applications.isEmpty else { return }

        isCheckingUpdates = true
        defer { isCheckingUpdates = false }

        updateStates = Dictionary(
            uniqueKeysWithValues: applications.map {
                ($0.id, .checking)
            }
        )

        let results = await updateCoordinator.checkForUpdates(for: applications)

        for application in applications {
            guard let status = results[application.id] else {
                updateStates[application.id] = .unavailable
                continue
            }

            switch status {
            case .updateAvailable(let candidate):
                updateStates[application.id] = .updateAvailable(candidate)
            case .upToDate:
                updateStates[application.id] = .upToDate
            case .unavailable:
                updateStates[application.id] = .unavailable
            }
        }
    }
}
