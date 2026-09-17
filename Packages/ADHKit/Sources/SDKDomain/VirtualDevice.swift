public import Foundation

/// An Android Virtual Device (AVD) read from disk.
public struct VirtualDevice: Hashable, Sendable, Identifiable {
    /// The AVD id (`AvdId`), which is also the folder and `.ini` name.
    public var id: String
    public var displayName: String
    public var directory: URL
    public var iniFile: URL
    public var sysdir: String?
    public var apiLevel: APILevel?
    public var tagID: String?
    public var tagDisplay: String?
    public var abi: ABI?
    public var hasPlayStore: Bool
    public var hardwareProfileID: String?
    public var manufacturer: String?
    public var screenWidth: Int?
    public var screenHeight: Int?
    public var density: Int?
    public var ramMiB: Int?
    public var cpuCores: Int?
    public var dataPartitionBytes: Int64?
    public var skinName: String?
    public var skinPath: String?
    /// `runtime.network.*`, applied when the emulator boots.
    public var networkSpeed: NetworkSpeed?
    public var networkLatency: NetworkLatency?
    /// The screen presets of a resizable emulator; empty for every other device.
    public var resizableScreens: [ResizableScreen]
    /// Problems found while reading, e.g. a missing system image.
    public var issues: [VirtualDeviceIssue]

    public init(
        id: String, displayName: String, directory: URL, iniFile: URL, sysdir: String? = nil,
        apiLevel: APILevel? = nil, tagID: String? = nil, tagDisplay: String? = nil, abi: ABI? = nil,
        hasPlayStore: Bool = false, hardwareProfileID: String? = nil, manufacturer: String? = nil,
        screenWidth: Int? = nil, screenHeight: Int? = nil, density: Int? = nil, ramMiB: Int? = nil,
        cpuCores: Int? = nil, dataPartitionBytes: Int64? = nil, skinName: String? = nil, skinPath: String? = nil,
        networkSpeed: NetworkSpeed? = nil, networkLatency: NetworkLatency? = nil,
        resizableScreens: [ResizableScreen] = [], issues: [VirtualDeviceIssue] = []
    ) {
        self.id = id
        self.displayName = displayName
        self.directory = directory
        self.iniFile = iniFile
        self.sysdir = sysdir
        self.apiLevel = apiLevel
        self.tagID = tagID
        self.tagDisplay = tagDisplay
        self.abi = abi
        self.hasPlayStore = hasPlayStore
        self.hardwareProfileID = hardwareProfileID
        self.manufacturer = manufacturer
        self.screenWidth = screenWidth
        self.screenHeight = screenHeight
        self.density = density
        self.ramMiB = ramMiB
        self.cpuCores = cpuCores
        self.dataPartitionBytes = dataPartitionBytes
        self.skinName = skinName
        self.skinPath = skinPath
        self.networkSpeed = networkSpeed
        self.networkLatency = networkLatency
        self.resizableScreens = resizableScreens
        self.issues = issues
    }

    public var services: ImageServices? { tagID.map(ImageServices.init(tagID:)) }
}

public enum VirtualDeviceIssue: Hashable, Sendable {
    /// `image.sysdir.1` points at a folder that is not installed.
    case missingSystemImage(sysdir: String)
    /// `config.ini` is missing or unreadable.
    case unreadableConfiguration(reason: String)

    public var message: String {
        switch self {
        case let .missingSystemImage(sysdir): "System image not installed (\(sysdir))"
        case let .unreadableConfiguration(reason): "Configuration can't be read: \(reason)"
        }
    }
}

// MARK: - Creating devices

public enum BootMode: String, CaseIterable, Hashable, Sendable, Identifiable {
    case quick
    case cold

    public var id: String { rawValue }
    public var title: String { self == .quick ? "Quick boot" : "Cold boot" }
}

public enum GraphicsMode: String, CaseIterable, Hashable, Sendable, Identifiable {
    case auto
    case host
    case software = "swiftshader_indirect"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .auto: "Automatic"
        case .host: "Hardware"
        case .software: "Software"
        }
    }
}

