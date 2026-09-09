import Foundation

nonisolated protocol ISOImageExtracting: Sendable {
    func extractFirstDiskImage(from isoURL: URL, to directory: URL) throws -> URL
}

struct ISOImageExtractor: ISOImageExtracting, Sendable {
    enum ExtractionError: LocalizedError, Equatable {
        case invalidPrimaryVolumeDescriptor
        case unsupportedSectorSize
        case rootDirectoryUnavailable
        case diskImageNotFound
        case invalidDirectoryRecord
        case truncatedFile
        case writeFailed

        var errorDescription: String? {
            switch self {
            case .invalidPrimaryVolumeDescriptor:
                return "The ISO image does not contain a valid ISO9660 primary volume descriptor."
            case .unsupportedSectorSize:
                return "The ISO image uses an unsupported logical block size."
            case .rootDirectoryUnavailable:
                return "The ISO root directory could not be read."
            case .diskImageNotFound:
                return "No disk image was found inside the ISO."
            case .invalidDirectoryRecord:
                return "The ISO contains an invalid directory record."
            case .truncatedFile:
                return "A file inside the ISO is truncated."
            case .writeFailed:
                return "Luma could not extract the disk image from the ISO."
            }
        }
    }

    private struct DirectoryRecord {
        let extent: UInt32
        let dataLength: UInt32
        let isDirectory: Bool
        let name: String
    }

    private let sectorOffset = 16

    func extractFirstDiskImage(from isoURL: URL, to directory: URL) throws -> URL {
        guard let handle = try? FileHandle(forReadingFrom: isoURL) else {
            throw ExtractionError.invalidPrimaryVolumeDescriptor
        }
        defer { try? handle.close() }

        let blockSize = try readUInt16LE(handle, at: UInt64(sectorOffset * 2048 + 128))
        guard blockSize == 2048 || blockSize == 1024 || blockSize == 512 else {
            throw ExtractionError.unsupportedSectorSize
        }

        let descriptorOffset = UInt64(sectorOffset) * UInt64(blockSize)
        let descriptor = try readBytes(handle, at: descriptorOffset, count: 2048)
        guard descriptor.count >= 190,
              descriptor[0] == 1,
              String(data: descriptor.subdata(in: 1..<6), encoding: .ascii) == "CD001" else {
            throw ExtractionError.invalidPrimaryVolumeDescriptor
        }

        let rootRecordLength = Int(descriptor[156])
        guard rootRecordLength >= 34, 156 + rootRecordLength <= descriptor.count else {
            throw ExtractionError.rootDirectoryUnavailable
        }

        let rootRecord = try parseDirectoryRecord(descriptor.subdata(in: 156..<(156 + rootRecordLength)))
        guard rootRecord.isDirectory else {
            throw ExtractionError.rootDirectoryUnavailable
        }

        guard let result = try findDiskImage(
            handle: handle,
            blockSize: Int(blockSize),
            record: rootRecord,
            destinationDirectory: directory,
            visitedDirectories: []
        ) else {
            throw ExtractionError.diskImageNotFound
        }

        return result
    }

    private func findDiskImage(
        handle: FileHandle,
        blockSize: Int,
        record: DirectoryRecord,
        destinationDirectory: URL,
        visitedDirectories: Set<UInt32>
    ) throws -> URL? {
        if visitedDirectories.contains(record.extent) {
            return nil
        }

        var nextVisited = visitedDirectories
        nextVisited.insert(record.extent)

        let directoryData = try readBytes(
            handle,
            at: UInt64(record.extent) * UInt64(blockSize),
            count: Int(record.dataLength)
        )
        guard directoryData.count == Int(record.dataLength) else {
            throw ExtractionError.truncatedFile
        }

        var offset = 0
        while offset < directoryData.count {
            let length = Int(directoryData[offset])
            if length == 0 {
                let nextBoundary = ((offset / blockSize) + 1) * blockSize
                offset = min(nextBoundary, directoryData.count)
                continue
            }

            guard length >= 34, offset + length <= directoryData.count else {
                throw ExtractionError.invalidDirectoryRecord
            }

            let rawRecord = directoryData.subdata(in: offset..<(offset + length))
            let child = try parseDirectoryRecord(rawRecord)
            offset += length

            if child.name == "." || child.name == ".." {
                continue
            }

            if child.isDirectory {
                if let result = try findDiskImage(
                    handle: handle,
                    blockSize: blockSize,
                    record: child,
                    destinationDirectory: destinationDirectory,
                    visitedDirectories: nextVisited
                ) {
                    return result
                }
                continue
            }

            let normalizedName = normalizedFilename(child.name)
            guard normalizedName.lowercased().hasSuffix(".dmg") else {
                continue
            }

            let destinationURL = uniqueDestinationURL(filename: normalizedName, in: destinationDirectory)
            try copyFile(
                handle: handle,
                extent: child.extent,
                length: child.dataLength,
                blockSize: blockSize,
                to: destinationURL
            )
            return destinationURL
        }

        return nil
    }

