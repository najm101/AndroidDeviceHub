import Foundation

/// The Google services bundled with a system image.
public enum ImageServices: String, CaseIterable, Hashable, Sendable, Identifiable {
    case googlePlay
    case googleAPIs
    case plainAndroid

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .googlePlay: "Google Play Store"
        case .googleAPIs: "Google APIs"
        case .plainAndroid: "Android Open Source"
        }
    }

    /// Derived from a system image tag folder such as `google_apis_playstore_ps16k`.
    public init(tagID: String) {
        let id = tagID.lowercased()
        if id.contains("playstore") || id.contains("play_store") {
            self = .googlePlay
        } else if id.hasPrefix("google") || id.contains("google_apis") {
            self = .googleAPIs
        } else {
            self = .plainAndroid
        }
    }
}

/// A system image tag, e.g. `google_apis_playstore` / "Google Play".
public struct ImageTag: Hashable, Sendable {
    public var id: String
    public var display: String

    public init(id: String, display: String) {
        self.id = id
        self.display = display
    }
}

/// A CPU architecture of a system image.
public struct ABI: RawRepresentable, Hashable, Sendable, CustomStringConvertible {
    public var rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static let arm64 = ABI(rawValue: "arm64-v8a")
    public static let intel64 = ABI(rawValue: "x86_64")

    /// The value written to `hw.cpu.arch`.
    public var cpuArchitecture: String {
        switch rawValue {
        case "arm64-v8a": "arm64"
        case "armeabi-v7a", "armeabi": "arm"
        case "x86_64": "x86_64"
        case "x86": "x86"
        default: rawValue
        }
    }

    /// The ABI the current Mac can run with hardware acceleration.
    public static var host: ABI {
        #if arch(arm64)
            .arm64
        #else
            .intel64
        #endif
    }

    public var description: String { rawValue }
}

/// A catalog release channel. Lower is more stable.
public enum ReleaseChannel: Int, Comparable, CaseIterable, Hashable, Sendable, Identifiable {
    case stable = 0
    case beta = 1
    case dev = 2
    case canary = 3

    public var id: Int { rawValue }

    public var title: String {
        switch self {
        case .stable: "Stable"
        case .beta: "Beta"
        case .dev: "Dev"
        case .canary: "Canary"
        }
    }

    public static func < (lhs: ReleaseChannel, rhs: ReleaseChannel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
