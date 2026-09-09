import Foundation
import Testing
@testable import Luma

struct ApplicationInstallationMonitorTests {
    @Test
    func completesWhenInstalledVersionReachesExpectedVersion() async {
        let application = fixtureApplication()
        let expectedVersion = SoftwareVersion("27.0.1")
        let provider = FixedVersionProvider(version: expectedVersion)
        let monitor = ApplicationInstallationMonitor(
            versionProvider: provider,
            pollInterval: .milliseconds(0),
            maxAttempts: 1
        )

        let completed = await monitor.waitForInstallation(
            of: application,
            expectedVersion: expectedVersion
        )

        #expect(completed)
    }

    @Test
    func doesNotCompleteForOlderInstalledVersion() async {
        let application = fixtureApplication()
        let provider = FixedVersionProvider(version: SoftwareVersion("27.0.0"))
        let monitor = ApplicationInstallationMonitor(
            versionProvider: provider,
            pollInterval: .milliseconds(0),
            maxAttempts: 1
        )

        let completed = await monitor.waitForInstallation(
            of: application,
            expectedVersion: SoftwareVersion("27.0.1")
        )

        #expect(!completed)
    }

    @Test
    func acceptsNewerInstalledVersion() async {
        let application = fixtureApplication()
        let provider = FixedVersionProvider(version: SoftwareVersion("28.0.0"))
        let monitor = ApplicationInstallationMonitor(
            versionProvider: provider,
            pollInterval: .milliseconds(0),
            maxAttempts: 1
        )

        let completed = await monitor.waitForInstallation(
            of: application,
            expectedVersion: SoftwareVersion("27.0.1")
        )

        #expect(completed)
    }

    private func fixtureApplication() -> InstalledApplication {
        InstalledApplication(
            id: ApplicationIdentity(bundleIdentifier: "com.example.fixture"),
            name: "Fixture",
            version: SoftwareVersion("27.0.0"),
            bundleURL: URL(fileURLWithPath: "/tmp/Fixture.app")
        )
    }
}

private struct FixedVersionProvider: InstalledApplicationVersionProviding {
    let version: SoftwareVersion?

    func installedVersion(for application: InstalledApplication) -> SoftwareVersion? {
        version
    }
}
