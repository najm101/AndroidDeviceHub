import DeviceDomain
import Foundation

/// Decodes `logcat -B` output: a stream of `logger_entry` headers, each followed by
/// `priority`, `tag\0` and `message\0`.
struct LogcatDecoder {
    private var pending = Data()
    private var nextID = 0

    mutating func append(_ data: Data) {
        pending.append(data)
    }

    mutating func entries() -> [LogEntry] {
        var result: [LogEntry] = []
        while pending.count >= 4 {
            let payloadLength = Int(pending.littleEndianUInt16(at: 0))
            let headerSize = Int(pending.littleEndianUInt16(at: 2))
            // Version 1 headers have no size field (it's padding and reads 0).
            let effectiveHeader = headerSize == 0 ? 20 : headerSize
            guard pending.count >= effectiveHeader + payloadLength else { break }
            let entryData = pending.prefix(effectiveHeader + payloadLength)
            pending.removeFirst(effectiveHeader + payloadLength)
            if let entry = decode(Data(entryData), headerSize: effectiveHeader, payloadLength: payloadLength) {
                result.append(entry)
            }
        }
        return result
    }

    private mutating func decode(_ data: Data, headerSize: Int, payloadLength: Int) -> LogEntry? {
        guard headerSize >= 20, payloadLength >= 3 else { return nil }
        let pid = Int(Int32(bitPattern: data.littleEndianUInt32(at: 4)))
        let tid = Int(data.littleEndianUInt32(at: 8))
        let seconds = TimeInterval(data.littleEndianUInt32(at: 12))
        let nanoseconds = TimeInterval(data.littleEndianUInt32(at: 16))
        let uid = headerSize >= 28 ? Int(data.littleEndianUInt32(at: 24)) : nil

        let payload = data.suffix(payloadLength)
        let priority = payload[payload.startIndex]
        let rest = payload.dropFirst()
        guard let tagEnd = rest.firstIndex(of: 0) else { return nil }
        let tag = String(decoding: rest[rest.startIndex..<tagEnd], as: UTF8.self)
        var messageBytes = rest[(tagEnd + 1)...]
        while let last = messageBytes.last, last == 0 || last == 10 {
            messageBytes = messageBytes.dropLast()
        }
        nextID += 1
        return LogEntry(
            id: nextID,
            date: Date(timeIntervalSince1970: seconds + nanoseconds / 1_000_000_000),
            pid: pid,
            tid: tid,
            uid: uid,
            level: LogLevel(rawValue: Int(priority)) ?? (priority > 7 ? .fatal : .verbose),
            tag: tag,
            message: String(decoding: messageBytes, as: UTF8.self)
        )
    }
}

extension Data {
    fileprivate func littleEndianUInt16(at offset: Int) -> UInt16 {
        UInt16(self[startIndex + offset]) | UInt16(self[startIndex + offset + 1]) << 8
    }

    fileprivate func littleEndianUInt32(at offset: Int) -> UInt32 {
        (0..<4).reduce(UInt32(0)) { $0 | UInt32(self[startIndex + offset + $1]) << ($1 * 8) }
    }
}
