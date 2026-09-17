import Foundation

public enum FormFactor: String, CaseIterable, Codable, Hashable, Sendable, Identifiable {
    case phone
    case tablet
    case foldable
    case wear
    case tv
    case automotive
    case desktop
    case xr

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .phone: "Phone"
        case .tablet: "Tablet"
        case .foldable: "Foldable"
        case .wear: "Wear OS"
        case .tv: "TV"
        case .automotive: "Automotive"
        case .desktop: "Desktop"
        case .xr: "XR"
        }
    }

    public var symbolName: String {
        switch self {
        case .phone: "iphone"
        case .tablet: "ipad"
        case .foldable: "ipad.landscape.and.iphone"
        case .wear: "applewatch"
        case .tv: "tv"
        case .automotive: "car"
        case .desktop: "desktopcomputer"
        case .xr: "visionpro"
        }
    }

    /// Maps system image tag ids to form factors. Phone, tablet and foldable share generic images (`nil`).
    public init?(imageTagID: String) {
        let id = imageTagID.lowercased()
        switch true {
        case id.hasPrefix("android-wear"): self = .wear
        case id.hasPrefix("android-tv"), id.hasPrefix("google-tv"): self = .tv
        case id.hasPrefix("android-automotive"): self = .automotive
        case id.hasPrefix("android-desktop"): self = .desktop
        case id.contains("xr"), id.hasPrefix("ai-glasses"): self = .xr
        default: return nil
        }
    }

    /// Whether this form factor uses the generic phone/tablet images.
    public var usesMobileImages: Bool {
        switch self {
        case .phone, .tablet, .foldable: true
        default: false
        }
    }
}

/// A device definition (screen, RAM, cameras…) used to create an emulator.
public struct HardwareProfile: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var manufacturer: String
    public var formFactor: FormFactor
    public var tagID: String?
    public var playStore: Bool
    public var diagonalInches: Double
    public var widthPixels: Int
    public var heightPixels: Int
    public var density: Int
    public var isRound: Bool
    public var ramMiB: Int
    public var hasHardwareKeyboard: Bool
    public var hasHardwareButtons: Bool
    public var hasDPad: Bool
    public var hasFrontCamera: Bool
    public var hasBackCamera: Bool
    public var skin: String?
    public var minAPI: Int?
    public var maxAPI: Int?
    public var isFoldable: Bool
    public var source: String

    public init(
        id: String, name: String, manufacturer: String, formFactor: FormFactor, tagID: String? = nil,
        playStore: Bool, diagonalInches: Double, widthPixels: Int, heightPixels: Int, density: Int,
        isRound: Bool = false, ramMiB: Int, hasHardwareKeyboard: Bool = false, hasHardwareButtons: Bool = false,
        hasDPad: Bool = false, hasFrontCamera: Bool = true, hasBackCamera: Bool = true, skin: String? = nil,
        minAPI: Int? = nil, maxAPI: Int? = nil, isFoldable: Bool = false, source: String = "devices"
    ) {
        self.id = id
        self.name = name
        self.manufacturer = manufacturer
        self.formFactor = formFactor
        self.tagID = tagID
        self.playStore = playStore
        self.diagonalInches = diagonalInches
        self.widthPixels = widthPixels
        self.heightPixels = heightPixels
        self.density = density
        self.isRound = isRound
        self.ramMiB = ramMiB
        self.hasHardwareKeyboard = hasHardwareKeyboard
        self.hasHardwareButtons = hasHardwareButtons
        self.hasDPad = hasDPad
        self.hasFrontCamera = hasFrontCamera
        self.hasBackCamera = hasBackCamera
        self.skin = skin
        self.minAPI = minAPI
        self.maxAPI = maxAPI
        self.isFoldable = isFoldable
        self.source = source
    }

    public var resolutionText: String { "\(widthPixels)×\(heightPixels)" }
    public var sizeText: String { diagonalInches.formatted(.number.precision(.fractionLength(0...1))) + "″" }

    /// Whether a system image can run on this hardware.
    public func supports(_ image: SystemImageDetails) -> Bool {
        if let minAPI, image.apiLevel.major < minAPI { return false }
        if let maxAPI, image.apiLevel.major > maxAPI { return false }
        if playStore == false, image.hasPlayStore { return false }
        switch (formFactor.usesMobileImages, image.formFactor) {
        case (true, nil): return true
        case (false, let imageFactor?): return imageFactor == formFactor
        default: return false
        }
    }

    /// The default RAM for a new emulator: the device RAM capped for the host, in MiB.
    public var recommendedRAMMiB: Int {
        switch formFactor {
        case .wear: min(ramMiB, 2048)
        case .tablet, .desktop, .automotive, .xr: min(ramMiB, 4096)
        default: min(ramMiB, 2048)
        }
    }
}
