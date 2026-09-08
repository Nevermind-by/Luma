import Combine
import Foundation

@MainActor
final class ApplicationLibraryViewModel: ObservableObject {
    @Published private(set) var applications: [InstalledApplication] = []
    @Published private(set) var isScanning = false

    private let scanner: any ApplicationScanning

    init(scanner: any ApplicationScanning = ApplicationScanner()) {
        self.scanner = scanner
    }

    func load() async {
        guard !isScanning else { return }

        isScanning = true
        defer { isScanning = false }

        applications = await scanner.scan()
    }
}
