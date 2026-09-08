import Foundation

nonisolated protocol DownloadManaging: Sendable {
    func download(
        _ option: DownloadOption,
        to directory: URL,
        progress: @escaping @Sendable (DownloadProgress) -> Void
    ) async throws -> URL
}

final class DownloadManager: NSObject, URLSessionDownloadDelegate, DownloadManaging, @unchecked Sendable {
    enum DownloadError: Error, Equatable {
        case unsupportedDownloadOption
        case invalidDestination
        case downloadFailed
    }

    private struct Job {
        let destinationURL: URL
        let continuation: CheckedContinuation<URL, Error>
        let progress: @Sendable (DownloadProgress) -> Void
    }

    private let lock = NSLock()
    private var jobs: [Int: Job] = [:]
    private lazy var session: URLSession = {
        URLSession(
            configuration: .default,
            delegate: self,
            delegateQueue: nil
        )
    }()

    deinit {
        session.invalidateAndCancel()
    }

    func download(
        _ option: DownloadOption,
        to directory: URL,
        progress: @escaping @Sendable (DownloadProgress) -> Void
    ) async throws -> URL {
        guard option.kind == .direct else {
            throw DownloadError.unsupportedDownloadOption
        }

        var isDirectory: ObjCBool = false
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw DownloadError.invalidDestination
        }

        let destinationURL = uniqueDestinationURL(
            for: sanitizedFilename(from: option.url),
            in: directory
        )

        let task = session.downloadTask(with: option.url)

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
            lock.lock()
            jobs[task.taskIdentifier] = Job(
                destinationURL: destinationURL,
                continuation: continuation,
                progress: progress
            )
            lock.unlock()

            task.resume()
        }
    }

    private func sanitizedFilename(from url: URL) -> String {
        let original = url.lastPathComponent.isEmpty ? "Luma-Download" : url.lastPathComponent
        return original
            .replacingOccurrences(of: "/", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func uniqueDestinationURL(for filename: String, in directory: URL) -> URL {
        let initialURL = directory.appendingPathComponent(filename)
        guard FileManager.default.fileExists(atPath: initialURL.path) else {
            return initialURL
        }

        let base = initialURL.deletingPathExtension().lastPathComponent
        let ext = initialURL.pathExtension

        for index in 2...10_000 {
            let candidateName = ext.isEmpty ? "\(base) (\(index))" : "\(base) (\(index)).\(ext)"
            let candidate = directory.appendingPathComponent(candidateName)
            if !FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }

        return directory.appendingPathComponent("Luma-\(UUID().uuidString).download")
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let job = job(for: downloadTask.taskIdentifier)
        let total = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : nil
        job?.progress(
            DownloadProgress(
                bytesWritten: totalBytesWritten,
                totalBytes: total
            )
        )
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard let job = removeJob(for: downloadTask.taskIdentifier) else {
            return
        }

        do {
            if FileManager.default.fileExists(atPath: job.destinationURL.path) {
                try FileManager.default.removeItem(at: job.destinationURL)
            }

            try FileManager.default.moveItem(at: location, to: job.destinationURL)
            job.progress(
                DownloadProgress(
                    bytesWritten: 1,
                    totalBytes: 1
                )
            )
            job.continuation.resume(returning: job.destinationURL)
        } catch {
            job.continuation.resume(throwing: error)
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard let error else {
            return
        }

        guard let job = removeJob(for: task.taskIdentifier) else {
            return
        }

        job.continuation.resume(throwing: error)
    }

    private func job(for taskIdentifier: Int) -> Job? {
        lock.lock()
        defer { lock.unlock() }
        return jobs[taskIdentifier]
    }

    private func removeJob(for taskIdentifier: Int) -> Job? {
        lock.lock()
        defer { lock.unlock() }
        return jobs.removeValue(forKey: taskIdentifier)
    }
}
