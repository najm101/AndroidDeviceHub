public import Foundation

/// A device's screen: what the hardware has and what `wm size` / `wm density` currently override.
///
/// Sizes are in the display's natural orientation (portrait for phones).
public struct DisplayMetrics: Hashable, Sendable {
    public var physicalSize: PixelSize
    public var physicalDensity: Int
    public var overrideSize: PixelSize?
    public var overrideDensity: Int?

    public init(physicalSize: PixelSize, physicalDensity: Int, overrideSize: PixelSize? = nil, overrideDensity: Int? = nil) {
        self.physicalSize = physicalSize
        self.physicalDensity = physicalDensity
        self.overrideSize = overrideSize
        self.overrideDensity = overrideDensity
    }

    public var current: DisplayConfiguration {
        DisplayConfiguration(size: overrideSize ?? physicalSize, density: overrideDensity ?? physicalDensity)
    }

    public var physical: DisplayConfiguration {
        DisplayConfiguration(size: physicalSize, density: physicalDensity)
    }

    public var isOverridden: Bool { overrideSize != nil || overrideDensity != nil }

    /// The density that makes `size` show things at their real-world size on this screen.
    ///
    /// Android scales an override size to fit the panel, so each override pixel covers `1 / scale`
    /// real pixels; the density follows that scale.
    public func densityKeepingPhysicalSize(for size: PixelSize) -> Int {
        guard physicalSize.width > 0, physicalSize.height > 0 else { return physicalDensity }
        let scale = max(
            Double(size.width) / Double(physicalSize.width),
            Double(size.height) / Double(physicalSize.height)
        )
        return max(DisplayConfiguration.densityRange.lowerBound, Int((Double(physicalDensity) * scale).rounded()))
    }
}

/// A screen size in pixels plus a density in dpi.
public struct DisplayConfiguration: Hashable, Sendable {
    public static let sizeRange = 240...8192
    public static let densityRange = 72...1280

    public var size: PixelSize
    public var density: Int

    public init(size: PixelSize, density: Int) {
        self.size = size
        self.density = density
    }

    /// The size apps see, in density-independent pixels.
    public var sizeDP: PixelSize {
        guard density > 0 else { return size }
        return PixelSize(width: size.width * 160 / density, height: size.height * 160 / density)
    }

    /// Why Android would reject this configuration, if it would.
    public var validationError: String? {
        let sizes = Self.sizeRange
        if !sizes.contains(size.width) || !sizes.contains(size.height) {
            return "Width and height must be between \(sizes.lowerBound) and \(sizes.upperBound) pixels."
        }
        if !Self.densityRange.contains(density) {
            return "Density must be between \(Self.densityRange.lowerBound) and \(Self.densityRange.upperBound) dpi."
        }
        return nil
    }
}

/// A screen shape in density-independent pixels, e.g. a 1280 × 800 dp tablet.
public struct ScreenPreset: Hashable, Codable, Sendable, Identifiable {
    public var name: String
    /// The short side, in dp.
    public var shortSideDP: Int
    /// The long side, in dp.
    public var longSideDP: Int

    public var id: String { "\(name)-\(shortSideDP)x\(longSideDP)" }

    public init(name: String, widthDP: Int, heightDP: Int) {
        self.name = name
        shortSideDP = min(widthDP, heightDP)
        longSideDP = max(widthDP, heightDP)
    }

    /// Android's reference sizes for each window size class.
    public static let builtIn: [ScreenPreset] = [
        ScreenPreset(name: "Phone", widthDP: 411, heightDP: 914),
        ScreenPreset(name: "Foldable", widthDP: 673, heightDP: 841),
        ScreenPreset(name: "Small Tablet", widthDP: 600, heightDP: 960),
        ScreenPreset(name: "Tablet", widthDP: 800, heightDP: 1280),
        ScreenPreset(name: "Large Tablet", widthDP: 1024, heightDP: 1366),
        ScreenPreset(name: "Desktop", widthDP: 1080, heightDP: 1920),
    ]

    /// The largest configuration with this shape that fits the physical screen, in its orientation.
    ///
    /// The pixel size keeps the preset's aspect ratio (Android letterboxes it) and the density makes
    /// the dp size come out exactly.
    public func configuration(fitting physical: PixelSize) -> DisplayConfiguration {
        let isPortrait = physical.width <= physical.height
        let widthDP = Double(isPortrait ? shortSideDP : longSideDP)
        let heightDP = Double(isPortrait ? longSideDP : shortSideDP)
        let scale = min(Double(physical.width) / widthDP, Double(physical.height) / heightDP)
        let density = Int((160 * scale).rounded())
        // Derive pixels from the rounded density so the dp size matches.
        let pixelsPerDP = Double(density) / 160
        return DisplayConfiguration(
            size: PixelSize(
                width: Int((widthDP * pixelsPerDP).rounded()),
                height: Int((heightDP * pixelsPerDP).rounded())
            ),
            density: density
        )
    }
}

/// Screen size and density overrides of a running device (`wm size` and `wm density`).
///
/// The overrides live on the device until reset or a data wipe; the hardware profile isn't changed.
@MainActor
public protocol DisplayOverriding: AnyObject {
    func displayMetrics() async throws -> DisplayMetrics
    /// Applies an override, or restores the physical values when `nil`.
    func setDisplayOverride(_ configuration: DisplayConfiguration?) async throws
}
