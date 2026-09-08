import Foundation

nonisolated protocol ApplicationScanning {
    func scan() async -> [InstalledApplication]
}

nonisolated struct ApplicationScanner: ApplicationScanning {
    private let roots: [URL]

    init(
        roots: [URL] = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true)
        ]
    ) {
        self.roots = roots
    }

    func scan() async -> [InstalledApplication] {
        roots
            .flatMap(scanDirectory)
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func scanDirectory(_ directory: URL) -> [InstalledApplication] {
        let fileManager = FileManager.default

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
            !name.isEmpty,
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
