import Foundation

protocol ApplicationScanning: Sendable {
    func scan() async -> [InstalledApplication]
}

struct ApplicationScanner: ApplicationScanning {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func scan() async -> [InstalledApplication] {
        let directories = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true)
        ]

        return directories
            .flatMap(scanDirectory)
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func scanDirectory(_ directory: URL) -> [InstalledApplication] {
        guard let contents = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return contents
            .filter { $0.pathExtension == "app" }
            .compactMap(readApplication)
    }

    private func readApplication(from url: URL) -> InstalledApplication? {
        guard
            let bundle = Bundle(url: url),
            let bundleIdentifier = bundle.bundleIdentifier,
            let name = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String,
            let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
            !version.isEmpty
        else {
            return nil
        }

        return InstalledApplication(
            id: ApplicationIdentity(bundleIdentifier: bundleIdentifier),
            name: name,
            version: SoftwareVersion(version),
            bundleURL: url
        )
    }
}
