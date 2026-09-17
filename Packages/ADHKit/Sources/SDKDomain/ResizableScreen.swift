import Foundation

/// The screen presets of a "Resizable (Experimental)" emulator. Raw values match the emulator's
/// `DisplayModeValue` and the ids in `hw.resizable.configs`.
public enum ResizableMode: Int, CaseIterable, Hashable, Sendable, Identifiable {
    case phone = 0
    case foldable = 1
    case tablet = 2
    case desktop = 3

    public var id: Int { rawValue }

    public var title: String {
        switch self {
        case .phone: "Phone"
        case .foldable: "Foldable"
        case .tablet: "Tablet"
        case .desktop: "Desktop"
        }
    }

    public var formFactor: FormFactor {
        switch self {
        case .phone: .phone
        case .foldable: .foldable
        case .tablet: .tablet
        case .desktop: .desktop
        }
    }

    /// The name the emulator uses in `hw.resizable.configs`.
    var configName: String {
        switch self {
        case .phone: "phone"
        case .foldable: "unfolded"
        case .tablet: "tablet"
        case .desktop: "desktop"
        }
    }
}

/// One entry of `hw.resizable.configs`: `name-id-width-height-dpi`.
public struct ResizableScreen: Hashable, Sendable {
    public var mode: ResizableMode
    public var width: Int
    public var height: Int
    public var density: Int

    public init(mode: ResizableMode, width: Int, height: Int, density: Int) {
        self.mode = mode
        self.width = width
        self.height = height
        self.density = density
    }

    /// The emulator's own presets, used when the AVD doesn't list any.
    ///
    /// Emulator 36.5 crashes on start when `hw.resizable.configs` is in `config.ini`, so the app never
    /// writes that key and relies on these built-in values. Desktop isn't supported by that version.
    public static let builtIn: [ResizableScreen] = [
        ResizableScreen(mode: .phone, width: 1080, height: 2340, density: 420),
        ResizableScreen(mode: .foldable, width: 1768, height: 2208, density: 420),
        ResizableScreen(mode: .tablet, width: 1920, height: 1200, density: 240),
    ]

    public static func configValue(_ screens: [ResizableScreen]) -> String {
        screens
            .map { "\($0.mode.configName)-\($0.mode.rawValue)-\($0.width)-\($0.height)-\($0.density)" }
            .joined(separator: ", ")
    }

    /// Reads `hw.resizable.configs`; malformed entries are skipped.
    public static func parse(_ value: String) -> [ResizableScreen] {
        value.split(separator: ",").compactMap { entry in
            let parts = entry.trimmingCharacters(in: .whitespaces).split(separator: "-")
            guard parts.count == 5,
                let id = Int(parts[1]), let mode = ResizableMode(rawValue: id),
                let width = Int(parts[2]), let height = Int(parts[3]), let density = Int(parts[4])
            else { return nil }
            return ResizableScreen(mode: mode, width: width, height: height, density: density)
        }
    }
}

public extension HardwareProfile {
    /// Android Studio's "Resizable (Experimental)" device, which switches between screen presets.
    var isResizable: Bool { id == "resizable" }
}
