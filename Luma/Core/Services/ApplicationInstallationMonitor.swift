import Foundation

protocol InstalledApplicationVersionProviding: Sendable {
    func installedVersion(for application: InstalledApplication) -> SoftwareVersion?
}

struct BundleApplicationVersionProvider: InstalledApplicationVersionProviding {
    func installedVersion(for application: InstalledApplication) -> SoftwareVersion? {
        guard let bundle = Bundle(url: application.bundleURL),
              bundle.bundleIdentifier == application.id.bundleIdentifier,
              let value = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
              !value.isEmpty else {
            return nil
        }

        return SoftwareVersion(value)
    }
}

struct ApplicationInstallationMonitor: Sendable {
    private let versionProvider: any InstalledApplicationVersionProviding
    private let pollInterval: Duration
    private let maxAttempts: Int

    init(
        versionProvider: any InstalledApplicationVersionProviding = BundleApplicationVersionProvider(),
        pollInterval: Duration = .seconds(2),
        maxAttempts: Int = 300
    ) {
        self.versionProvider = versionProvider
        self.pollInterval = pollInterval
        self.maxAttempts = maxAttempts
    }

    func waitForInstallation(
        of application: InstalledApplication,
        expectedVersion: SoftwareVersion
    ) async -> Bool {
        guard maxAttempts > 0 else { return false }

        for attempt in 0..<maxAttempts {
            if Task.isCancelled { return false }

            if let installedVersion = versionProvider.installedVersion(for: application),
               VersionComparator().compare(installedVersion, expectedVersion) != .orderedAscending {
                return true
            }

            if attempt + 1 < maxAttempts {
                do {
                    try await Task.sleep(for: pollInterval)
                } catch {
                    return false
                }
            }
        }

        return false
    }
}
