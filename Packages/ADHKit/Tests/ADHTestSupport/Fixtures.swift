public import Foundation

/// Locates files in `Tests/Fixtures`. Symlinked into each test target that needs fixtures.
public enum Fixtures {
    public static let root = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appending(path: "Fixtures", directoryHint: .isDirectory)

    public static func url(_ relativePath: String) -> URL {
        root.appending(path: relativePath, directoryHint: .notDirectory)
    }

    public static func data(_ relativePath: String) throws -> Data {
        try Data(contentsOf: url(relativePath))
    }
}

/// A temporary directory removed when the test finishes.
public final class TemporaryDirectory {
    public let url: URL

    public init() throws {
        url = FileManager.default.temporaryDirectory
            .appending(path: "ADHKitTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }

    public func appending(_ path: String, isDirectory: Bool = false) -> URL {
        url.appending(path: path, directoryHint: isDirectory ? .isDirectory : .notDirectory)
    }

    public func write(_ text: String, to path: String) throws {
        let file = appending(path)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: file)
    }
}
