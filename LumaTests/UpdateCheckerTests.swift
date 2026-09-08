import Foundation
import Testing
@testable import Luma

struct UpdateCheckerTests {
    @Test func reportsUpdateAvailableWhenSourceHasNewerVersion() async {
        let application = makeApplication(version: "1.2.0")
        let source = MockUpdateSource(result: .success(makeCandidate(version: "1.3.0")))
        let checker = UpdateChecker(sources: [source])

        let status = await checker.check(for: application)

        switch status {
        case .updateAvailable(let candidate):
            #expect(candidate.version == SoftwareVersion("1.3.0"))
        default:
            Issue.record("Expected an available update")
        }
    }

    @Test func reportsUpToDateWhenSourceVersionIsNotNewer() async {
        let application = makeApplication(version: "1.3.0")
        let source = MockUpdateSource(result: .success(makeCandidate(version: "1.3.0")))
        let checker = UpdateChecker(sources: [source])

        let status = await checker.check(for: application)

        #expect(status == .upToDate)
    }

    @Test func selectsHighestVersionFromMultipleSources() async {
        let application = makeApplication(version: "1.0.0")
        let first = MockUpdateSource(result: .success(makeCandidate(version: "1.4.0")))
        let second = MockUpdateSource(result: .success(makeCandidate(version: "1.6.0")))
        let checker = UpdateChecker(sources: [first, second])

        let status = await checker.check(for: application)

        switch status {
        case .updateAvailable(let candidate):
            #expect(candidate.version == SoftwareVersion("1.6.0"))
        default:
            Issue.record("Expected the highest available update")
        }
    }

    @Test func ignoresUnavailableSourceWhenAnotherSourceSucceeds() async {
        let application = makeApplication(version: "1.0.0")
        let failing = MockUpdateSource(result: .failure(TestError.failed))
        let working = MockUpdateSource(result: .success(makeCandidate(version: "1.1.0")))
        let checker = UpdateChecker(sources: [failing, working])

        let status = await checker.check(for: application)

        switch status {
        case .updateAvailable(let candidate):
            #expect(candidate.version == SoftwareVersion("1.1.0"))
        default:
            Issue.record("Expected the working source to provide the result")
        }
    }

    @Test func reportsUnavailableWhenEverySourceFails() async {
        let application = makeApplication(version: "1.0.0")
        let first = MockUpdateSource(result: .failure(TestError.failed))
        let second = MockUpdateSource(result: .failure(TestError.failed))
        let checker = UpdateChecker(sources: [first, second])

        let status = await checker.check(for: application)

        #expect(status == .unavailable)
    }

    private func makeApplication(version: String) -> InstalledApplication {
        InstalledApplication(
            id: ApplicationIdentity(bundleIdentifier: "com.example.test"),
            name: "Test App",
            version: SoftwareVersion(version),
            bundleURL: URL(fileURLWithPath: "/Applications/Test App.app")
        )
    }

    private func makeCandidate(version: String) -> UpdateCandidate {
        UpdateCandidate(
            application: ApplicationIdentity(bundleIdentifier: "com.example.test"),
            version: SoftwareVersion(version),
            downloadOptions: []
        )
    }

    private struct MockUpdateSource: UpdateSource {
        let result: Result<UpdateCandidate?, any Error>

        var name: String { "Mock" }

        func checkForUpdate(for application: InstalledApplication) async throws -> UpdateCandidate? {
            try result.get()
        }
    }

    private enum TestError: Error {
        case failed
    }
}
