import Foundation

nonisolated protocol ApplicationUpdateCoordinating: Sendable {
    func checkForUpdates(for applications: [InstalledApplication]) async -> [ApplicationIdentity: UpdateStatus]
}

nonisolated struct ApplicationUpdateCoordinator: ApplicationUpdateCoordinating {
    private let checker: any UpdateChecking
    private let maxConcurrentChecks: Int

    init(
        checker: any UpdateChecking,
        maxConcurrentChecks: Int = 3
    ) {
        self.checker = checker
        self.maxConcurrentChecks = max(1, maxConcurrentChecks)
    }

    func checkForUpdates(
        for applications: [InstalledApplication]
    ) async -> [ApplicationIdentity: UpdateStatus] {
        guard !applications.isEmpty else { return [:] }

        var results: [ApplicationIdentity: UpdateStatus] = [:]
        results.reserveCapacity(applications.count)

        await withTaskGroup(of: (ApplicationIdentity, UpdateStatus).self) { group in
            var iterator = applications.makeIterator()

            for _ in 0..<maxConcurrentChecks {
                guard let application = iterator.next() else { break }
                group.addTask {
                    let status = await checker.check(for: application)
                    return (application.id, status)
                }
            }

            while let result = await group.next() {
                results[result.0] = result.1

                if let application = iterator.next() {
                    group.addTask {
                        let status = await checker.check(for: application)
                        return (application.id, status)
                    }
                }
            }
        }

        return results
    }
}
