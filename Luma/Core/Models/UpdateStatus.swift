import Foundation

nonisolated enum UpdateStatus: Equatable, Sendable {
    case upToDate
    case updateAvailable(UpdateCandidate)
    case unavailable
}
