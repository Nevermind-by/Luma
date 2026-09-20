import Foundation
import Testing
@testable import Luma

@MainActor
struct ApplicationInstallerTests {
    @Test
    func acceptsInstalledApplicationWithExpectedIdentityVersionAndValidSignature() throws {
        let root = try makeFixtureRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let appURL = try makeFixtureApplication(in: root, bundleIdentifier: "com.example.fixture", version: "2.0.0")
        let expected = PreparedUpdate(
            application: ApplicationIdentity(bundleIdentifier: "com.example.fixture"),
            version: SoftwareVersion("2.0.0"),
            artifactURL: appURL,
            payload: .application(appURL),
            bundleIdentifier: "com.example.fixture"
        )

        let installer = makeInstaller(signatureIsValid: true)

        #expect(installer.verifyInstalledApplication(at: appURL, expected: expected))
    }

    @Test
    func rejectsInstalledApplicationWithInvalidCodeSignature() throws {
        let root = try makeFixtureRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let appURL = try makeFixtureApplication(in: root, bundleIdentifier: "com.example.fixture", version: "2.0.0")
        let expected = PreparedUpdate(
            application: ApplicationIdentity(bundleIdentifier: "com.example.fixture"),
            version: SoftwareVersion("2.0.0"),
            artifactURL: appURL,
            payload: .application(appURL),
            bundleIdentifier: "com.example.fixture"
        )

        let installer = makeInstaller(signatureIsValid: false)

        #expect(!installer.verifyInstalledApplication(at: appURL, expected: expected))
    }

    @Test
    func rejectsInstalledApplicationWithUnexpectedIdentityOrVersion() throws {
        let root = try makeFixtureRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let appURL = try makeFixtureApplication(in: root, bundleIdentifier: "com.example.other", version: "3.0.0")

        let expected = PreparedUpdate(
            application: ApplicationIdentity(bundleIdentifier: "com.example.fixture"),
            version: SoftwareVersion("2.0.0"),
            artifactURL: appURL,
            payload: .application(appURL),
            bundleIdentifier: "com.example.fixture"
        )

        let installer = makeInstaller(signatureIsValid: true)

        #expect(!installer.verifyInstalledApplication(at: appURL, expected: expected))
    }

    private func makeInstaller(signatureIsValid: Bool) -> ApplicationInstaller {
        let suiteName = "LumaTests.ApplicationInstaller.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        return ApplicationInstaller(
            destinationStore: InstallDestinationStore(defaults: defaults),
            codeSignatureVerifier: StubCodeSignatureVerifier(isValid: signatureIsValid)
        )
    }

    private func makeFixtureRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("LumaApplicationInstallerTest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func makeFixtureApplication(
        in root: URL,
        bundleIdentifier: String,
        version: String
    ) throws -> URL {
        let appURL = root.appendingPathComponent("Fixture.app", isDirectory: true)
        let contentsURL = appURL.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contentsURL, withIntermediateDirectories: true)

        let info: [String: Any] = [
            "CFBundleIdentifier": bundleIdentifier,
            "CFBundleShortVersionString": version,
            "CFBundleVersion": "200"
        ]

        let plistURL = contentsURL.appendingPathComponent("Info.plist")
        let data = try PropertyListSerialization.data(
            fromPropertyList: info,
            format: .binary,
            options: 0
        )
        try data.write(to: plistURL)

        return appURL
    }
}

private struct StubCodeSignatureVerifier: CodeSignatureVerifying {
    let isValid: Bool

    func verifyApplication(at url: URL) -> Bool {
        _ = url
        return isValid
    }
}
