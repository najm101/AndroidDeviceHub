public import Foundation

/// Where a resolved path came from, shown in onboarding and Components.
public enum LocationSource: Hashable, Sendable {
    case userSelection
    case environment(variable: String)
    case androidStudio
    case defaultLocation

    public var title: String {
        switch self {
        case .userSelection: "Chosen in Android Device Hub"
        case let .environment(variable): "From $\(variable)"
        case .androidStudio: "From Android Studio settings"
        case .defaultLocation: "Default location"
        }
    }
}

/// The SDK folder and the folder holding virtual devices.
public struct SDKLocation: Hashable, Sendable {
    public var sdkRoot: URL
    public var sdkSource: LocationSource
    public var avdHome: URL
    public var avdSource: LocationSource

    public init(sdkRoot: URL, sdkSource: LocationSource, avdHome: URL, avdSource: LocationSource) {
        self.sdkRoot = sdkRoot
        self.sdkSource = sdkSource
        self.avdHome = avdHome
        self.avdSource = avdSource
    }

    public var emulatorDirectory: URL { sdkRoot.appending(path: "emulator", directoryHint: .isDirectory) }
    public var emulatorExecutable: URL { emulatorDirectory.appending(path: "emulator", directoryHint: .notDirectory) }
    public var platformToolsDirectory: URL {
        sdkRoot.appending(path: "platform-tools", directoryHint: .isDirectory)
    }
    public var adbExecutable: URL { platformToolsDirectory.appending(path: "adb", directoryHint: .notDirectory) }
    public var licensesDirectory: URL { sdkRoot.appending(path: "licenses", directoryHint: .isDirectory) }
    public var skinsDirectory: URL { sdkRoot.appending(path: "skins", directoryHint: .isDirectory) }
    public var temporaryDirectory: URL { sdkRoot.appending(path: ".temp/adh", directoryHint: .isDirectory) }

    public func url(forSysdir sysdir: String) -> URL {
        sdkRoot.appending(path: sysdir, directoryHint: .isDirectory)
    }
}

/// The outcome of looking for the SDK.
public enum SDKLocationResolution: Hashable, Sendable {
    /// An existing SDK folder was found.
    case found(SDKLocation)
    /// No SDK exists yet; `suggested` is where one can be created.
    case notFound(suggested: SDKLocation)

    public var location: SDKLocation {
        switch self {
        case let .found(location), let .notFound(location): location
        }
    }
}
