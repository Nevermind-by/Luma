import Foundation

nonisolated enum ApplicationInstallationSource: String, Equatable, Sendable {
    case appStore
    case direct
    case unknown
}
