import Foundation

/// A package revision such as `36.5.11` or `37.2.9 rc1`.
public struct PackageRevision: Hashable, Comparable, Sendable, CustomStringConvertible {
    public var major: Int
    public var minor: Int
    public var micro: Int
    public var preview: Int?

    public init(major: Int, minor: Int = 0, micro: Int = 0, preview: Int? = nil) {
        self.major = major
        self.minor = minor
        self.micro = micro
        self.preview = preview
    }

    /// Parses `"36"`, `"36.5"` or `"36.5.11"`.
    public init?(string: String) {
        let parts = string.split(separator: ".").map { Int($0) }
        guard let major = parts.first ?? nil, parts.count <= 3, !parts.contains(nil) else { return nil }
        self.init(
            major: major,
            minor: parts.count > 1 ? parts[1] ?? 0 : 0,
            micro: parts.count > 2 ? parts[2] ?? 0 : 0
        )
    }

    public static func < (lhs: PackageRevision, rhs: PackageRevision) -> Bool {
        if (lhs.major, lhs.minor, lhs.micro) != (rhs.major, rhs.minor, rhs.micro) {
            return (lhs.major, lhs.minor, lhs.micro) < (rhs.major, rhs.minor, rhs.micro)
        }
        // A final release sorts after its previews.
        switch (lhs.preview, rhs.preview) {
        case let (left?, right?): return left < right
        case (.some, nil): return true
        default: return false
        }
    }

    public var description: String {
        let base = "\(major).\(minor).\(micro)"
        return preview.map { "\(base) rc\($0)" } ?? base
    }
}
