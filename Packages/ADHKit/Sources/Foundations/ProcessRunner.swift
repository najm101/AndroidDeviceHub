public import Foundation

/// Starts native programs. Output is written to a log file and never parsed.
public enum ProcessRunner {
    public struct Failure: LocalizedError {
        public var executable: String
        public var exitCode: Int32
        public var logFile: URL?

        public var errorDescription: String? {
            "\(executable) exited with code \(exitCode)."
        }

        public var recoverySuggestion: String? {
            logFile.map { "See the log at \($0.path(percentEncoded: false))." }
        }
    }

    /// Runs a program to completion and throws if it fails.
    public static func run(
        _ executable: URL,
        arguments: [String],
        environment: [String: String]? = nil,
        workingDirectory: URL? = nil,
        logFile: URL? = nil
    ) async throws {
        let process = try configuredProcess(executable, arguments, environment, workingDirectory, logFile)
        let status: Int32 = try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                continuation.resume(throwing: error)
            }
        }
        guard status == 0 else {
            throw Failure(executable: executable.lastPathComponent, exitCode: status, logFile: logFile)
        }
    }

    /// Starts a long-running program and returns immediately.
    /// `onExit` is called with the exit status when the program ends.
    @discardableResult
    public static func launch(
        _ executable: URL,
        arguments: [String],
        environment: [String: String]? = nil,
        workingDirectory: URL? = nil,
        logFile: URL? = nil,
        onExit: @escaping @Sendable (Int32) -> Void
    ) throws -> Int32 {
        let process = try configuredProcess(executable, arguments, environment, workingDirectory, logFile)
        let id = ObjectIdentifier(process)
        process.terminationHandler = { finished in
            LaunchedProcesses.shared.remove(id)
            onExit(finished.terminationStatus)
        }
        // Keep the Process alive until it exits, otherwise its termination handler never runs.
        LaunchedProcesses.shared.insert(process)
        do {
            try process.run()
        } catch {
            LaunchedProcesses.shared.remove(id)
            throw error
        }
        return process.processIdentifier
    }

    private static func configuredProcess(
        _ executable: URL,
        _ arguments: [String],
        _ environment: [String: String]?,
        _ workingDirectory: URL?,
        _ logFile: URL?
    ) throws -> Process {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        if let environment { process.environment = environment }
        if let workingDirectory { process.currentDirectoryURL = workingDirectory }
        process.standardInput = FileHandle.nullDevice
        if let logFile {
            try FileManager.default.createDirectory(
                at: logFile.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            FileManager.default.createFile(atPath: logFile.path(percentEncoded: false), contents: nil)
            let handle = try FileHandle(forWritingTo: logFile)
            process.standardOutput = handle
            process.standardError = handle
        } else {
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
        }
        return process
    }
}

private final class LaunchedProcesses: @unchecked Sendable {
    static let shared = LaunchedProcesses()

    private let lock = NSLock()
    private var processes: [ObjectIdentifier: Process] = [:]

    func insert(_ process: Process) {
        lock.withLock { processes[ObjectIdentifier(process)] = process }
    }

    func remove(_ id: ObjectIdentifier) {
        _ = lock.withLock { processes.removeValue(forKey: id) }
    }
}

public enum ProcessStatus {
    /// Whether a process with this id is still alive.
    public static func isAlive(_ pid: Int32) -> Bool {
        guard pid > 0 else { return false }
        return kill(pid, 0) == 0 || errno == EPERM
    }
}