    private func parseDirectoryRecord(_ data: Data) throws -> DirectoryRecord {
        guard data.count >= 34 else {
            throw ExtractionError.invalidDirectoryRecord
        }

        let extent = try uint32LE(data, at: 2)
        let dataLength = try uint32LE(data, at: 10)
        let flags = data[25]
        let nameLength = Int(data[32])
        guard 33 + nameLength <= data.count else {
            throw ExtractionError.invalidDirectoryRecord
        }

        let nameData = data.subdata(in: 33..<(33 + nameLength))
        let name = String(data: nameData, encoding: .ascii) ?? ""
        return DirectoryRecord(
            extent: extent,
            dataLength: dataLength,
            isDirectory: (flags & 0x02) != 0,
            name: name
        )
    }

    private func normalizedFilename(_ name: String) -> String {
        var result = name
        if let semicolon = result.lastIndex(of: ";") {
            result = String(result[..<semicolon])
        }
        while result.last == "." {
            result.removeLast()
        }
        return result.isEmpty ? "Luma-Extracted.dmg" : result
    }

    private func uniqueDestinationURL(filename: String, in directory: URL) -> URL {
        let initialURL = directory.appendingPathComponent(filename)
        if !FileManager.default.fileExists(atPath: initialURL.path) {
            return initialURL
        }

        let base = initialURL.deletingPathExtension().lastPathComponent
        let ext = initialURL.pathExtension
        for index in 2...10_000 {
            let candidateName = ext.isEmpty ? "\(base) (\(index))" : "\(base) (\(index)).\(ext)"
            let candidate = directory.appendingPathComponent(candidateName)
            if !FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }

        return directory.appendingPathComponent("Luma-\(UUID().uuidString).dmg")
    }

    private func copyFile(
        handle: FileHandle,
        extent: UInt32,
        length: UInt32,
        blockSize: Int,
        to destination: URL
    ) throws {
        FileManager.default.createFile(atPath: destination.path, contents: nil)
        guard let output = try? FileHandle(forWritingTo: destination) else {
            throw ExtractionError.writeFailed
        }
        defer { try? output.close() }

        let chunkSize = 4 * 1024 * 1024
        var remaining = Int64(length)
        var offset = UInt64(extent) * UInt64(blockSize)

        while remaining > 0 {
            let readCount = Int(min(Int64(chunkSize), remaining))
            let chunk = try readBytes(handle, at: offset, count: readCount)
            guard chunk.count == readCount else {
                throw ExtractionError.truncatedFile
            }
            do {
                try output.write(contentsOf: chunk)
            } catch {
                throw ExtractionError.writeFailed
            }
            remaining -= Int64(readCount)
            offset += UInt64(readCount)
        }
    }

    private func readBytes(_ handle: FileHandle, at offset: UInt64, count: Int) throws -> Data {
        try handle.seek(toOffset: offset)
        return try handle.read(upToCount: count) ?? Data()
    }

    private func readUInt16LE(_ handle: FileHandle, at offset: UInt64) throws -> UInt16 {
        let data = try readBytes(handle, at: offset, count: 2)
        guard data.count == 2 else { throw ExtractionError.invalidPrimaryVolumeDescriptor }
        return UInt16(data[0]) | (UInt16(data[1]) << 8)
    }

    private func uint32LE(_ data: Data, at offset: Int) throws -> UInt32 {
        guard offset + 4 <= data.count else { throw ExtractionError.invalidDirectoryRecord }
        return UInt32(data[offset])
            | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16)
            | (UInt32(data[offset + 3]) << 24)
    }
}
