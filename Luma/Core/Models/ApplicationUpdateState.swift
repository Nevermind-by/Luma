import Foundation

nonisolated enum ApplicationUpdateState: Equatable, Sendable {
    case notChecked
    case checking
    case upToDate
    case updateAvailable(UpdateCandidate)
    case unavailable
    case failed
}
