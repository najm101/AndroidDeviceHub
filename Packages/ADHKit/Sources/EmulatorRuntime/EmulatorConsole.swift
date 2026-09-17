public import Foundation
import Foundations
import Network
import os

/// The emulator's telnet console on `localhost:<port.serial>`, used for the few settings gRPC doesn't offer
/// (network speed and latency, cellular state).
///
/// The protocol is line based: every reply ends with a line that is `OK` or starts with `KO`.
/// Only that final line is interpreted.
public struct EmulatorConsole: Sendable {
    public static var defaultTokenFile: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".emulator_console_auth_token", directoryHint: .notDirectory)
    }

    public let port: Int
    private let tokenFile: URL
    private let timeout: Duration

    public init(port: Int, tokenFile: URL = EmulatorConsole.defaultTokenFile, timeout: Duration = .seconds(5)) {
        self.port = port
        self.tokenFile = tokenFile
        self.timeout = timeout
    }

    /// Runs the commands in order on one connection and stops at the first rejected one.
    public func run(_ commands: [String]) async throws {
        let connection = ConsoleConnection(port: port)
        defer { connection.close() }
        // Cancelling the connection wakes any pending receive when the timeout fires.
        try await withTimeout(timeout, onTimeout: connection.close) {
            try await connection.open()
            _ = try await connection.readReply()  // banner
            if let token = try? String(contentsOf: tokenFile, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty
            {
                try await connection.send("auth \(token)")
                try Self.check(try await connection.readReply(), command: "auth")
            }
            for command in commands {
                try await connection.send(command)
                try Self.check(try await connection.readReply(), command: command)
            }
        }
    }

    static func check(_ reply: ConsoleReply, command: String) throws {
        if case let .rejected(reason) = reply {
            throw EmulatorConsoleError.rejected(command: command.components(separatedBy: " ").first ?? command, reason)
        }
    }

    private func withTimeout(
        _ duration: Duration,
        onTimeout: @escaping @Sendable () -> Void,
        _ operation: @escaping @Sendable () async throws -> Void
    ) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask(operation: operation)
            group.addTask {
                try await Task.sleep(for: duration)
                onTimeout()
                throw EmulatorConsoleError.timedOut
            }
            try await group.next()
            group.cancelAll()
        }
    }
}

public enum EmulatorConsoleError: LocalizedError, Equatable {
    case connectionFailed(String)
    case closed
    case timedOut
    case rejected(command: String, String)

    public var errorDescription: String? {
        switch self {
        case let .connectionFailed(reason): "Can't reach the emulator console: \(reason)"
        case .closed: "The emulator console closed the connection."
        case .timedOut: "The emulator console didn't answer in time."
        case let .rejected(command, reason): "The emulator rejected “\(command)”: \(reason)"
        }
    }
}

enum ConsoleReply: Equatable {
    case ok
    case rejected(String)

    /// Returns the reply if `line` ends one, otherwise nil.
    init?(line: String) {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed == "OK" {
            self = .ok
        } else if trimmed.hasPrefix("KO") {
            let reason = trimmed.dropFirst(2).drop { $0 == ":" || $0 == " " }
            self = .rejected(reason.isEmpty ? "unknown error" : String(reason))
        } else {
            return nil
        }
    }
}

/// Splits incoming bytes into lines and finds reply terminators.
struct ConsoleLineBuffer {
    private var pending = Data()

    mutating func append(_ data: Data) {
        pending.append(data)
    }

    /// Consumes lines up to and including the next reply terminator.
    mutating func nextReply() -> ConsoleReply? {
        while let newline = pending.firstIndex(of: UInt8(ascii: "\n")) {
            let lineData = pending[pending.startIndex..<newline]
            pending.removeSubrange(pending.startIndex...newline)
            let line = String(decoding: lineData, as: UTF8.self).trimmingCharacters(in: .newlines)
            if let reply = ConsoleReply(line: line) {
                return reply
            }
        }
        return nil
    }
}

/// A minimal async wrapper around `NWConnection` for the console.
private final class ConsoleConnection: @unchecked Sendable {
    private let connection: NWConnection
    private let queue = DispatchQueue(label: "io.github.najm101.AndroidDeviceApp.console")
    // Only touched from the calling task, one call at a time.
    private var buffer = ConsoleLineBuffer()

    init(port: Int) {
        connection = NWConnection(
            host: "127.0.0.1",
            port: NWEndpoint.Port(integerLiteral: UInt16(clamping: port)),
            using: .tcp
        )
    }

    func open() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            let resumed = OSAllocatedUnfairLock(initialState: false)
            connection.stateUpdateHandler = { state in
                let result: Result<Void, any Error>?
                switch state {
                case .ready: result = .success(())
                case let .failed(error), let .waiting(error):
                    result = .failure(EmulatorConsoleError.connectionFailed(error.localizedDescription))
                case .cancelled: result = .failure(EmulatorConsoleError.closed)
                default: result = nil
                }
                guard let result,
                    !resumed.withLock({ alreadyResumed in
                        defer { alreadyResumed = true }
                        return alreadyResumed
                    })
                else { return }
                continuation.resume(with: result)
            }
            connection.start(queue: queue)
        }
    }

    func send(_ line: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            connection.send(
                content: Data((line + "\n").utf8),
                completion: .contentProcessed { error in
                    if let error {
                        continuation.resume(throwing: EmulatorConsoleError.connectionFailed(error.localizedDescription))
                    } else {
                        continuation.resume()
                    }
                })
        }
    }

    func readReply() async throws -> ConsoleReply {
        while true {
            if let reply = buffer.nextReply() { return reply }
            try Task.checkCancellation()
            buffer.append(try await receive())
        }
    }

    private func receive() async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { data, _, isComplete, error in
                if let error {
                    continuation.resume(throwing: EmulatorConsoleError.connectionFailed(error.localizedDescription))
                } else if let data, !data.isEmpty {
                    continuation.resume(returning: data)
                } else if isComplete {
                    continuation.resume(throwing: EmulatorConsoleError.closed)
                } else {
                    continuation.resume(returning: Data())
                }
            }
        }
    }

    func close() {
        connection.cancel()
    }
}
