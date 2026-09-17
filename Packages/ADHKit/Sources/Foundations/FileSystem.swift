public import Foundation

/// File access used by infrastructure modules. The live implementation wraps `FileManager`;
/// tests use a temporary directory with the same live implementation.
public protocol FileSystem: Sendable {
    func fileExists(at url: URL) -> Bool
    func directoryExists(at url: URL) -> Bool
    func contents(of url: URL) throws -> Data
    func write(_ data: Data, to url: URL) throws
    func createDirectory(at url: URL) throws
    func removeItem(at url: URL) throws
    func moveItem(at source: URL, to destination: URL) throws
    func copyItem(at source: URL, to destination: URL) throws
    func contentsOfDirectory(at url: URL) throws -> [URL]
    func isWritableDirectory(at url: URL) -> Bool
    func availableCapacity(at url: URL) -> Int64?
    func allocatedSize(ofDirectory url: URL) -> Int64
    func setExecutable(at url: URL) throws
}

public extension FileSystem {
    func string(contentsOf url: URL) throws -> String {
        let data = try contents(of: url)
        guard let text = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadInapplicableStringEncoding, userInfo: [NSURLErrorKey: url])
        }
        return text
    }

    func write(_ text: String, to url: URL) throws {
        try write(Data(text.utf8), to: url)
    }
}

public struct LiveFileSystem: FileSystem {
    public init() {}

    private var manager: FileManager { .default }

    public func fileExists(at url: URL) -> Bool {
        manager.fileExists(atPath: url.path(percentEncoded: false))
    }

    public func directoryExists(at url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return manager.fileExists(atPath: url.path(percentEncoded: false), isDirectory: &isDirectory)
            && isDirectory.boolValue
    }

    public func contents(of url: URL) throws -> Data {
        try Data(contentsOf: url)
    }

    public func write(_ data: Data, to url: URL) throws {
        try createDirectory(at: url.deletingLastPathComponent())
        try data.write(to: url, options: .atomic)
    }

    public func createDirectory(at url: URL) throws {
        try manager.createDirectory(at: url, withIntermediateDirectories: true)
    }

    public func removeItem(at url: URL) throws {
        guard fileExists(at: url) else { return }
        try manager.removeItem(at: url)
    }

    public func moveItem(at source: URL, to destination: URL) throws {
        try createDirectory(at: destination.deletingLastPathComponent())
        try manager.moveItem(at: source, to: destination)
    }

    public func copyItem(at source: URL, to destination: URL) throws {
        try createDirectory(at: destination.deletingLastPathComponent())
        try manager.copyItem(at: source, to: destination)
    }

    public func contentsOfDirectory(at url: URL) throws -> [URL] {
        try manager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
    }

    public func isWritableDirectory(at url: URL) -> Bool {
        directoryExists(at: url) && manager.isWritableFile(atPath: url.path(percentEncoded: false))
    }

    public func availableCapacity(at url: URL) -> Int64? {
        let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage
    }

    public func allocatedSize(ofDirectory url: URL) -> Int64 {
        let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .isRegularFileKey]
        guard let enumerator = manager.enumerator(at: url, includingPropertiesForKeys: Array(keys)) else {
            return 0
        }
        var total: Int64 = 0
        for case let file as URL in enumerator {
            guard let values = try? file.resourceValues(forKeys: keys), values.isRegularFile == true else {
                continue
            }
            total += Int64(values.totalFileAllocatedSize ?? 0)
        }
        return total
    }

    public func setExecutable(at url: URL) throws {
        try manager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path(percentEncoded: false))
    }
}
