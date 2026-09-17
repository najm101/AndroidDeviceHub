public import Foundation

/// A snapshot of environment variables, injectable for tests.
public struct ProcessEnvironment: Sendable, Equatable {
    public var values: [String: String]
    public var homeDirectory: URL

    public init(values: [String: String], homeDirectory: URL) {
        self.values = values
        self.homeDirectory = homeDirectory
    }

    public static var current: ProcessEnvironment {
        ProcessEnvironment(
            values: ProcessInfo.processInfo.environment,
            homeDirectory: FileManager.default.homeDirectoryForCurrentUser
        )
    }

    /// The value of `name`, or `nil` when it is unset or blank.
    public subscript(name: String) -> String? {
        guard let value = values[name]?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }

    /// Expands a leading `~` against ``homeDirectory``.
    public func url(forPath path: String) -> URL {
        if path == "~" { return homeDirectory }
        if path.hasPrefix("~/") {
            return homeDirectory.appending(path: String(path.dropFirst(2)), directoryHint: .isDirectory)
        }
        return URL(filePath: path, directoryHint: .isDirectory)
    }
}
