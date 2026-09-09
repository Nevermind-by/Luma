import Foundation

nonisolated enum ArtifactType: String, Sendable {
    case zip
    case dmg
    case pkg
    case app
    case iso
    case html
    case unknown
}
