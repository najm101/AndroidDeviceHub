import Foundation

/// Looks up string resources in a compiled `resources.arsc`.
struct ResourceTable {
    private let reader: BinaryReader
    private let globalPool: StringPool
    /// Package id → offset of its chunk.
    private let packages: [UInt8: Int]

    init(_ data: Data) throws {
        reader = BinaryReader(data)
        guard try reader.uint16(0) == ChunkType.table else { throw APKMetadataError.malformed("not a resource table") }
        var offset = Int(try reader.uint16(2))
        var pool: StringPool?
        var packages: [UInt8: Int] = [:]
        while offset + 8 <= reader.count {
            let type = try reader.uint16(offset)
            let size = try reader.int(offset + 4)
            guard size >= 8 else { throw APKMetadataError.malformed("chunk size") }
            if type == ChunkType.stringPool, pool == nil {
                pool = try StringPool(reader: reader, at: offset)
            } else if type == ChunkType.tablePackage {
                packages[UInt8(truncatingIfNeeded: try reader.uint32(offset + 8))] = offset
            }
            offset += size
        }
        guard let pool else { throw APKMetadataError.malformed("no string pool") }
        globalPool = pool
        self.packages = packages
    }

    /// The string for a resource id, preferring the default configuration, then English.
    func string(for id: UInt32, depth: Int = 0) throws -> String? {
        guard depth < 5 else { return nil }
        let packageID = UInt8(id >> 24)
        let typeID = UInt8((id >> 16) & 0xFF)
        let entryIndex = Int(id & 0xFFFF)
        // Shared libraries use package id 0 at build time.
        guard let package = packages[packageID] ?? (packages.count == 1 ? packages.values.first : nil) else {
            return nil
        }

        var best: (rank: Int, value: ResourceValue)?
        let headerSize = Int(try reader.uint16(package + 2))
        let packageEnd = package + (try reader.int(package + 4))
        var offset = package + headerSize
        while offset + 8 <= packageEnd {
            let type = try reader.uint16(offset)
            let size = try reader.int(offset + 4)
            guard size >= 8 else { throw APKMetadataError.malformed("chunk size") }
            if type == ChunkType.tableType, try reader.uint8(offset + 8) == typeID,
                let value = try entry(entryIndex, inTypeChunk: offset)
            {
                let rank = try configRank(typeChunk: offset)
                if best == nil || rank < best!.rank {
                    best = (rank, value)
                    if rank == 0 { break }
                }
            }
            offset += size
        }
        switch best?.value {
        case let .string(text): return text
        case let .reference(next) where next != id: return try string(for: next, depth: depth + 1)
        default: return nil
        }
    }

    // MARK: - Type chunks

    private func entry(_ index: Int, inTypeChunk chunk: Int) throws -> ResourceValue? {
        let flags = try reader.uint8(chunk + 9)
        let entryCount = try reader.int(chunk + 12)
        let entriesStart = chunk + (try reader.int(chunk + 16))
        let headerSize = Int(try reader.uint16(chunk + 2))
        let offsets = chunk + headerSize
        let isSparse = flags & 0x01 != 0
        let isOffset16 = flags & 0x02 != 0

        var entryOffset: Int?
        if isSparse {
            // Sorted (index, offset / 4) pairs.
            var low = 0
            var high = entryCount - 1
            while low <= high {
                let middle = (low + high) / 2
                let key = Int(try reader.uint16(offsets + middle * 4))
                if key == index {
                    entryOffset = Int(try reader.uint16(offsets + middle * 4 + 2)) * 4
                    break
                }
                if key < index { low = middle + 1 } else { high = middle - 1 }
            }
        } else if index < entryCount {
            if isOffset16 {
                let value = try reader.uint16(offsets + index * 2)
                entryOffset = value == 0xFFFF ? nil : Int(value) * 4
            } else {
                let value = try reader.uint32(offsets + index * 4)
                entryOffset = value == 0xFFFF_FFFF ? nil : Int(value)
            }
        }
        guard let entryOffset else { return nil }
        let entry = entriesStart + entryOffset
        let entryFlags = try reader.uint16(entry + 2)
        if entryFlags & 0x0008 != 0 {
            // Compact entry: key (2), flags with the data type in the high byte (2), data (4).
            return try value(type: UInt8(entryFlags >> 8), data: try reader.uint32(entry + 4))
        }
        guard entryFlags & 0x0001 == 0 else { return nil }  // complex (bag) entries aren't strings
        let size = Int(try reader.uint16(entry))
        let valueOffset = entry + size
        return try value(type: try reader.uint8(valueOffset + 3), data: try reader.uint32(valueOffset + 4))
    }

    private func value(type: UInt8, data: UInt32) throws -> ResourceValue {
        switch type {
        case 0x03: .string(try globalPool.string(at: Int(data)))
        case 0x01: .reference(data)
        default: .other
        }
    }

    /// 0 for the default configuration, 1 for English without other qualifiers, 2 for English, 3 otherwise.
    private func configRank(typeChunk chunk: Int) throws -> Int {
        let config = chunk + 20
        let size = try reader.int(config)
        let fields = try reader.bytes(config + 4, max(0, size - 4))
        if fields.allSatisfy({ $0 == 0 }) { return 0 }
        // imsi (4 bytes), then language (2) and country (2).
        let language = fields.count >= 6 ? String(decoding: fields[4..<6], as: UTF8.self) : ""
        guard language == "en" else { return 3 }
        let others = fields.enumerated().filter { !(4..<6).contains($0.offset) }.map(\.element)
        return others.allSatisfy { $0 == 0 } ? 1 : 2
    }
}
