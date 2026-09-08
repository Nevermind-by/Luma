import Foundation
import Testing
@testable import Luma

struct ApplicationScannerTests {
    @Test func scansApplicationBundles() async throws {
        let fixtureRoot = try makeFixtureRoot()
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }

        try makeApplication(
            at: fixtureRoot,
            directoryName: "Zeta.app",
            name: "Zeta",
            bundleIdentifier: "com.example.zeta",
            version: "2.4.1"
        )

        let scanner = ApplicationScanner(roots: [fixtureRoot])
        let applications = await scanner.scan()

        #expect(applications.count == 1)
        #expect(applications.first?.name == "Zeta")
        #expect(applications.first?.version.rawValue == "2.4.1")
        #expect(applications.first?.id.bundleIdentifier == "com.example.zeta")
        #expect(applications.first?.bundleURL.lastPathComponent == "Zeta.app")
    }

    @Test func sortsApplicationsByDisplayName() async throws {
        let fixtureRoot = try makeFixtureRoot()
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }

        try makeApplication(
            at: fixtureRoot,
            directoryName: "Zeta.app",
            name: "Zeta",
            bundleIdentifier: "com.example.zeta",
            version: "1.0"
        )
        try makeApplication(
            at: fixtureRoot,
            directoryName: "Alpha.app",
            name: "Alpha",
            bundleIdentifier: "com.example.alpha",
            version: "1.0"
        )

        let scanner = ApplicationScanner(roots: [fixtureRoot])
        let applications = await scanner.scan()

        #expect(applications.map(\.name) == ["Alpha", "Zeta"])
    }

    @Test func ignoresBundlesWithoutRequiredMetadata() async throws {
        let fixtureRoot = try makeFixtureRoot()
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }

        try makeApplication(
            at: fixtureRoot,
            directoryName: "Valid.app",
            name: "Valid",
            bundleIdentifier: "com.example.valid",
            version: "1.0"
        )

        let invalidBundle = fixtureRoot.appendingPathComponent("Invalid.app")
            .appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: invalidBundle, withIntermediateDirectories: true)
        try Data("<?xml version=\"1.0\" encoding=\"UTF-8\"?><plist version=\"1.0\"><dict><key>CFBundleName</key><string>Invalid</string></dict></plist>".utf8)
            .write(to: invalidBundle.appendingPathComponent("Info.plist"))

        let scanner = ApplicationScanner(roots: [fixtureRoot])
        let applications = await scanner.scan()

        #expect(applications.map(\.name) == ["Valid"])
    }

    private func makeFixtureRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("LumaTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )

        return root
    }

    private func makeApplication(
        at root: URL,
        directoryName: String,
        name: String,
        bundleIdentifier: String,
        version: String
    ) throws {
        let contents = root
            .appendingPathComponent(directoryName, isDirectory: true)
            .appendingPathComponent("Contents", isDirectory: true)

        try FileManager.default.createDirectory(
            at: contents,
            withIntermediateDirectories: true
        )

        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>CFBundleIdentifier</key>
            <string>\(bundleIdentifier)</string>
            <key>CFBundleDisplayName</key>
            <string>\(name)</string>
            <key>CFBundleShortVersionString</key>
            <string>\(version)</string>
        </dict>
        </plist>
        """

        try plist.data(using: .utf8)!.write(
            to: contents.appendingPathComponent("Info.plist")
        )
    }
}
