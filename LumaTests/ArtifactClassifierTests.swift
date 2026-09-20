import Foundation
import Testing
@testable import Luma

struct ArtifactClassifierTests {
    @Test
    func detectsZIPByMagicEvenWithoutExtension() throws {
        let url = try makeTemporaryFile(named: "download", contents: Data([0x50, 0x4B, 0x03, 0x04]))
        defer { try? FileManager.default.removeItem(at: url) }

        let artifact = makeArtifact(for: url, mimeType: "application/octet-stream")
        #expect(ArtifactClassifier().classify(artifact) == .zip)
    }

    @Test
    func detectsHTMLBeforeUsingFilenameExtension() throws {
        let data = Data("<!doctype html><html><body>Cloudflare</body></html>".utf8)
        let url = try makeTemporaryFile(named: "Parallels.iso", contents: data)
        defer { try? FileManager.default.removeItem(at: url) }

        let artifact = makeArtifact(for: url, mimeType: "application/octet-stream")
        #expect(ArtifactClassifier().classify(artifact) == .html)
    }

    @Test
    func detectsISO9660With1024ByteLogicalBlocks() throws {
        let blockSize = 1024
        var data = Data(repeating: 0, count: blockSize * 17 + 134)
        let descriptorOffset = 16 * blockSize
        data[descriptorOffset] = 1
        data.replaceSubrange(
            (descriptorOffset + 1)..<(descriptorOffset + 6),
            with: Data("CD001".utf8)
        )
        data[descriptorOffset + 6] = 1
        data[descriptorOffset + 128] = UInt8(blockSize & 0xFF)
        data[descriptorOffset + 129] = UInt8((blockSize >> 8) & 0xFF)

        let url = try makeTemporaryFile(named: "download.bin", contents: data)
        defer { try? FileManager.default.removeItem(at: url) }

        let artifact = makeArtifact(for: url)
        #expect(ArtifactClassifier().classify(artifact) == .iso)
    }

    @Test
    func detectsISO9660ByPrimaryVolumeDescriptor() throws {
        var data = Data(repeating: 0, count: 32_768 + 190)
        data[32_768] = 1
        data[32_769] = 0x43
        data[32_770] = 0x44
        data[32_771] = 0x30
        data[32_772] = 0x30
        data[32_773] = 0x31
        data[32_896] = 0
        data[32_897] = 8
        let url = try makeTemporaryFile(named: "download.bin", contents: data)
        defer { try? FileManager.default.removeItem(at: url) }

        let artifact = makeArtifact(for: url)
        #expect(ArtifactClassifier().classify(artifact) == .iso)
    }

    private func makeTemporaryFile(named name: String, contents: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("LumaClassifier-\(UUID().uuidString)-\(name)")
        try contents.write(to: url)
        return url
    }

    private func makeArtifact(for url: URL, mimeType: String? = nil) -> DownloadedArtifact {
        let byteCount = Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        return DownloadedArtifact(
            originalURL: URL(string: "https://example.com/original")!,
            finalURL: URL(string: "https://example.com/final")!,
            fileURL: url,
            filename: url.lastPathComponent,
            mimeType: mimeType,
            byteCount: byteCount
        )
    }
}
