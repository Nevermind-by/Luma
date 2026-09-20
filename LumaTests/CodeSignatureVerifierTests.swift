import Foundation
import Testing
@testable import Luma

struct CodeSignatureVerifierTests {
    @Test
    func rejectsUnsignedApplicationBundle() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("LumaCodeSignatureTest-\(UUID().uuidString)")
        let appURL = root.appendingPathComponent("Fixture.app", isDirectory: true)
        let contentsURL = appURL.appendingPathComponent("Contents", isDirectory: true)

        try FileManager.default.createDirectory(at: contentsURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let plist: [String: Any] = [
            "CFBundleIdentifier": "com.example.fixture",
            "CFBundleShortVersionString": "1.0.0"
        ]
        try PropertyListSerialization.data(
            fromPropertyList: plist,
            format: .xml,
            options: 0
        ).write(to: contentsURL.appendingPathComponent("Info.plist"))

        #expect(!CodeSignatureVerifier().verifyApplication(at: appURL))
    }
}
