public import Foundation

/// A file or folder on the device, from the sync protocol.
public struct ADBFileEntry: Hashable, Sendable {
    public var name: String
    /// Unix mode bits, including the file type.
    public var mode: UInt32
    public var size: Int64
    public var modified: Date

    public init(name: String, mode: UInt32, size: Int64, modified: Date) {
        self.name = name
        self.mode = mode
        self.size = size
        self.modified = modified
    }

    public var isDirectory: Bool { mode & 0o170000 == 0o040000 }
    public var isSymbolicLink: Bool { mode & 0o170000 == 0o120000 }
    public var isRegularFile: Bool { mode & 0o170000 == 0o100000 }
    /// The sync protocol reports mode 0 for paths that don't exist or can't be read.
    public var exists: Bool { mode != 0 }
}

/// The sync protocol on one connection: list, stat, pull and push.
///
/// Requests are 4-byte ids followed by a little-endian length and the path. One operation at a time.
public final class ADBSyncSession: @unchecked Sendable {
    static let maxChunk = 64 * 1024

    private let socket: ADBSocket
    private let listV2: Bool
    private let statV2: Bool

    init(socket: ADBSocket, features: Set<String>) {
        self.socket = socket
        listV2 = features.contains("ls_v2")
        statV2 = features.contains("stat_v2")
    }

    public func close() {
        Task { [socket] in
            try? await socket.write(Self.request("QUIT", Data()))
            socket.close()
        }
    }

    // MARK: - List and stat

    public func list(_ path: String) async throws -> [ADBFileEntry] {
        try await socket.write(Self.request(listV2 ? "LIS2" : "LIST", path))
        var entries: [ADBFileEntry] = []
        while true {
            let id = try await readID()
            switch id {
            case "DENT":
                let header = try await socket.read(exactly: 16)
                let name = try await readName(length: header.littleEndianInteger(at: 12, as: UInt32.self))
                entries.append(
                    ADBFileEntry(
                        name: name,
                        mode: header.littleEndianInteger(at: 0),
                        size: Int64(header.littleEndianInteger(at: 4, as: UInt32.self)),
                        modified: Date(
                            timeIntervalSince1970: TimeInterval(header.littleEndianInteger(at: 8, as: UInt32.self)))
                    ))
            case "DNT2":
                let header = try await socket.read(exactly: 72)
                let name = try await readName(length: header.littleEndianInteger(at: 68, as: UInt32.self))
                let error: UInt32 = header.littleEndianInteger(at: 0)
                guard error == 0 else { continue }
                entries.append(Self.entryV2(name: name, stat: header))
            case "DONE":
                _ = try await socket.read(exactly: listV2 ? 72 : 16)
                return entries.filter { $0.name != "." && $0.name != ".." }
            case "FAIL":
                throw ADBError.failed(try await readMessage())
            default:
                throw ADBError.protocolViolation("list \(id)")
            }
        }
    }

    /// Follows symbolic links. Returns an entry with mode 0 when the path doesn't exist.
    public func stat(_ path: String) async throws -> ADBFileEntry {
        let name = (path as NSString).lastPathComponent
        if statV2 {
            try await socket.write(Self.request("STA2", path))
            try await expect("STA2")
            let stat = try await socket.read(exactly: 68)
            let error: UInt32 = stat.littleEndianInteger(at: 0)
            return error == 0
                ? Self.entryV2(name: name, stat: stat)
                : ADBFileEntry(name: name, mode: 0, size: 0, modified: .distantPast)
        }
        try await socket.write(Self.request("STAT", path))
        try await expect("STAT")
        let stat = try await socket.read(exactly: 12)
        return ADBFileEntry(
            name: name,
            mode: stat.littleEndianInteger(at: 0),
            size: Int64(stat.littleEndianInteger(at: 4, as: UInt32.self)),
            modified: Date(timeIntervalSince1970: TimeInterval(stat.littleEndianInteger(at: 8, as: UInt32.self)))
        )
    }

    // MARK: - Transfers

