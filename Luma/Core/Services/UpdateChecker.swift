import Foundation

nonisolated protocol UpdateChecking: Sendable {
    func check(for application: InstalledApplication) async -> UpdateStatus
}

nonisolated struct UpdateChecker: UpdateChecking {
    private let sources: [any UpdateSource]
    private let versionComparator: VersionComparator

    init(
        sources: [any UpdateSource],
        versionComparator: VersionComparator = VersionComparator()
    ) {
        self.sources = sources
        self.versionComparator = versionComparator
    }

    func check(for application: InstalledApplication) async -> UpdateStatus {
        guard !sources.isEmpty else {
            return .unavailable
        }

        var bestCandidate: UpdateCandidate?
        var successfulSourceCount = 0

        for source in sources {
            do {
                guard let candidate = try await source.checkForUpdate(for: application) else {
                    successfulSourceCount += 1
                    continue
                }

                successfulSourceCount += 1

                guard versionComparator.compare(candidate.version, application.version) == .orderedDescending else {
                    continue
                }

                if let currentBest = bestCandidate {
                    if versionComparator.compare(candidate.version, currentBest.version) == .orderedDescending {
                        bestCandidate = candidate
                    }
                } else {
                    bestCandidate = candidate
                }
            } catch {
                continue
            }
        }

        if let bestCandidate {
            return .updateAvailable(bestCandidate)
        }

        return successfulSourceCount > 0 ? .upToDate : .unavailable
    }
}
