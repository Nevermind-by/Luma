import Foundation

nonisolated struct ApplicationIdentity: Hashable, Sendable {
    let bundleIdentifier: String
}
