import Foundation

/// Little-endian reads with bounds checks. Out-of-range reads throw instead of trapping.
struct BinaryReader {
    let data: Data

    init(_ data: Data) {
        // Rebase so offsets start at zero.
        self.data = Data(data)
    }

    var count: Int { data.count }

    func uint8(_ offset: Int) throws -> UInt8 {
        try check(offset, 1)
        return data[offset]
    }

    func uint16(_ offset: Int) throws -> UInt16 {
        try check(offset, 2)
        return UInt16(data[offset]) | UInt16(data[offset + 1]) << 8
    }

    func uint32(_ offset: Int) throws -> UInt32 {
        try check(offset, 4)
        return (0..<4).reduce(UInt32(0)) { $0 | UInt32(data[offset + $1]) << ($1 * 8) }
    }

    func int(_ offset: Int) throws -> Int { Int(try uint32(offset)) }

    func bytes(_ offset: Int, _ length: Int) throws -> Data {
        try check(offset, length)
        return data.subdata(in: offset..<(offset + length))
    }

    private func check(_ offset: Int, _ length: Int) throws {
        guard offset >= 0, length >= 0, offset + length <= data.count else {
            throw APKMetadataError.malformed("read past the end at \(offset)")
        }
    }
}

public enum APKMetadataError: Error, Equatable {
    case malformed(String)
}

/// Chunk types from `ResourceTypes.h`.
enum ChunkType {
    static let stringPool: UInt16 = 0x0001
    static let table: UInt16 = 0x0002
    static let xml: UInt16 = 0x0003
    static let xmlStartElement: UInt16 = 0x0102
    static let xmlResourceMap: UInt16 = 0x0180
    static let tablePackage: UInt16 = 0x0200
    static let tableType: UInt16 = 0x0201
}

/// A `ResStringPool` chunk.
struct StringPool {
    private let reader: BinaryReader
    private let start: Int
    private let stringCount: Int
    private let stringsStart: Int
    private let isUTF8: Bool

    init(reader: BinaryReader, at start: Int) throws {
        guard try reader.uint16(start) == ChunkType.stringPool else {
            throw APKMetadataError.malformed("expected a string pool")
        }
        self.reader = reader
        self.start = start
        stringCount = try reader.int(start + 8)
        isUTF8 = try reader.uint32(start + 16) & 0x100 != 0
        stringsStart = start + (try reader.int(start + 20))
    }

    func string(at index: Int) throws -> String {
        guard index >= 0, index < stringCount else { throw APKMetadataError.malformed("string \(index)") }
        let headerSize = Int(try reader.uint16(start + 2))
        let offset = stringsStart + (try reader.int(start + headerSize + index * 4))
        if isUTF8 {
            // UTF-16 length (skipped), then UTF-8 byte length; each is 1 or 2 bytes.
            var position = offset + (try reader.uint8(offset) & 0x80 != 0 ? 2 : 1)
            var length = Int(try reader.uint8(position))
            if length & 0x80 != 0 {
                length = (length & 0x7F) << 8 | Int(try reader.uint8(position + 1))
                position += 2
            } else {
                position += 1
            }
            return String(decoding: try reader.bytes(position, length), as: UTF8.self)
        }
        var length = Int(try reader.uint16(offset))
        var position = offset + 2
        if length & 0x8000 != 0 {
            length = (length & 0x7FFF) << 16 | Int(try reader.uint16(offset + 2))
            position += 2
        }
        let units = try (0..<length).map { try reader.uint16(position + $0 * 2) }
        return String(decoding: units, as: UTF16.self)
    }
}

/// A typed value (`Res_value`).
enum ResourceValue: Equatable {
    case string(String)
    case reference(UInt32)
    case other
}
