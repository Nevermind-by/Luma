import Foundation
import Testing
@testable import Luma

struct UpdateArtifactInspectorTests {
    @Test
    func inspectsZipAndValidatesApplicationIdentityAndVersion() async throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent("LumaInspectorTest-\(UUID().uuidString)")
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }

        let appURL = root.appendingPathComponent("Fixture.app", isDirectory: true)
        try fileManager.createDirectory(
            at: appURL.appendingPathComponent("Contents", isDirectory: true),
            withIntermediateDirectories: true
        )

        let info: [String: Any] = [
            "CFBundleIdentifier": "com.example.fixture",
            "CFBundleShortVersionString": "2.0.0",
            "CFBundleVersion": "200"
        ]
        let plistURL = appURL.appendingPathComponent("Contents/Info.plist")
        try PropertyListSerialization.data(
            fromPropertyList: info,
            format: .binary,
            options: 0
        ).write(to: plistURL)

        let archiveURL = root.appendingPathComponent("Fixture.zip")
        try runProcess(
            executable: "/usr/bin/ditto",
            arguments: ["-c", "-k", "--sequesterRsrc", "--keepParent", appURL.path, archiveURL.path]
        )

        let prepared = try await UpdateArtifactInspector().inspect(
            artifactURL: archiveURL,
            expectedApplication: ApplicationIdentity(bundleIdentifier: "com.example.fixture"),
            expectedVersion: SoftwareVersion("2.0.0")
        )

        #expect(prepared.bundleIdentifier == "com.example.fixture")
        #expect(prepared.version == SoftwareVersion("2.0.0"))
        #expect(fileManager.fileExists(atPath: prepared.applicationURL.path))
    }

    @Test
    func rejectsVersionMismatch() async throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent("LumaInspectorTest-\(UUID().uuidString)")
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }

        let appURL = root.appendingPathComponent("Fixture.app", isDirectory: true)
        try fileManager.createDirectory(
            at: appURL.appendingPathComponent("Contents", isDirectory: true),
            withIntermediateDirectories: true
        )

        let info: [String: Any] = [
            "CFBundleIdentifier": "com.example.fixture",
            "CFBundleShortVersionString": "2.0.0",
            "CFBundleVersion": "200"
        ]
        let plistURL = appURL.appendingPathComponent("Contents/Info.plist")
        try PropertyListSerialization.data(
            fromPropertyList: info,
            format: .binary,
            options: 0
        ).write(to: plistURL)

        let archiveURL = root.appendingPathComponent("Fixture.zip")
        try runProcess(
            executable: "/usr/bin/ditto",
            arguments: ["-c", "-k", "--sequesterRsrc", "--keepParent", appURL.path, archiveURL.path]
        )

        await #expect(throws: UpdateArtifactInspector.InspectionError.versionMismatch(
            expected: "3.0.0",
            actual: "2.0.0"
        )) {
            try await UpdateArtifactInspector().inspect(
                artifactURL: archiveURL,
                expectedApplication: ApplicationIdentity(bundleIdentifier: "com.example.fixture"),
                expectedVersion: SoftwareVersion("3.0.0")
            )
        }
    }

    private func runProcess(executable: String, arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
    }
}
