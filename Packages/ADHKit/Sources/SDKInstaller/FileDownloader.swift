import Foundation

/// Downloads one large file with progress reporting and resume support.
///
/// Resume data is kept next to the destination (`<file>.resume`) when a download fails or is cancelled,
/// so the next attempt continues where it stopped.
///
/// Each download runs on its own `URLSession` with a session delegate: the async
/// `URLSession.download(from:delegate:)` API never calls `didWriteData`, so it can't report progress.
struct FileDownloader: Sendable {
    typealias Progress = @Sendable (_ received: Int64, _ total: Int64, _ bytesPerSecond: Double?) -> Void

    /// Its configuration (timeouts, protocol classes) is used for every download.
    let session: URLSession

    func download(_ url: URL, to destination: URL, expectedSize: Int64, progress: @escaping Progress) async throws {
        let resumeFile = destination.appendingPathExtension("resume")
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        let resumeData = try? Data(contentsOf: resumeFile)
        try? FileManager.default.removeItem(at: resumeFile)

        let run = { (source: Source) in
            try await self.run(
                source, to: destination, resumeFile: resumeFile, expectedSize: expectedSize, progress: progress)
        }
        guard let resumeData else {
            return try await run(.url(url))
        }
        do {
            try await run(.resumeData(resumeData))
        } catch let error as URLError where error.code != .cancelled && error.downloadTaskResumeData == nil {
            // Stale resume data: start over.
            try await run(.url(url))
        }
    }

    private enum Source {
        case url(URL)
        case resumeData(Data)
    }

    private func run(
        _ source: Source,
        to destination: URL,
        resumeFile: URL,
        expectedSize: Int64,
        progress: @escaping Progress
    ) async throws {
        let delegate = DownloadDelegate(destination: destination, expectedSize: expectedSize, progress: progress)
        let downloadSession = URLSession(configuration: session.configuration, delegate: delegate, delegateQueue: nil)
        // The session keeps its delegate alive until it's invalidated.
        defer { downloadSession.finishTasksAndInvalidate() }

        let task =
            switch source {
            case let .url(url): downloadSession.downloadTask(with: url)
            case let .resumeData(data): downloadSession.downloadTask(withResumeData: data)
            }
        do {
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    delegate.start(task, continuation: continuation)
                }
            } onCancel: {
                task.cancel(byProducingResumeData: { data in
                    if let data { try? data.write(to: resumeFile) }
                })
            }
        } catch {
            if let data = (error as? URLError)?.downloadTaskResumeData {
                try? data.write(to: resumeFile)
            }
            throw error
        }
    }
}

private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let destination: URL
    private let expectedSize: Int64
    private let progress: FileDownloader.Progress
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, any Error>?
    /// Set when the finished file can't be used (bad status or failed move).
    private var finishError: (any Error)?
    private var lastReport = Date.distantPast
    private var sample: (date: Date, bytes: Int64)?
    private var speed: Double?

    init(destination: URL, expectedSize: Int64, progress: @escaping FileDownloader.Progress) {
        self.destination = destination
        self.expectedSize = expectedSize
        self.progress = progress
    }

    func start(_ task: URLSessionDownloadTask, continuation: CheckedContinuation<Void, any Error>) {
        lock.withLock { self.continuation = continuation }
        task.resume()
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let total = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : expectedSize
        let report: (Int64, Double?)? = lock.withLock {
            let now = Date.now
            guard now.timeIntervalSince(lastReport) >= 0.25 else { return nil }
            lastReport = now
            if let sample, now.timeIntervalSince(sample.date) >= 1 {
                let current = Double(totalBytesWritten - sample.bytes) / now.timeIntervalSince(sample.date)
                speed = speed.map { $0 * 0.6 + current * 0.4 } ?? current
                self.sample = (now, totalBytesWritten)
            } else if sample == nil {
                sample = (now, totalBytesWritten)
            }
            return (totalBytesWritten, speed)
        }
        if let report {
            progress(report.0, total, report.1)
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // The temporary file is deleted when this method returns, so it's moved here.
        let error: (any Error)?
        if let http = downloadTask.response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            error = URLError(.badServerResponse)
        } else {
            do {
                try? FileManager.default.removeItem(at: destination)
                try FileManager.default.moveItem(at: location, to: destination)
                error = nil
            } catch let moveError {
                error = moveError
            }
        }
        lock.withLock { finishError = error }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        let (continuation, finishError) = lock.withLock {
            defer { self.continuation = nil }
            return (self.continuation, self.finishError)
        }
        if let error = error ?? finishError {
            continuation?.resume(throwing: error)
        } else {
            continuation?.resume()
        }
    }
}
