import Foundation

final class DownloadProgressReporter: @unchecked Sendable {
    private let lock = NSLock()
    private let interval: TimeInterval
    private let delivery: @Sendable (ApplicationIdentity, DownloadProgress) -> Void

    private var latestProgress: [ApplicationIdentity: DownloadProgress] = [:]
    private var scheduledIdentities: Set<ApplicationIdentity> = []

    init(
        interval: TimeInterval = 0.1,
        delivery: @escaping @Sendable (ApplicationIdentity, DownloadProgress) -> Void
    ) {
        self.interval = interval
        self.delivery = delivery
    }

    func report(
        _ progress: DownloadProgress,
        for application: ApplicationIdentity
    ) {
        lock.lock()
        latestProgress[application] = progress
        let shouldSchedule = scheduledIdentities.insert(application).inserted
        lock.unlock()

        guard shouldSchedule else { return }

        DispatchQueue.main.asyncAfter(
            deadline: .now() + interval
        ) { [weak self] in
            self?.deliverLatestProgress(for: application)
        }
    }

    func finish(for application: ApplicationIdentity) {
        lock.lock()
        latestProgress.removeValue(forKey: application)
        scheduledIdentities.remove(application)
        lock.unlock()
    }

    private func deliverLatestProgress(for application: ApplicationIdentity) {
        lock.lock()
        let progress = latestProgress.removeValue(forKey: application)
        scheduledIdentities.remove(application)
        lock.unlock()

        guard let progress else { return }
        delivery(application, progress)
    }
}
