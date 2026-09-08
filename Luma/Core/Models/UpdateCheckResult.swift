import Foundation

nonisolated enum UpdateCheckResult: Sendable {
    case updateAvailable(UpdateCandidate)
    case upToDate
    case unavailable
    case failed
}
