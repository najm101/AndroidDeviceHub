public import Foundation

public enum ADBError: LocalizedError, Equatable {
    /// Nothing listens on the ADB server port.
    case serverUnavailable(String)
    /// The server or device answered `FAIL`.
    case failed(String)
    /// The bytes on the wire didn't follow the protocol.
    case protocolViolation(String)
    case connectionClosed
    case timedOut
    /// A shell command exited with a non-zero status.
    case commandFailed(command: String, exitCode: Int, message: String)

    public var errorDescription: String? {
        switch self {
        case let .serverUnavailable(reason): "The ADB server isn't running: \(reason)"
        case let .failed(message): message.isEmpty ? "ADB reported an error." : message
        case let .protocolViolation(detail): "Unexpected reply from ADB (\(detail))."
        case .connectionClosed: "The device closed the connection."
        case .timedOut: "The device didn't answer in time."
        case let .commandFailed(command, exitCode, message):
            message.isEmpty ? "“\(command)” failed with exit code \(exitCode)." : message
        }
    }
}
