public import Foundation

/// The output of a shell command run with the v2 protocol.
public struct ShellResult: Sendable, Equatable {
    public var exitCode: Int
    public var standardOutput: Data
    public var standardError: Data

    public init(exitCode: Int, standardOutput: Data, standardError: Data = Data()) {
        self.exitCode = exitCode
        self.standardOutput = standardOutput
        self.standardError = standardError
    }

    public var output: String { String(decoding: standardOutput, as: UTF8.self) }
    public var errorOutput: String { String(decoding: standardError, as: UTF8.self) }
}

/// Byte progress of a transfer.
public typealias ADBProgress = @Sendable (_ completed: Int64, _ total: Int64) -> Void

/// Services on one device. Every call opens its own connection.
public struct ADBDevice: Sendable {
    public let serial: String
    public let server: ADBServer

    public init(serial: String, server: ADBServer = ADBServer()) {
        self.serial = serial
        self.server = server
    }

    public func features() async throws -> Set<String> {
        try await server.features(serial: serial)
    }

    // MARK: - Shell

    /// Runs a command with the shell v2 protocol, which keeps stdout, stderr and the exit code apart.
    public func shell(_ command: String) async throws -> ShellResult {
        let socket = try await server.openDeviceService("shell,v2,raw:\(command)", serial: serial)
        defer { socket.close() }
        var decoder = ShellV2Decoder()
        var result = ShellResult(exitCode: -1, standardOutput: Data())
        while let chunk = try await socket.readChunk() {
            decoder.append(chunk)
            while let packet = try decoder.next() {
                switch packet.kind {
                case .stdout: result.standardOutput.append(packet.payload)
                case .stderr: result.standardError.append(packet.payload)
                case .exit: result.exitCode = Int(packet.payload.first ?? 255)
                default: break
                }
            }
        }
        return result
    }

    /// Runs a command and throws unless it exits with 0. Returns stdout.
    @discardableResult
    public func run(_ command: String) async throws -> String {
        let result = try await shell(command)
        guard result.exitCode == 0 else {
            let message =
                [result.errorOutput, result.output]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first { !$0.isEmpty } ?? ""
            throw ADBError.commandFailed(command: command, exitCode: result.exitCode, message: message)
        }
        return result.output
    }

    /// The command's stdout as it arrives. The command is stopped when the stream is cancelled.
    public func shellStream(_ command: String) -> AsyncThrowingStream<Data, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let socket = try await server.openDeviceService("shell,v2,raw:\(command)", serial: serial)
                    defer { socket.close() }
                    var decoder = ShellV2Decoder()
                    while let chunk = try await socket.readChunk() {
                        decoder.append(chunk)
                        while let packet = try decoder.next() {
                            if packet.kind == .stdout { continuation.yield(packet.payload) }
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Streaming input

    /// Runs `exec:<command>` (or `abb_exec:` when `abb` is true), writes `input` to its stdin and returns
    /// everything it prints.
    func execute(
        _ command: String, abb: Bool, input: URL, size: Int64, progress: ADBProgress?
    ) async throws -> String {
        let service = abb ? "abb_exec:\(command)" : "exec:\(command)"
        let socket = try await server.openDeviceService(service, serial: serial)
        defer { socket.close() }
        let handle = try FileHandle(forReadingFrom: input)
        defer { try? handle.close() }
        var sent: Int64 = 0
        while let chunk = try handle.read(upToCount: 256 * 1024), !chunk.isEmpty {
            try Task.checkCancellation()
            try await socket.write(chunk)
            sent += Int64(chunk.count)
            progress?(sent, size)
        }
        return String(decoding: try await socket.readToEnd(), as: UTF8.self)
    }

    /// Runs a command without stdin and returns its combined output (`exec:` or `abb_exec:`).
    func execute(_ command: String, abb: Bool) async throws -> String {
        let service = abb ? "abb_exec:\(command)" : "exec:\(command)"
        let socket = try await server.openDeviceService(service, serial: serial)
        defer { socket.close() }
        return String(decoding: try await socket.readToEnd(), as: UTF8.self)
    }

    // MARK: - Sync

    /// Opens a file transfer session. Close it when done.
    public func sync() async throws -> ADBSyncSession {
        let features = (try? await features()) ?? []
        let socket = try await server.openDeviceService("sync:", serial: serial)
        return ADBSyncSession(socket: socket, features: features)
    }

    public func reboot(into target: String = "") async throws {
        let socket = try await server.openDeviceService("reboot:\(target)", serial: serial)
        socket.close()
    }
}

/// Quotes a string for the device's `sh`.
public func shellQuoted(_ text: String) -> String {
    "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
}

// MARK: - Shell v2 framing

struct ShellV2Packet: Equatable {
    enum Kind: UInt8 {
        case stdin = 0
        case stdout = 1
        case stderr = 2
        case exit = 3
        case closeStdin = 4
        case windowSizeChange = 5
    }

    var kind: Kind
    var payload: Data
}

/// Splits a shell v2 stream into packets: 1 byte id, 4 bytes little-endian length, payload.
struct ShellV2Decoder {
    private var pending = Data()

    mutating func append(_ data: Data) {
        pending.append(data)
    }

    mutating func next() throws -> ShellV2Packet? {
        guard pending.count >= 5 else { return nil }
        let length = Int(pending.littleEndianInteger(at: 1, as: UInt32.self))
        guard pending.count >= 5 + length else { return nil }
        let id = pending[pending.startIndex]
        guard let kind = ShellV2Packet.Kind(rawValue: id) else {
            throw ADBError.protocolViolation("shell packet \(id)")
        }
        let payload = Data(pending[(pending.startIndex + 5)..<(pending.startIndex + 5 + length)])
        pending.removeFirst(5 + length)
        return ShellV2Packet(kind: kind, payload: payload)
    }
}
