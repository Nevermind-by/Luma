import Foundation
import Testing
@testable import Luma

struct ISOImageExtractorTests {
    @Test
    func extractsFirstDMGFromIso9660Image() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent("LumaISOTest-\(UUID().uuidString)")
        let output = root.appendingPathComponent("Output", isDirectory: true)
        let isoURL = root.appendingPathComponent("Fixture.iso")
        try fileManager.createDirectory(at: output, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }

        let dmgBytes = Data("fixture-dmg".utf8)
        try makeISOImage(at: isoURL, dmgBytes: dmgBytes)

        let extractedURL = try ISOImageExtractor().extractFirstDiskImage(
            from: isoURL,
            to: output
        )

        #expect(extractedURL.lastPathComponent == "Fixture.dmg")
        #expect(try Data(contentsOf: extractedURL) == dmgBytes)
    }

    private func makeISOImage(at url: URL, dmgBytes: Data) throws {
        let blockSize = 2048
        let rootExtent = 20
        let fileExtent = 21
        let fileName = Data("Fixture.dmg;1".utf8)
        var image = Data(repeating: 0, count: blockSize * 22)

        let descriptorOffset = 16 * blockSize
        image[descriptorOffset] = 1
        image.replaceSubrange(
            (descriptorOffset + 1)..<(descriptorOffset + 6),
            with: Data("CD001".utf8)
        )
        image[descriptorOffset + 6] = 1

        let blockSizeLE = UInt16(blockSize)
        image[descriptorOffset + 128] = UInt8(blockSizeLE & 0xFF)
        image[descriptorOffset + 129] = UInt8(blockSizeLE >> 8)

        let rootRecord = directoryRecord(
            name: Data([0]),
            extent: rootExtent,
            dataLength: blockSize,
            isDirectory: true
        )
        image.replaceSubrange((descriptorOffset + 156)..<(descriptorOffset + 156 + rootRecord.count), with: rootRecord)

        var directory = Data(repeating: 0, count: blockSize)
        var offset = 0
        for record in [
            directoryRecord(name: Data([0]), extent: rootExtent, dataLength: blockSize, isDirectory: true),
            directoryRecord(name: Data([1]), extent: rootExtent, dataLength: blockSize, isDirectory: true),
            directoryRecord(name: fileName, extent: fileExtent, dataLength: UInt32(dmgBytes.count), isDirectory: false)
        ] {
            directory.replaceSubrange(offset..<(offset + record.count), with: record)
            offset += record.count
        }

        image.replaceSubrange((rootExtent * blockSize)..<((rootExtent + 1) * blockSize), with: directory)
        image.replaceSubrange((fileExtent * blockSize)..<(fileExtent * blockSize + dmgBytes.count), with: dmgBytes)
        try image.write(to: url)
    }

    private func directoryRecord(
        name: Data,
        extent: Int,
        dataLength: Int,
        isDirectory: Bool
    ) -> Data {
        directoryRecord(
            name: name,
            extent: UInt32(extent),
            dataLength: UInt32(dataLength),
            isDirectory: isDirectory
        )
    }

    private func directoryRecord(
        name: Data,
        extent: UInt32,
        dataLength: UInt32,
        isDirectory: Bool
    ) -> Data {
        let length = 33 + name.count + (name.count % 2 == 0 ? 1 : 0)
        var record = Data(repeating: 0, count: length)
        record[0] = UInt8(length)
        record[2] = UInt8(extent & 0xFF)
        record[3] = UInt8((extent >> 8) & 0xFF)
        record[4] = UInt8((extent >> 16) & 0xFF)
        record[5] = UInt8((extent >> 24) & 0xFF)
        record[10] = UInt8(dataLength & 0xFF)
        record[11] = UInt8((dataLength >> 8) & 0xFF)
        record[12] = UInt8((dataLength >> 16) & 0xFF)
        record[13] = UInt8((dataLength >> 24) & 0xFF)
        record[25] = isDirectory ? 0x02 : 0x00
        record[32] = UInt8(name.count)
        record.replaceSubrange(33..<(33 + name.count), with: name)
        return record
    }
}
