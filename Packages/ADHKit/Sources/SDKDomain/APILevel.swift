import Foundation

/// An Android API level such as `36`, `36.1` or `37.2`.
public struct APILevel: Hashable, Comparable, Sendable, CustomStringConvertible {
    public var major: Int
    public var minor: Int

    public init(major: Int, minor: Int = 0) {
        self.major = major
        self.minor = minor
    }

    /// Parses catalog values like `"36"`, `"36.1"` and `"36x"` (extension variants).
    public init?(catalogValue: String) {
        let trimmed = catalogValue.trimmingCharacters(in: .whitespaces)
        let numeric = trimmed.hasSuffix("x") ? String(trimmed.dropLast()) : trimmed
        let parts = numeric.split(separator: ".", omittingEmptySubsequences: false)
        guard let major = parts.first.flatMap({ Int($0) }), parts.count <= 2 else { return nil }
        let minor = parts.count == 2 ? Int(parts[1]) : 0
        guard let minor else { return nil }
        self.init(major: major, minor: minor)
    }

    public static func < (lhs: APILevel, rhs: APILevel) -> Bool {
        (lhs.major, lhs.minor) < (rhs.major, rhs.minor)
    }

    /// `"36"` or `"36.1"`.
    public var description: String {
        minor == 0 ? "\(major)" : "\(major).\(minor)"
    }

    /// The marketing version, e.g. `"16"` for API 36. Unknown future levels return `nil`.
    public var androidVersion: String? {
        Self.androidVersions[major]
    }

    /// `"Android 16"`, or `"API 40"` when the version is unknown.
    public var androidVersionTitle: String {
        androidVersion.map { "Android \($0)" } ?? "API \(description)"
    }

    private static let androidVersions: [Int: String] = [
        21: "5.0", 22: "5.1", 23: "6.0", 24: "7.0", 25: "7.1", 26: "8.0", 27: "8.1", 28: "9",
        29: "10", 30: "11", 31: "12", 32: "12L", 33: "13", 34: "14", 35: "15", 36: "16", 37: "17",
    ]
}

/// Pre-release information attached to a system image.
public enum ReleaseStage: Hashable, Sendable {
    case stable
    case beta(number: Int, targetLevel: APILevel?)
    case canary(build: String?)
    case preview(codename: String)

    public var isPrerelease: Bool {
        if case .stable = self { return false }
        return true
    }

    public var label: String? {
        switch self {
        case .stable: nil
        case let .beta(number, _): "Beta \(number)"
        case .canary: "Canary"
        case let .preview(codename): codename
        }
    }
}
