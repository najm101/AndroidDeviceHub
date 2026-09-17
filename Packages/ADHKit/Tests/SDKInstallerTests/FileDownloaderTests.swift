import Foundation
import Synchronization
import Testing

@testable import SDKInstaller

/// Serves canned responses: `/ok` returns `StubProtocol.body` in chunks, anything else is a 404.
private final class StubProtocol: URLProtocol {
    static let body = Data((0..<300_000).map { UInt8($0 % 251) })

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }
        let found = url.path == "/ok"
        let response = HTTPURLResponse(
            url: url,
            statusCode: found ? 200 : 404,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Length": "\(found ? Self.body.count : 0)"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if found {
            for start in stride(from: 0, to: Self.body.count, by: 64_000) {
                client?.urlProtocol(self, didLoad: Self.body[start..<min(start + 64_000, Self.body.count)])
            }
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

struct FileDownloaderTests {
    let downloader: FileDownloader = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        return FileDownloader(session: URLSession(configuration: configuration))
    }()

    func temporaryFile() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "FileDownloaderTests-\(UUID().uuidString)", directoryHint: .isDirectory)
            .appending(path: "archive.zip", directoryHint: .notDirectory)
    }

    @Test func reportsProgressAndMovesTheFileIntoPlace() async throws {
        let destination = temporaryFile()
        defer { try? FileManager.default.removeItem(at: destination.deletingLastPathComponent()) }
        let reports = Mutex<[(received: Int64, total: Int64)]>([])

        try await downloader.download(
            URL(string: "https://stub.test/ok")!, to: destination, expectedSize: 1
        ) { received, total, _ in
            reports.withLock { $0.append((received, total)) }
        }

        #expect(try Data(contentsOf: destination) == StubProtocol.body)
        let first = try #require(reports.withLock { $0.first })
        #expect(first.received > 0)
        #expect(first.total == Int64(StubProtocol.body.count))
    }

    @Test func failedResponsesThrowAndLeaveNoFile() async throws {
        let destination = temporaryFile()
        defer { try? FileManager.default.removeItem(at: destination.deletingLastPathComponent()) }

        await #expect(throws: URLError(.badServerResponse)) {
            try await downloader.download(
                URL(string: "https://stub.test/missing")!, to: destination, expectedSize: 1
            ) { _, _, _ in }
        }
        #expect(!FileManager.default.fileExists(atPath: destination.path))
    }
}
