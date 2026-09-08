import Foundation

protocol UpdateSource: Sendable {
    var name: String { get }

    func checkForUpdate(
        for application: InstalledApplication
    ) async throws -> UpdateCandidate?
}
