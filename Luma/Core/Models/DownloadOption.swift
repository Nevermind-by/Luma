import Foundation

struct DownloadOption: Identifiable, Hashable, Sendable {
    enum Kind: String, Sendable {
        case direct
        case external
    }

    let id: UUID
    let kind: Kind
    let title: String
    let url: URL

    init(id: UUID = UUID(), kind: Kind, title: String, url: URL) {
        self.id = id
        self.kind = kind
        self.title = title
        self.url = url
    }
}