    /// Downloads one file. The local file is replaced.
    public func pull(_ remotePath: String, to localURL: URL, size: Int64, progress: ADBProgress? = nil) async throws {
        let partial = localURL.appendingPathExtension("download")
        FileManager.default.createFile(atPath: partial.path(percentEncoded: false), contents: nil)
        let handle = try FileHandle(forWritingTo: partial)
        var finished = false
        defer {
            try? handle.close()
            if !finished { try? FileManager.default.removeItem(at: partial) }
        }
        try await socket.write(Self.request("RECV", remotePath))
        var received: Int64 = 0
        loop: while true {
            let id = try await readID()
            switch id {
            case "DATA":
                let length = Int(try await socket.readUInt32())
                try handle.write(contentsOf: try await socket.read(exactly: length))
                received += Int64(length)
                progress?(received, max(size, received))
            case "DONE":
                _ = try await socket.readUInt32()
                break loop
            case "FAIL":
                throw ADBError.failed(try await readMessage())
            default:
                throw ADBError.protocolViolation("recv \(id)")
            }
        }
        try handle.close()
        if FileManager.default.fileExists(atPath: localURL.path(percentEncoded: false)) {
            _ = try FileManager.default.replaceItemAt(localURL, withItemAt: partial)
        } else {
            try FileManager.default.moveItem(at: partial, to: localURL)
        }
        finished = true
    }

    /// Uploads one file, creating missing parent folders on the device.
    public func push(
        _ localURL: URL, to remotePath: String, mode: UInt32 = 0o644, progress: ADBProgress? = nil
    ) async throws {
        let values = try localURL.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let size = Int64(values.fileSize ?? 0)
        let modified = UInt32(clamping: Int((values.contentModificationDate ?? Date()).timeIntervalSince1970))
        let handle = try FileHandle(forReadingFrom: localURL)
        defer { try? handle.close() }

        try await socket.write(Self.request("SEND", "\(remotePath),\(mode | 0o100000)"))
        var sent: Int64 = 0
        progress?(0, size)
        while let chunk = try handle.read(upToCount: Self.maxChunk), !chunk.isEmpty {
            try Task.checkCancellation()
            var packet = Data("DATA".utf8)
            packet.appendLittleEndian(UInt32(chunk.count))
            packet.append(chunk)
            try await socket.write(packet)
            sent += Int64(chunk.count)
            progress?(sent, size)
        }
        var done = Data("DONE".utf8)
        done.appendLittleEndian(modified)
        try await socket.write(done)

        let id = try await readID()
        switch id {
        case "OKAY":
            _ = try await socket.readUInt32()
        case "FAIL":
            throw ADBError.failed(try await readMessage())
        default:
            throw ADBError.protocolViolation("send \(id)")
        }
    }

    // MARK: - Wire helpers

    static func request(_ id: String, _ path: String) -> Data {
        request(id, Data(path.utf8))
    }

    static func request(_ id: String, _ payload: Data) -> Data {
        var data = Data(id.utf8)
        data.appendLittleEndian(UInt32(payload.count))
        data.append(payload)
        return data
    }

    /// Decodes the v2 stat block that follows the id (error, dev, ino, mode, nlink, uid, gid, size, times).
    static func entryV2(name: String, stat: Data) -> ADBFileEntry {
        ADBFileEntry(
            name: name,
            mode: stat.littleEndianInteger(at: 20),
            size: stat.littleEndianInteger(at: 36),
            modified: Date(timeIntervalSince1970: TimeInterval(stat.littleEndianInteger(at: 52, as: Int64.self)))
        )
    }

    private func readID() async throws -> String {
        String(decoding: try await socket.read(exactly: 4), as: UTF8.self)
    }

    private func expect(_ expected: String) async throws {
        let id = try await readID()
        if id == "FAIL" { throw ADBError.failed(try await readMessage()) }
        guard id == expected else { throw ADBError.protocolViolation("expected \(expected), got \(id)") }
    }

    private func readMessage() async throws -> String {
        let length = Int(try await socket.readUInt32())
        return String(decoding: try await socket.read(exactly: length), as: UTF8.self)
    }

    private func readName(length: UInt32) async throws -> String {
        String(decoding: try await socket.read(exactly: Int(length)), as: UTF8.self)
    }
}
