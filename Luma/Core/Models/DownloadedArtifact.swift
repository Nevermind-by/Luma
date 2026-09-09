import Foundation

nonisolated struct DownloadedArtifact: Identifiable, Equatable, Sendable {
    let id: UUID
    let originalURL: URL
    let finalURL: URL
    let fileURL: URL
    let filename: String
    let mimeType: String?
    let byteCount: Int64

    init(
        id: UUID = UUID(),
        originalURL: URL,
        finalURL: URL,
        fileURL: URL,
        filename: String,
        mimeType: String?,
        byteCount: Int64
    ) {
        self.id = id
        self.originalURL = originalURL
        self.finalURL = finalURL
        self.fileURL = fileURL
        self.filename = filename
        self.mimeType = mimeType
        self.byteCount = byteCount
    }
}
