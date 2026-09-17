import Foundation
public import SDKDomain

/// Identifies a device across launches.
public enum DeviceID: Hashable, Sendable, Codable, CustomStringConvertible {
    /// An emulator, by AVD id.
    case emulator(avdID: String)
    /// A physical device, by ADB serial.
    case physical(serial: String)

    public var description: String {
        switch self {
        case let .emulator(avdID): "emulator:\(avdID)"
        case let .physical(serial): "physical:\(serial)"
        }
    }
}

public enum DeviceKind: Hashable, Sendable {
    case emulator
    case physical(Connection)

    public enum Connection: Hashable, Sendable {
        case usb
        case wifi
    }
}

public enum DeviceState: Hashable, Sendable {
    case stopped
    case starting
    /// Running. `inAppControl` is false when the emulator was started by another tool
    /// or is shown in its own window.
    case running(inAppControl: Bool)
    /// The device can't be used until something is fixed.
    case needsAttention(DeviceProblem)

    public var isRunning: Bool {
        switch self {
        case .running, .starting: true
        default: false
        }
    }
}

public enum DeviceProblem: Hashable, Sendable {
    case missingSystemImage(sysdir: String)
    case unreadable(reason: String)

    public var message: String {
        switch self {
        case .missingSystemImage: "System image not installed"
        case let .unreadable(reason): reason
        }
    }
}

/// Something the UI can offer for a device. Views check capabilities, never device kinds.
public enum Capability: String, CaseIterable, Hashable, Sendable {
    // Lifecycle
    case start, coldBoot, shutDown, restart
    // Management
    case revealInFinder, rename, duplicate, wipeData, remove
    // Canvas
    case screen, input, zoom, compactWindow, keyboardMode, rotate, navigationKeys, screenshot, record
    // Inspector
    case settings, reports, info, apps, profiles, files
    // Emulator settings (sections of Inspector ▸ Settings)
    case location, battery, network, telephony, sensors, posture, fingerprint, display, microphone, clipboard
    case snapshots
    /// Screen size and density overrides (over ADB).
    case displaySize
}

/// Whether a capability can be used right now.
public enum Availability: Hashable, Sendable {
    case available
    /// Shown but disabled, with the reason as a tooltip.
    case disabled(reason: String)
    /// Not offered for this device at all.
    case hidden

    public var isAvailable: Bool { self == .available }
    public var isVisible: Bool { self != .hidden }
    public var reason: String? {
        if case let .disabled(reason) = self { return reason }
        return nil
    }
}

/// A screen size in device pixels.
public struct PixelSize: Hashable, Sendable {
    public var width: Int
    public var height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }

    /// Width divided by height.
    public var aspectRatio: Double {
        height > 0 ? Double(width) / Double(height) : 1
    }
}

/// A device shown in the sidebar and workspace.
public struct Device: Hashable, Sendable, Identifiable {
    public var id: DeviceID
    public var name: String
    public var kind: DeviceKind
    public var state: DeviceState
    public var apiLevel: APILevel?
    public var formFactor: FormFactor
    public var screenSize: PixelSize?
    public var hasPlayStore: Bool
    /// Capabilities with their current availability. Missing entries are hidden.
    public var capabilities: [Capability: Availability]
    /// The backing AVD, for emulators.
    public var virtualDevice: VirtualDevice?

    public init(
        id: DeviceID,
        name: String,
        kind: DeviceKind,
        state: DeviceState,
        apiLevel: APILevel?,
        formFactor: FormFactor,
        screenSize: PixelSize?,
        hasPlayStore: Bool,
        capabilities: [Capability: Availability],
        virtualDevice: VirtualDevice?
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.state = state
        self.apiLevel = apiLevel
        self.formFactor = formFactor
        self.screenSize = screenSize
        self.hasPlayStore = hasPlayStore
        self.capabilities = capabilities
        self.virtualDevice = virtualDevice
    }

    public func availability(of capability: Capability) -> Availability {
        capabilities[capability] ?? .hidden
    }

    /// "Android 16 · API 36"
    public var versionSummary: String {
        guard let apiLevel else { return "Unknown Android version" }
        return "\(apiLevel.androidVersionTitle) · API \(apiLevel)"
    }
}
