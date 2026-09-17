import Foundation
import Network
import os

/// One TCP connection to the ADB server, with buffered async reads.
///
/// Used by one task at a time: every method is called sequentially by its owner.
final class ADBSocket: @unchecked Sendable {
    private let connection: NWConnection
    private let queue = DispatchQueue(label: "io.github.najm101.AndroidDeviceApp.adb")
    private var buffer = Data()
    private var isAtEnd = false

    init(host: String, port: UInt16) {
        connection = NWConnection(
            host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port) ?? 5037, using: .tcp)
    }

    deinit {
        connection.cancel()
    }

    func open() async throws {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                let resumed = OSAllocatedUnfairLock(initialState: false)
                connection.stateUpdateHandler = { state in
                    let result: Result<Void, any Error>?
                    switch state {
                    case .ready: result = .success(())
                    case let .failed(error), let .waiting(error):
                        result = .failure(ADBError.serverUnavailable(error.localizedDescription))
                    case .cancelled: result = .failure(CancellationError())
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
        } onCancel: {
            connection.cancel()
        }
        // `waiting` keeps retrying in the background; stop listening once the outcome is known.
        connection.stateUpdateHandler = nil
    }

    func close() {
        connection.cancel()
    }

    // MARK: - Writing

    func write(_ data: Data) async throws {
        guard !data.isEmpty else { return }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            connection.send(
                content: data,
                completion: .contentProcessed { error in
                    if let error {
                        continuation.resume(throwing: ADBError.failed(error.localizedDescription))
                    } else {
                        continuation.resume()
                    }
                })
        }
    }

    /// Sends a host or device service request: 4 hex digits of length, then the payload.
    func sendRequest(_ service: String) async throws {
        try await write(ADBWire.request(service))
    }

    // MARK: - Reading

    /// Waits for `OKAY`, or throws the message that follows `FAIL`.
    func readStatus() async throws {
        let status = try await read(exactly: 4)
        switch String(decoding: status, as: UTF8.self) {
        case "OKAY":
            return
        case "FAIL":
            throw ADBError.failed(try await readLengthPrefixedString())
        case let other:
            throw ADBError.protocolViolation("status \(other)")
        }
    }

    /// 4 hex digits of length followed by that many bytes of UTF-8.
    func readLengthPrefixedString() async throws -> String {
        let length = try ADBWire.hexLength(try await read(exactly: 4))
        return String(decoding: try await read(exactly: length), as: UTF8.self)
    }

    func read(exactly count: Int) async throws -> Data {
        while buffer.count < count {
            guard try await fill() else { throw ADBError.connectionClosed }
        }
        let result = buffer.prefix(count)
        buffer.removeFirst(count)
        return Data(result)
    }

    /// The next chunk of bytes, or nil once the other side has closed the connection.
    func readChunk() async throws -> Data? {
        if buffer.isEmpty, try await !fill() {
            return nil
        }
        let result = buffer
        buffer = Data()
        return result
    }

    func readToEnd() async throws -> Data {
        var result = Data()
        while let chunk = try await readChunk() {
            result.append(chunk)
        }
        return result
    }

    func readUInt32() async throws -> UInt32 {
        try await read(exactly: 4).littleEndianInteger()
    }

    /// Appends received bytes to the buffer. Returns false at the end of the stream.
    private func fill() async throws -> Bool {
        if isAtEnd { return false }
        try Task.checkCancellation()
        let data: Data? = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                connection.receive(minimumIncompleteLength: 1, maximumLength: 256 * 1024) {
                    data, _, isComplete, error in
                    if let data, !data.isEmpty {
                        continuation.resume(returning: data)
                    } else if isComplete {
                        continuation.resume(returning: nil)
                    } else if let error {
                        if case .posix(.ECANCELED) = error {
                            continuation.resume(throwing: CancellationError())
                        } else if case .posix(.ENODATA) = error {
                            // The other side closed the stream without a clean shutdown.
                            continuation.resume(returning: nil)
                        } else {
                            continuation.resume(throwing: ADBError.failed(error.localizedDescription))
                        }
                    } else {
                        continuation.resume(returning: Data())
                    }
                }
            }
        } onCancel: {
            connection.cancel()
        }
        guard let data else {
            isAtEnd = true
            return false
        }
        buffer.append(data)
        return true
    }
}

/// Encoding helpers shared by the host, shell and sync protocols.
enum ADBWire {
    static func request(_ service: String) -> Data {
        let payload = Data(service.utf8)
        var data = Data(String(format: "%04x", payload.count).utf8)
        data.append(payload)
        return data
    }

    static func hexLength(_ data: Data) throws -> Int {
        guard data.count == 4, let value = Int(String(decoding: data, as: UTF8.self), radix: 16) else {
            throw ADBError.protocolViolation("length \(String(decoding: data, as: UTF8.self))")
        }
        return value
    }
}

extension Data {
    /// Reads a little-endian integer from the start of the data.
    func littleEndianInteger<T: FixedWidthInteger>(at offset: Int = 0, as type: T.Type = T.self) -> T {
        var value: T = 0
        let size = MemoryLayout<T>.size
        let start = startIndex + offset
        for index in 0..<size where start + index < endIndex {
            value |= T(truncatingIfNeeded: self[start + index]) << (index * 8)
        }
        return value
    }

    mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }
}
