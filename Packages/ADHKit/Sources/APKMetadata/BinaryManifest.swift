import Foundation

/// Reads the application label from a compiled `AndroidManifest.xml`.
enum BinaryManifest {
    static let labelAttributeID: UInt32 = 0x0101_0001

    static func applicationLabel(in data: Data) throws -> ResourceValue? {
        let reader = BinaryReader(data)
        guard try reader.uint16(0) == ChunkType.xml else { throw APKMetadataError.malformed("not binary XML") }
        var offset = Int(try reader.uint16(2))
        var pool: StringPool?
        var resourceIDs: [UInt32] = []

        while offset + 8 <= reader.count {
            let type = try reader.uint16(offset)
            let size = try reader.int(offset + 4)
            guard size >= 8 else { throw APKMetadataError.malformed("chunk size") }
            switch type {
            case ChunkType.stringPool:
                pool = try StringPool(reader: reader, at: offset)
            case ChunkType.xmlResourceMap:
                let headerSize = Int(try reader.uint16(offset + 2))
                let count = (size - headerSize) / 4
                resourceIDs = try (0..<count).map { try reader.uint32(offset + headerSize + $0 * 4) }
            case ChunkType.xmlStartElement:
                guard let pool else { throw APKMetadataError.malformed("no string pool") }
                // Node header (16 bytes), then ns, name, attributeStart, attributeSize, attributeCount…
                let body = offset + 16
                let name = try pool.string(at: try reader.int(body + 4))
                if name == "application" {
                    return try label(reader: reader, pool: pool, resourceIDs: resourceIDs, element: body)
                }
            default:
                break
            }
            offset += size
        }
        return nil
    }

    private static func label(
        reader: BinaryReader, pool: StringPool, resourceIDs: [UInt32], element: Int
    ) throws -> ResourceValue? {
        let attributeStart = Int(try reader.uint16(element + 8))
        let attributeSize = Int(try reader.uint16(element + 10))
        let attributeCount = Int(try reader.uint16(element + 12))
        for index in 0..<attributeCount {
            let attribute = element + attributeStart + index * attributeSize
            let nameIndex = try reader.int(attribute + 4)
            let isLabel =
                nameIndex < resourceIDs.count
                ? resourceIDs[nameIndex] == labelAttributeID
                : (try? pool.string(at: nameIndex)) == "label"
            guard isLabel else { continue }
            let rawValue = try reader.uint32(attribute + 8)
            let dataType = try reader.uint8(attribute + 15)
            let value = try reader.uint32(attribute + 16)
            switch dataType {
            case 0x03: return .string(try pool.string(at: Int(value)))
            case 0x01: return .reference(value)
            default:
                return rawValue != 0xFFFF_FFFF ? .string(try pool.string(at: Int(rawValue))) : nil
            }
        }
        return nil
    }
}
