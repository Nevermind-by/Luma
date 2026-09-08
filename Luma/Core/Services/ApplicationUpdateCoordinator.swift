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
        var results: [ApplicationIdentity: UpdateStatus] = [:]
        var pending = Array(applications.enumerated())

        while !pending.isEmpty {
            let batch = Array(pending.prefix(maxConcurrentChecks))
            pending.removeFirst(batch.count)

            let batchResults = await withTaskGroup(
                of: (ApplicationIdentity, UpdateStatus).self,
                returning: [(ApplicationIdentity, UpdateStatus)].self
            ) { group in
                for (_, application) in batch {
                    group.addTask {
                        let status = await checker.check(for: application)
                        return (application.id, status)
                    }
                }

                var completed: [(ApplicationIdentity, UpdateStatus)] = []
                for await result in group {
                    completed.append(result)
                }
                return completed
            }

            for (identity, status) in batchResults {
                results[identity] = status
            }
        }

        return results
    }
}
