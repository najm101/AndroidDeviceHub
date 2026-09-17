public import ADBClient
public import Foundation
import Foundations
import os

/// Keeps the ADB server running and reports attached devices.
///
/// The server is shared with Android Studio and Flutter, so it's only started when nothing answers,
/// and never killed.
public actor ADBRuntime {
    public nonisolated let server: ADBServer
    private let logFile: URL?
    private let log = ADHLog.logger("ADBRuntime")

    public init(server: ADBServer = ADBServer(), logFile: URL? = nil) {
        self.server = server
        self.logFile = logFile
    }

    /// Starts the server with `adb start-server` if it isn't answering.
    public func ensureServer(adb: URL) async throws {
        if (try? await server.version()) != nil { return }
        guard FileManager.default.isExecutableFile(atPath: adb.path(percentEncoded: false)) else {
            throw ADBError.serverUnavailable("Platform Tools aren't installed.")
        }
        log.info("Starting the ADB server")
        // `start-server` returns once the daemon is listening; its output only goes to the log.
        try await ProcessRunner.run(adb, arguments: ["start-server"], logFile: logFile)
        _ = try await server.version()
    }

    /// The attached devices whenever they change. Restarts the server and reconnects after failures,
    /// until the stream is cancelled.
    public nonisolated func deviceUpdates(adb: @escaping @Sendable () async -> URL?) -> AsyncStream<[ADBDeviceEntry]> {
        AsyncStream { continuation in
            let task = Task {
                var delay = Duration.seconds(1)
                while !Task.isCancelled {
                    do {
                        guard let executable = await adb() else { throw ADBError.serverUnavailable("No SDK") }
                        try await ensureServer(adb: executable)
                        delay = .seconds(1)
                        for try await devices in server.trackDevices() {
                            continuation.yield(devices)
                        }
                    } catch is CancellationError {
                        break
                    } catch {
                        log.error("Device tracking stopped: \(error.localizedDescription, privacy: .public)")
                    }
                    continuation.yield([])
                    try? await Task.sleep(for: delay)
                    delay = min(delay * 2, .seconds(30))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
