import ADHTestSupport
import Foundation
import Network
import Testing

@testable import EmulatorRuntime

struct ConsoleProtocolTests {
    @Test func findsReplyTerminators() {
        var buffer = ConsoleLineBuffer()
        buffer.append(Data("Android Console: Authentication required\r\nAndroid Console: type 'auth <token>'\r\n".utf8))
        #expect(buffer.nextReply() == nil)
        buffer.append(Data("OK\r\nKO: bad speed 'x'\r\nOK".utf8))
        #expect(buffer.nextReply() == .ok)
        #expect(buffer.nextReply() == .rejected("bad speed 'x'"))
        // An unterminated line waits for more data.
        #expect(buffer.nextReply() == nil)
        buffer.append(Data("\n".utf8))
        #expect(buffer.nextReply() == .ok)
    }

    @Test func keepsTextThatOnlyContainsOK() {
        #expect(ConsoleReply(line: "OK then") == nil)
        #expect(ConsoleReply(line: "KO") == .rejected("unknown error"))
    }
}

/// Runs `EmulatorConsole` against a local fake console.
@Suite(.serialized)
struct EmulatorConsoleTests {
    /// Accepts one connection, answers every line with `respond`, and records what it received.
    final class FakeConsole: @unchecked Sendable {
        let listener: NWListener
        private let queue = DispatchQueue(label: "fake-console")
        private let lock = NSLock()
        private var lines: [String] = []

        init(respond: @escaping @Sendable (String) -> String) throws {
            listener = try NWListener(using: .tcp, on: .any)
            listener.newConnectionHandler = { [weak self] connection in
                guard let self else { return }
                connection.start(queue: self.queue)
                connection.send(
                    content: Data("Android Console: Authentication required\r\nOK\r\n".utf8), completion: .idempotent)
                self.receive(on: connection, pending: "", respond: respond)
            }
        }

        func start() async throws -> Int {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Int, any Error>) in
                listener.stateUpdateHandler = { [listener] state in
                    switch state {
                    case .ready: continuation.resume(returning: Int(listener.port?.rawValue ?? 0))
                    case let .failed(error): continuation.resume(throwing: error)
                    default: break
                    }
                }
                listener.start(queue: queue)
            }
        }

        var received: [String] {
            lock.withLock { lines }
        }

        private func receive(
            on connection: NWConnection, pending: String, respond: @escaping @Sendable (String) -> String
        ) {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 1024) { [weak self] data, _, done, _ in
                guard let self, let data, !done else { return }
                var buffer = pending + String(decoding: data, as: UTF8.self)
                while let newline = buffer.firstIndex(of: "\n") {
                    let line = String(buffer[..<newline])
                    buffer = String(buffer[buffer.index(after: newline)...])
                    self.lock.withLock { self.lines.append(line) }
                    connection.send(content: Data("\(respond(line))\r\n".utf8), completion: .idempotent)
                }
                self.receive(on: connection, pending: buffer, respond: respond)
            }
        }

        func stop() {
            listener.cancel()
        }
    }

    @Test func authenticatesAndRunsCommandsInOrder() async throws {
        let temp = try TemporaryDirectory()
        let token = temp.appending("token")
        try "secret\n".write(to: token, atomically: true, encoding: .utf8)
        let fake = try FakeConsole { _ in "OK" }
        defer { fake.stop() }
        let port = try await fake.start()

        try await EmulatorConsole(port: port, tokenFile: token).run(["network speed lte", "gsm data home"])
        #expect(fake.received == ["auth secret", "network speed lte", "gsm data home"])
    }

    @Test func stopsAtTheFirstRejectedCommand() async throws {
        let fake = try FakeConsole { $0.hasPrefix("network") ? "KO: bad speed" : "OK" }
        defer { fake.stop() }
        let port = try await fake.start()
        let console = EmulatorConsole(port: port, tokenFile: URL(filePath: "/nonexistent/token"))

        await #expect(throws: EmulatorConsoleError.rejected(command: "network", "bad speed")) {
            try await console.run(["network speed nope", "gsm data home"])
        }
        #expect(fake.received == ["network speed nope"])
    }

    @Test func timesOutWhenTheConsoleIsSilent() async throws {
        let fake = try FakeConsole { _ in "still thinking" }
        defer { fake.stop() }
        let port = try await fake.start()
        let console = EmulatorConsole(
            port: port, tokenFile: URL(filePath: "/nonexistent/token"), timeout: .milliseconds(300))

        await #expect(throws: EmulatorConsoleError.timedOut) {
            try await console.run(["network speed lte"])
        }
    }
}
