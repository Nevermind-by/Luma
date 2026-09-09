import Foundation

nonisolated enum InstallationResult: Equatable, Sendable {
    case completed
    case userActionRequired
}
