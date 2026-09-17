import Foundation

/// A device as the ADB server lists it (`host:devices-l`).
public struct ADBDeviceEntry: Hashable, Sendable {
    public enum State: Hashable, Sendable {
        case device
        case offline
        case unauthorized
        case authorizing
        case connecting
        case other(String)

        init(_ text: String) {
            switch text {
            case "device": self = .device
            case "offline": self = .offline
            case "unauthorized": self = .unauthorized
            case "authorizing": self = .authorizing
            case "connecting": self = .connecting
            default: self = .other(text)
            }
        }
    }

    public var serial: String
    public var state: State
    /// `product`, `model`, `device`, `transport_id`, …
    public var attributes: [String: String]

    public init(serial: String, state: State, attributes: [String: String] = [:]) {
        self.serial = serial
        self.state = state
        self.attributes = attributes
    }

    public var isReady: Bool { state == .device }
    public var model: String? { attributes["model"] }

    /// Parses the server's device list, one device per line: `<serial> <state> key:value…`.
    static func parseList(_ text: String) -> [ADBDeviceEntry] {
        text.split(whereSeparator: \.isNewline).compactMap { line in
            let fields = line.split(whereSeparator: \.isWhitespace).map(String.init)
            guard fields.count >= 2 else { return nil }
            var attributes: [String: String] = [:]
            for field in fields.dropFirst(2) {
                let pair = field.split(separator: ":", maxSplits: 1).map(String.init)
                if pair.count == 2 { attributes[pair[0]] = pair[1] }
            }
            return ADBDeviceEntry(serial: fields[0], state: State(fields[1]), attributes: attributes)
        }
    }
}

/// The ADB server's host services over its socket.
public struct ADBServer: Sendable {
    public static let defaultPort: UInt16 = 5037

    public let host: String
    public let port: UInt16

    public init(host: String = "127.0.0.1", port: UInt16 = ADBServer.defaultPort) {
        self.host = host
        self.port = port
    }

    /// The server's protocol version (`host:version`).
    public func version() async throws -> Int {
        let socket = try await openHostService("host:version")
        defer { socket.close() }
        return try ADBWire.hexLength(Data(try await socket.readLengthPrefixedString().utf8))
    }

    public func devices() async throws -> [ADBDeviceEntry] {
        let socket = try await openHostService("host:devices-l")
        defer { socket.close() }
        return ADBDeviceEntry.parseList(try await socket.readLengthPrefixedString())
    }

    /// The full device list each time it changes. Ends with an error when the server goes away.
    public func trackDevices() -> AsyncThrowingStream<[ADBDeviceEntry], any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let socket = try await openHostService("host:track-devices-l")
                    defer { socket.close() }
                    while !Task.isCancelled {
                        continuation.yield(ADBDeviceEntry.parseList(try await socket.readLengthPrefixedString()))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Features both the server and the device support (`shell_v2`, `ls_v2`, `abb_exec`, …).
    public func features(serial: String) async throws -> Set<String> {
        let socket = try await openHostService("host-serial:\(serial):features")
        defer { socket.close() }
        return Set(try await socket.readLengthPrefixedString().split(separator: ",").map(String.init))
    }

    public func device(serial: String) -> ADBDevice {
        ADBDevice(serial: serial, server: self)
    }

    // MARK: - Connections

    func connect() async throws -> ADBSocket {
        let socket = ADBSocket(host: host, port: port)
        do {
            try await socket.open()
        } catch {
            socket.close()
            throw error
        }
        return socket
    }

    func openHostService(_ service: String) async throws -> ADBSocket {
        let socket = try await connect()
        do {
            try await socket.sendRequest(service)
            try await socket.readStatus()
            return socket
        } catch {
            socket.close()
            throw error
        }
    }

    /// Switches a new connection to the device's transport and opens a device service on it.
    func openDeviceService(_ service: String, serial: String) async throws -> ADBSocket {
        let socket = try await connect()
        do {
            try await socket.sendRequest("host:transport:\(serial)")
            try await socket.readStatus()
            try await socket.sendRequest(service)
            try await socket.readStatus()
            return socket
        } catch {
            socket.close()
            throw error
        }
    }
}
