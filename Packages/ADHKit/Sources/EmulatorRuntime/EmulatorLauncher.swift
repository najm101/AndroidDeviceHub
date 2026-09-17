public import Foundation
public import Foundations
public import SDKDomain
import os

public enum EmulatorLaunchError: LocalizedError, Equatable {
    case emulatorNotInstalled
    case exited(code: Int32, log: URL)

    public var errorDescription: String? {
        switch self {
        case .emulatorNotInstalled: "The Android Emulator isn't installed."
        case let .exited(code, _): "The emulator stopped right away (exit code \(code))."
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .emulatorNotInstalled: "Install it in Settings → Components."
        case let .exited(_, log): "Details are in \(log.path(percentEncoded: false))."
        }
    }
}

public struct LaunchOptions: Hashable, Sendable {
    public var coldBoot: Bool
    public var wipeData: Bool
    /// Hide the emulator's own window (the app draws the device itself).
    public var hideWindow: Bool

    public init(coldBoot: Bool = false, wipeData: Bool = false, hideWindow: Bool = false) {
        self.coldBoot = coldBoot
        self.wipeData = wipeData
        self.hideWindow = hideWindow
    }
}

/// Starts emulators. Output goes to a log file; nothing is parsed.
public struct EmulatorLauncher: Sendable {
    private let fileSystem: any FileSystem
    private let logDirectory: URL
    private let environment: @Sendable () -> ProcessEnvironment
    private let log = ADHLog.logger("EmulatorLauncher")

    public init(
        logDirectory: URL,
        fileSystem: any FileSystem = LiveFileSystem(),
        environment: @escaping @Sendable () -> ProcessEnvironment = { .current }
    ) {
        self.logDirectory = logDirectory
        self.fileSystem = fileSystem
        self.environment = environment
    }

    /// Launches the emulator and waits briefly so immediate failures (bad config, missing image) are reported.
    public func launch(avdID: String, options: LaunchOptions, location: SDKLocation) async throws {
        guard fileSystem.fileExists(at: location.emulatorExecutable) else {
            throw EmulatorLaunchError.emulatorNotInstalled
        }
        let logFile = logDirectory.appending(path: "\(avdID).log", directoryHint: .notDirectory)
        let exit = ExitSignal()
        let pid = try ProcessRunner.launch(
            location.emulatorExecutable,
            arguments: try Self.arguments(avdID: avdID, options: options),
            environment: Self.environment(base: environment(), location: location),
            workingDirectory: location.emulatorDirectory,
            logFile: logFile,
            onExit: { exit.send($0) }
        )
        log.info("Launched \(avdID, privacy: .public) as pid \(pid)")

        if let code = await exit.wait(upTo: .seconds(3)), code != 0 {
            throw EmulatorLaunchError.exited(code: code, log: logFile)
        }
    }

    static func arguments(avdID: String, options: LaunchOptions) throws -> [String] {
        var arguments = ["-avd", avdID]
        // gRPC with token auth, so the in-app controls can attach to emulators this app starts.
        arguments += ["-grpc", String(try PortAllocator.freeLoopbackPort()), "-grpc-use-token"]
        if options.coldBoot { arguments.append("-no-snapshot-load") }
        if options.wipeData { arguments.append("-wipe-data") }
        if options.hideWindow { arguments.append("-qt-hide-window") }
        return arguments
    }

    /// The emulator must see the same folders the app resolved, even when launched from Finder.
    static func environment(base: ProcessEnvironment, location: SDKLocation) -> [String: String] {
        var values = base.values
        let sdk = location.sdkRoot.path(percentEncoded: false)
        values["ANDROID_HOME"] = sdk
        values["ANDROID_SDK_ROOT"] = sdk
        values["ANDROID_AVD_HOME"] = location.avdHome.path(percentEncoded: false)
        return values
    }
}

/// Delivers a process exit code to an async waiter.
private final class ExitSignal: @unchecked Sendable {
    private let lock = NSLock()
    private var code: Int32?
    private var continuation: CheckedContinuation<Int32?, Never>?

    func send(_ value: Int32) {
        let waiting: CheckedContinuation<Int32?, Never>? = lock.withLock {
            code = value
            defer { continuation = nil }
            return continuation
        }
        waiting?.resume(returning: value)
    }

    /// The exit code if the process ended within `timeout`, otherwise `nil`.
    func wait(upTo timeout: Duration) async -> Int32? {
        await withTaskGroup(of: Int32?.self) { group in
            group.addTask { await self.exitCode() }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            self.resumeIfWaiting()
            return first
        }
    }

    private func exitCode() async -> Int32? {
        await withCheckedContinuation { continuation in
            let immediate: Int32?? = lock.withLock {
                if let code { return .some(code) }
                self.continuation = continuation
                return .none
            }
            if case let .some(code) = immediate {
                continuation.resume(returning: code)
            }
        }
    }

    private func resumeIfWaiting() {
        let waiting: CheckedContinuation<Int32?, Never>? = lock.withLock {
            defer { continuation = nil }
            return continuation
        }
        waiting?.resume(returning: nil)
    }
}
