public import Foundation

/// Small persistent settings (UserDefaults in the app, in-memory in tests).
public protocol KeyValueStore: Sendable {
    func string(forKey key: String) -> String?
    func bool(forKey key: String) -> Bool
    func integer(forKey key: String) -> Int
    func set(_ value: String?, forKey key: String)
    func set(_ value: Bool, forKey key: String)
    func set(_ value: Int, forKey key: String)
}

/// `UserDefaults` is thread-safe; the wrapper only exists to make that explicit to the compiler.
public struct UserDefaultsStore: KeyValueStore, @unchecked Sendable {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func string(forKey key: String) -> String? { defaults.string(forKey: key) }
    public func bool(forKey key: String) -> Bool { defaults.bool(forKey: key) }
    public func integer(forKey key: String) -> Int { defaults.integer(forKey: key) }
    public func set(_ value: String?, forKey key: String) { defaults.set(value, forKey: key) }
    public func set(_ value: Bool, forKey key: String) { defaults.set(value, forKey: key) }
    public func set(_ value: Int, forKey key: String) { defaults.set(value, forKey: key) }
}

public final class InMemoryKeyValueStore: KeyValueStore, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: any Sendable] = [:]

    public init(values: [String: any Sendable] = [:]) {
        self.values = values
    }

    public func string(forKey key: String) -> String? { read(key) as? String }
    public func bool(forKey key: String) -> Bool { read(key) as? Bool ?? false }
    public func integer(forKey key: String) -> Int { read(key) as? Int ?? 0 }
    public func set(_ value: String?, forKey key: String) { write(value, key) }
    public func set(_ value: Bool, forKey key: String) { write(value, key) }
    public func set(_ value: Int, forKey key: String) { write(value, key) }

    private func read(_ key: String) -> (any Sendable)? {
        lock.withLock { values[key] }
    }

    private func write(_ value: (any Sendable)?, _ key: String) {
        lock.withLock { values[key] = value }
    }
}

/// Keys shared across modules.
public enum PreferenceKey {
    public static let sdkRootOverride = "sdk.rootOverride"
    public static let onboardingCompletedVersion = "onboarding.completedVersion"
    public static let platformToolsSkipped = "onboarding.platformToolsSkipped"
    public static let defaultBootMode = "preferences.defaultBootMode"
    public static let showEmulatorWindow = "preferences.showEmulatorWindow"
    public static let captureFolder = "preferences.captureFolder"
    public static let recordingQuality = "preferences.recordingQuality"
}
