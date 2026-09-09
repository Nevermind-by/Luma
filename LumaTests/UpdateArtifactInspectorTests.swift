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

        let appURL = try makeFixtureApplication(in: root, version: "2.0.0")
        let archiveURL = try makeZipArchive(for: appURL, in: root)
        let artifact = makeArtifact(for: archiveURL)

        let prepared = try await UpdateArtifactInspector().inspect(
            artifact: artifact,
            expectedApplication: ApplicationIdentity(bundleIdentifier: "com.example.fixture"),
            expectedVersion: SoftwareVersion("2.0.0")
        )

        #expect(prepared.bundleIdentifier == "com.example.fixture")
        #expect(prepared.version == SoftwareVersion("2.0.0"))
        guard case .application(let preparedApplicationURL) = prepared.payload else {
            Issue.record("Expected an application payload")
            return
        }
        #expect(fileManager.fileExists(atPath: preparedApplicationURL.path))
    }

    @Test
    func rejectsVersionMismatch() async throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent("LumaInspectorTest-\(UUID().uuidString)")
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }

        let appURL = try makeFixtureApplication(in: root, version: "2.0.0")
        let archiveURL = try makeZipArchive(for: appURL, in: root)
        let artifact = makeArtifact(for: archiveURL)

        do {
            _ = try await UpdateArtifactInspector().inspect(
                artifact: artifact,
                expectedApplication: ApplicationIdentity(bundleIdentifier: "com.example.fixture"),
                expectedVersion: SoftwareVersion("3.0.0")
            )
            Issue.record("Expected version mismatch")
        } catch let error as UpdateArtifactInspector.InspectionError {
            #expect(error == .versionMismatch(expected: "3.0.0", actual: "2.0.0"))
        }
    }

    @Test
    func acceptsDiskImagePayloadWithoutTryingToMountIt() async throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent("LumaInspectorTest-\(UUID().uuidString)")
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }

        let dmgURL = root.appendingPathComponent("Fixture.dmg")
        try Data([0x00, 0x01, 0x02, 0x03]).write(to: dmgURL)
        let artifact = DownloadedArtifact(
            originalURL: URL(string: "https://example.com/update")!,
            finalURL: URL(string: "https://example.com/Fixture.dmg")!,
            fileURL: dmgURL,
            filename: dmgURL.lastPathComponent,
            mimeType: "application/x-apple-diskimage",
            byteCount: 4
        )

        let prepared = try await UpdateArtifactInspector().inspect(
            artifact: artifact,
            expectedApplication: ApplicationIdentity(bundleIdentifier: "com.example.fixture"),
            expectedVersion: SoftwareVersion("2.0.0")
        )

        #expect(prepared.payload == .diskImage(dmgURL))
        #expect(!prepared.isApplicationBundle)
    }

    private func makeFixtureApplication(in root: URL, version: String) throws -> URL {
        let appURL = root.appendingPathComponent("Fixture.app", isDirectory: true)
        try FileManager.default.createDirectory(
            at: appURL.appendingPathComponent("Contents", isDirectory: true),
            withIntermediateDirectories: true
        )

        let info: [String: Any] = [
            "CFBundleIdentifier": "com.example.fixture",
            "CFBundleShortVersionString": version,
            "CFBundleVersion": "200"
        ]
        let plistURL = appURL.appendingPathComponent("Contents/Info.plist")
        try PropertyListSerialization.data(fromPropertyList: info, format: .binary, options: 0).write(to: plistURL)
        return appURL
    }

    private func makeZipArchive(for appURL: URL, in root: URL) throws -> URL {
        let archiveURL = root.appendingPathComponent("Fixture.zip")
        try runProcess(
            executable: "/usr/bin/ditto",
            arguments: ["-c", "-k", "--sequesterRsrc", "--keepParent", appURL.path, archiveURL.path]
        )
        return archiveURL
    }

    private func makeArtifact(for fileURL: URL) -> DownloadedArtifact {
        let byteCount = Int64((try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        return DownloadedArtifact(
            originalURL: URL(string: "https://example.com/update")!,
            finalURL: URL(string: "https://example.com/Fixture.zip")!,
            fileURL: fileURL,
            filename: fileURL.lastPathComponent,
            mimeType: "application/zip",
            byteCount: byteCount
        )
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
