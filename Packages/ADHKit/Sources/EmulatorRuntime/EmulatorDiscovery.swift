public import Foundation
public import Foundations

/// A running emulator, read from its discovery file.
public struct RunningEmulator: Hashable, Sendable, CustomStringConvertible {
    public var pid: Int32
    public var avdID: String
    public var avdDirectory: URL?
    public var serialPort: Int?
    public var grpcPort: Int?
    /// The gRPC token from the discovery file. Present only for emulators started with `-grpc-use-token`.
    /// Never log it.
    public var grpcToken: String?
    public var emulatorVersion: String?

    /// Whether this app can control the emulator over gRPC.
    public var hasGRPCToken: Bool { grpcToken?.isEmpty == false }

    public init(
        pid: Int32, avdID: String, avdDirectory: URL? = nil, serialPort: Int? = nil, grpcPort: Int? = nil,
        grpcToken: String? = nil, emulatorVersion: String? = nil
    ) {
        self.pid = pid
        self.avdID = avdID
        self.avdDirectory = avdDirectory
        self.serialPort = serialPort
        self.grpcPort = grpcPort
        self.grpcToken = grpcToken
        self.emulatorVersion = emulatorVersion
    }

    public var description: String {
        "RunningEmulator(\(avdID), pid \(pid), grpc \(grpcPort.map(String.init) ?? "-"), token \(hasGRPCToken ? "<redacted>" : "none"))"
    }

    /// `emulator-5554`
    public var adbSerial: String? {
        serialPort.map { "emulator-\($0)" }
    }
}

/// Lists running emulators from `pid_<pid>.ini` files.
public struct EmulatorDiscovery: Sendable {
    public static var defaultDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Caches/TemporaryItems/avd/running", directoryHint: .isDirectory)
    }

    public let directory: URL
    private let fileSystem: any FileSystem
    private let isAlive: @Sendable (Int32) -> Bool

    public init(
        directory: URL = EmulatorDiscovery.defaultDirectory,
        fileSystem: any FileSystem = LiveFileSystem(),
        isAlive: @escaping @Sendable (Int32) -> Bool = ProcessStatus.isAlive
    ) {
        self.directory = directory
        self.fileSystem = fileSystem
        self.isAlive = isAlive
    }

    public func runningEmulators() -> [RunningEmulator] {
        let files = (try? fileSystem.contentsOfDirectory(at: directory)) ?? []
        return
            files
            .filter { $0.lastPathComponent.hasPrefix("pid_") && $0.pathExtension == "ini" }
            .compactMap { file in
                guard let text = try? fileSystem.string(contentsOf: file) else { return nil }
                return Self.parse(text, fileName: file.lastPathComponent)
            }
            .filter { isAlive($0.pid) }
    }

    /// Emits when emulators start or stop. Also polls, because a crashed emulator leaves its file behind.
    public func changes(pollInterval: Duration = .seconds(5)) -> AsyncStream<Void> {
        try? fileSystem.createDirectory(at: directory)
        let watched = DirectoryWatcher.changes(of: directory)
        return AsyncStream { continuation in
            let watcher = Task {
                for await _ in watched {
                    continuation.yield()
                }
            }
            let poller = Task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: pollInterval)
                    continuation.yield()
                }
            }
            continuation.onTermination = { _ in
                watcher.cancel()
                poller.cancel()
            }
        }
    }

    static func parse(_ text: String, fileName: String) -> RunningEmulator? {
        var values: [String: String] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: "=", maxSplits: 1)
            if parts.count == 2 {
                values[parts[0].trimmingCharacters(in: .whitespaces)] = parts[1].trimmingCharacters(in: .whitespaces)
            }
        }
        let pidText = fileName.dropFirst("pid_".count).split(separator: ".").first.map(String.init)
        guard let pid = pidText.flatMap(Int32.init), let avdID = values["avd.id"] else { return nil }
        return RunningEmulator(
            pid: pid,
            avdID: avdID,
            avdDirectory: values["avd.dir"].map { URL(filePath: $0, directoryHint: .isDirectory) },
            serialPort: values["port.serial"].flatMap(Int.init),
            grpcPort: values["grpc.port"].flatMap(Int.init),
            grpcToken: values["grpc.token"].flatMap { $0.isEmpty ? nil : $0 },
            emulatorVersion: values["emulator.version"]
        )
    }
}
