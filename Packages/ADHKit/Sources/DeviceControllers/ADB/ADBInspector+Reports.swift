import ADBClient
public import DeviceDomain
public import Foundation

extension ADBInspector {
    public func crashReports() async throws -> [CrashReport] {
        let tags = DeviceOutputParsers.crashTags.keys.sorted()
        let command = tags.map { "dumpsys dropbox --print \($0)" }.joined(separator: "; ")
        let output = try await device.shell(command).output
        return DeviceOutputParsers.crashReports(output)
    }

    public func logEntries(recent: Int) -> AsyncThrowingStream<[LogEntry], any Error> {
        let bytes = device.shellStream("logcat -B -b main,system,crash -T \(max(1, recent))")
        return AsyncThrowingStream { continuation in
            let task = Task.detached {
                var decoder = LogcatDecoder()
                do {
                    for try await chunk in bytes {
                        decoder.append(chunk)
                        let entries = decoder.entries()
                        if !entries.isEmpty { continuation.yield(entries) }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func bugReport(into folder: URL, progress: @escaping @Sendable (Double?) -> Void) async throws -> URL {
        progress(nil)
        var remotePath: String?
        var pending = ""
        for try await chunk in device.shellStream("bugreportz -p") {
            pending += String(decoding: chunk, as: UTF8.self)
            while let newline = pending.firstIndex(of: "\n") {
                let line = pending[..<newline].trimmingCharacters(in: .whitespaces)
                pending.removeSubrange(...newline)
                switch DeviceOutputParsers.bugReportLine(line) {
                case let .progress(fraction): progress(fraction * 0.9)
                case let .finished(path): remotePath = path
                case let .failed(reason): throw InspectorError.bugReportFailed(reason)
                case nil: break
                }
            }
        }
        guard let remotePath else { throw InspectorError.bugReportFailed("the device didn't create a report") }

        let sync = try await device.sync()
        defer { sync.close() }
        let stat = try await sync.stat(remotePath)
        let destination = Self.availableURL(for: RemotePath.name(of: remotePath), in: folder)
        try await sync.pull(remotePath, to: destination, size: stat.size) { completed, total in
            progress(0.9 + 0.1 * Double(completed) / Double(max(total, 1)))
        }
        _ = try? await device.run("rm -f \(shellQuoted(remotePath))")
        return destination
    }
}