public enum Orientation: String, CaseIterable, Hashable, Sendable, Identifiable {
    case portrait
    case landscape

    public var id: String { rawValue }
    public var title: String { rawValue.capitalized }
}

public enum CameraMode: String, CaseIterable, Hashable, Sendable, Identifiable {
    case none
    case emulated
    case virtualScene = "virtualscene"
    case webcam = "webcam0"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .none: "None"
        case .emulated: "Emulated"
        case .virtualScene: "Virtual scene"
        case .webcam: "Mac camera"
        }
    }
}

public enum NetworkSpeed: String, CaseIterable, Hashable, Sendable, Identifiable {
    case full, lte, hsdpa, umts, edge, gprs, gsm

    public var id: String { rawValue }
    public var title: String { self == .full ? "Full" : rawValue.uppercased() }
}

public enum NetworkLatency: String, CaseIterable, Hashable, Sendable, Identifiable {
    case none, umts, edge, gprs

    public var id: String { rawValue }
    public var title: String { self == .none ? "None" : rawValue.uppercased() }
}

/// Everything needed to create a new virtual device.
public struct VirtualDeviceSpecification: Hashable, Sendable {
    public var id: String
    public var displayName: String
    public var profile: HardwareProfile
    public var image: SystemImageDetails
    public var cpuCores: Int
    public var ramMiB: Int
    public var vmHeapMiB: Int
    public var internalStorageMiB: Int
    public var sdCardMiB: Int?
    public var orientation: Orientation
    public var bootMode: BootMode
    public var graphics: GraphicsMode
    public var useHostKeyboard: Bool
    public var frontCamera: CameraMode
    public var backCamera: CameraMode
    public var networkSpeed: NetworkSpeed
    public var networkLatency: NetworkLatency
    /// Absolute path of a skin folder, when one is installed.
    public var skinPath: URL?

    public init(
        id: String, displayName: String, profile: HardwareProfile, image: SystemImageDetails,
        cpuCores: Int, ramMiB: Int, vmHeapMiB: Int, internalStorageMiB: Int, sdCardMiB: Int?,
        orientation: Orientation, bootMode: BootMode, graphics: GraphicsMode, useHostKeyboard: Bool,
        frontCamera: CameraMode, backCamera: CameraMode, networkSpeed: NetworkSpeed,
        networkLatency: NetworkLatency, skinPath: URL?
    ) {
        self.id = id
        self.displayName = displayName
        self.profile = profile
        self.image = image
        self.cpuCores = cpuCores
        self.ramMiB = ramMiB
        self.vmHeapMiB = vmHeapMiB
        self.internalStorageMiB = internalStorageMiB
        self.sdCardMiB = sdCardMiB
        self.orientation = orientation
        self.bootMode = bootMode
        self.graphics = graphics
        self.useHostKeyboard = useHostKeyboard
        self.frontCamera = frontCamera
        self.backCamera = backCamera
        self.networkSpeed = networkSpeed
        self.networkLatency = networkLatency
        self.skinPath = skinPath
    }
}

/// Rules for AVD ids.
public enum VirtualDeviceName {
    /// Turns a display name into a valid id: `Pixel 8 API 36` → `Pixel_8_API_36`.
    public static func id(fromDisplayName name: String) -> String {
        let mapped = name.unicodeScalars.map { scalar -> Character in
            isAllowed(scalar) ? Character(scalar) : "_"
        }
        var result = String(mapped)
        while result.contains("__") {
            result = result.replacingOccurrences(of: "__", with: "_")
        }
        return result.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
    }

    public static func isValidID(_ id: String) -> Bool {
        !id.isEmpty && id.unicodeScalars.allSatisfy(isAllowed)
    }

    private static func isAllowed(_ scalar: Unicode.Scalar) -> Bool {
        scalar.isASCII && (CharacterSet.alphanumerics.contains(scalar) || "._-".unicodeScalars.contains(scalar))
    }
}
