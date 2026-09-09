import Foundation

nonisolated protocol DownloadManaging: Sendable {
    func download(
        _ option: DownloadOption,
        to directory: URL,
        cookies: [HTTPCookie],
        progress: @escaping @Sendable (DownloadProgress) -> Void
    ) async throws -> URL
}

final class DownloadManager: NSObject, URLSessionDownloadDelegate, DownloadManaging, @unchecked Sendable {
    enum DownloadError: Error, Equatable {
        case unsupportedDownloadOption
        case invalidDestination
        case invalidResponse
        case downloadFailed
    }

    private struct Job {
        let requestedFilename: String
        let destinationDirectory: URL
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
        cookies: [HTTPCookie] = [],
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

        let requestedFilename = sanitizedFilename(from: option.url)
        var request = URLRequest(url: option.url)
        request.setValue("https://appstorrent.ru/", forHTTPHeaderField: "Referer")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 Version/17.0 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
        if !cookies.isEmpty {
            let fields = HTTPCookie.requestHeaderFields(with: cookies)
            request.setValue(fields["Cookie"], forHTTPHeaderField: "Cookie")
        }

        let task = session.downloadTask(with: request)

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
            lock.lock()
            jobs[task.taskIdentifier] = Job(
                requestedFilename: requestedFilename,
                destinationDirectory: directory,
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

    private func preferredFilename(for response: HTTPURLResponse, requestedFilename: String) -> String {
        let suggested = response.suggestedFilename?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let suggested, !suggested.isEmpty else {
            return requestedFilename
        }

        return suggested
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let activeJob = job(for: downloadTask.taskIdentifier)
        let total = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : nil
        activeJob?.progress(
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
        guard let activeJob = job(for: downloadTask.taskIdentifier) else {
            return
        }

        guard let response = downloadTask.response as? HTTPURLResponse,
              (200..<300).contains(response.statusCode) else {
            _ = removeJob(for: downloadTask.taskIdentifier)
            activeJob.continuation.resume(throwing: DownloadError.invalidResponse)
            return
        }

        guard let completedJob = removeJob(for: downloadTask.taskIdentifier) else {
            return
        }

        do {
            let filename = preferredFilename(
                for: response,
                requestedFilename: completedJob.requestedFilename
            )
            let destinationURL = uniqueDestinationURL(
                for: filename,
                in: completedJob.destinationDirectory
            )

            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }

            try FileManager.default.moveItem(at: location, to: destinationURL)
            completedJob.progress(
                DownloadProgress(
                    bytesWritten: 1,
                    totalBytes: 1
                )
            )
            completedJob.continuation.resume(returning: destinationURL)
        } catch {
            completedJob.continuation.resume(throwing: error)
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
