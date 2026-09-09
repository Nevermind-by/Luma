import Foundation

nonisolated protocol ArtifactClassifying: Sendable {
    func classify(_ artifact: DownloadedArtifact) -> ArtifactType
}

struct ArtifactClassifier: ArtifactClassifying, Sendable {
    func classify(_ artifact: DownloadedArtifact) -> ArtifactType {
        let url = artifact.fileURL
        let extensionType = typeFromExtension(url.pathExtension)

        if hasHTMLSignature(at: url) {
            return .html
        }

        if hasZipSignature(at: url) {
            return .zip
        }

        if hasISO9660Signature(at: url) {
            return .iso
        }

        switch extensionType {
        case .pkg:
            return .pkg
        case .app:
            return .app
        case .dmg:
            return .dmg
        case .zip:
            return .zip
        case .iso:
            return .iso
        default:
            return .unknown
        }
    }

    private func typeFromExtension(_ pathExtension: String) -> ArtifactType {
        switch pathExtension.lowercased() {
        case "zip": return .zip
        case "dmg": return .dmg
        case "pkg": return .pkg
        case "app": return .app
        case "iso": return .iso
        default: return .unknown
        }
    }

    private func readBytes(at url: URL, offset: UInt64 = 0, count: Int) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        do {
            try handle.seek(toOffset: offset)
            return try handle.read(upToCount: count)
        } catch {
            return nil
        }
    }

    private func hasHTMLSignature(at url: URL) -> Bool {
        guard let data = readBytes(at: url, count: 256),
              let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return false
        }
        let lower = text.lowercased()
        return lower.hasPrefix("<!doctype html")
            || lower.hasPrefix("<html")
            || lower.hasPrefix("<head")
            || lower.hasPrefix("<body")
    }

    private func hasZipSignature(at url: URL) -> Bool {
        guard let header = readBytes(at: url, count: 4), header.count == 4 else { return false }
        return header[0] == 0x50
            && header[1] == 0x4B
            && header[2] == 0x03
            && (header[3] == 0x04 || header[3] == 0x05 || header[3] == 0x06)
    }

    private func hasISO9660Signature(at url: URL) -> Bool {
        // Primary Volume Descriptor starts at sector 16 (32,768 bytes)
        // and contains the standard ISO9660 identifier "CD001".
        guard let signature = readBytes(at: url, offset: 32_769, count: 5), signature.count == 5 else {
            return false
        }
        return signature == Data([0x43, 0x44, 0x30, 0x30, 0x31])
    }
}
