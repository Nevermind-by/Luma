import Foundation
import Testing
@testable import Luma

struct ApplicationUpdateCoordinatorTests {
    @Test func checksApplicationsAndReturnsStatusesByIdentity() async {
        let applications = [
            makeApplication(
                bundleIdentifier: "com.example.one",
                name: "One",
                version: "1.0"
            ),
            makeApplication(
                bundleIdentifier: "com.example.two",
                name: "Two",
                version: "2.0"
            )
        ]

        let checker = StubChecker(statuses: [
            "com.example.one": .upToDate,
            "com.example.two": .unavailable
        ])
        let coordinator = ApplicationUpdateCoordinator(
            checker: checker,
            maxConcurrentChecks: 2
        )

        let results = await coordinator.checkForUpdates(for: applications)

        #expect(results[applications[0].id] == .upToDate)
        #expect(results[applications[1].id] == .unavailable)
    }

    @Test func emptyApplicationListReturnsEmptyResults() async {
        let coordinator = ApplicationUpdateCoordinator(
            checker: StubChecker(statuses: [:])
        )

        let results = await coordinator.checkForUpdates(for: [])

        #expect(results.isEmpty)
    }

    @Test func respectsConfiguredConcurrencyLimit() async {
        let applications = (0..<8).map {
            makeApplication(
                bundleIdentifier: "com.example.\($0)",
                name: "App \($0)",
                version: "1.0"
            )
        }

        let checker = TrackingChecker()
        let coordinator = ApplicationUpdateCoordinator(
            checker: checker,
            maxConcurrentChecks: 2
        )

        _ = await coordinator.checkForUpdates(for: applications)

        #expect(await checker.maxObservedConcurrency() <= 2)
        #expect(await checker.totalChecks() == applications.count)
    }

    private func makeApplication(
        bundleIdentifier: String,
        name: String,
        version: String
    ) -> InstalledApplication {
        InstalledApplication(
            id: ApplicationIdentity(bundleIdentifier: bundleIdentifier),
            name: name,
            version: SoftwareVersion(version),
            bundleURL: URL(fileURLWithPath: "/Applications/\(name).app")
        )
    }

    private struct StubChecker: UpdateChecking {
        let statuses: [String: UpdateStatus]

        func check(for application: InstalledApplication) async -> UpdateStatus {
            statuses[application.id.bundleIdentifier] ?? .unavailable
        }
    }

    private actor TrackingChecker: UpdateChecking {
        private var activeChecks = 0
        private var maximumConcurrency = 0
        private var checks = 0

        func check(for application: InstalledApplication) async -> UpdateStatus {
            _ = application
            activeChecks += 1
            checks += 1
            maximumConcurrency = max(maximumConcurrency, activeChecks)
            try? await Task.sleep(for: .milliseconds(20))
            activeChecks -= 1
            return .upToDate
        }

        func maxObservedConcurrency() -> Int {
            maximumConcurrency
        }

        func totalChecks() -> Int {
            checks
        }
    }
}
