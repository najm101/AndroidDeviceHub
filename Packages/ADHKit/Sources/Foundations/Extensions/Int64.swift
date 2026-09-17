import Foundation

public extension Int64 {
    static let kibibyte: Int64 = 1024
    static let mebibyte: Int64 = 1024 * 1024
    static let gibibyte: Int64 = 1024 * 1024 * 1024

    /// "1.9 GB" style text for file sizes.
    var formattedFileSize: String {
        formatted(.byteCount(style: .file))
    }
}
