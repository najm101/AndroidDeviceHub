public import Foundation
public import SDKDomain

/// A device's screen: what the hardware has and what `wm size` / `wm density` currently override.
///
/// Sizes are in the display's natural orientation (portrait for phones).
public struct DisplayMetrics: Hashable, Sendable {
    public var physicalSize: PixelSize
    public var physicalDensity: Int
    public var overrideSize: PixelSize?
    public var overrideDensity: Int?

    public init(
        physicalSize: PixelSize,
        physicalDensity: Int,
        overrideSize: PixelSize? = nil,
        overrideDensity: Int? = nil
    ) {
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

    /// The part of the panel Android draws on, as fractions of the panel. An override size with another
    /// shape is scaled to fit and centered, leaving black bars.
    public var contentArea: CGRect {
        guard let size = overrideSize, size.width > 0, size.height > 0,
            physicalSize.width > 0, physicalSize.height > 0
        else { return CGRect(x: 0, y: 0, width: 1, height: 1) }
        let panelWidth = Double(physicalSize.width)
        let panelHeight = Double(physicalSize.height)
        let scale = min(panelWidth / Double(size.width), panelHeight / Double(size.height))
        let width = Double(size.width) * scale / panelWidth
        let height = Double(size.height) * scale / panelHeight
        return CGRect(x: (1 - width) / 2, y: (1 - height) / 2, width: width, height: height)
    }

    /// The screen size to draw the device at, in panel pixels: the current size at the panel's density.
    /// A lower density makes the device look bigger, as it would be in real life.
    public var apparentSize: PixelSize {
        let current = current
        guard current.density > 0 else { return current.size }
        let factor = Double(physicalDensity) / Double(current.density)
        return PixelSize(
            width: Int((Double(current.size.width) * factor).rounded()),
            height: Int((Double(current.size.height) * factor).rounded())
        )
    }

    /// How much of the panel's corner rounding still reaches the content, compared with rounding the
    /// content by `panelCorner` of its own short side: 1 without an override, 0 when the black bars
    /// around an override are thicker than the rounding.
    public func cornerScale(panelCorner: Double) -> Double {
        guard overrideSize != nil, panelCorner > 0 else { return 1 }
        let area = contentArea
        let panelWidth = Double(physicalSize.width)
        let panelHeight = Double(physicalSize.height)
        let radius = panelCorner * min(panelWidth, panelHeight)
        let bar = max(area.minX * panelWidth, area.minY * panelHeight)
        let contentShort = min(area.width * panelWidth, area.height * panelHeight)
        guard contentShort > 0 else { return 0 }
        return max(0, radius - bar) / contentShort / panelCorner
    }

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
    /// The metrics last read or applied, so the canvas can follow changes. Observable.
    var knownDisplayMetrics: DisplayMetrics? { get }
    func displayMetrics() async throws -> DisplayMetrics
    /// Applies an override, or restores the physical values when `nil`.
    func setDisplayOverride(_ configuration: DisplayConfiguration?) async throws
}

/// A "Resizable (Experimental)" emulator, which switches between phone, foldable, tablet and desktop
/// screens while running.
@MainActor
public protocol ResizableDisplayControlling: AnyObject {
    /// The presets this device offers, in menu order.
    var resizableModes: [ResizableMode] { get }
    /// The current preset, once the emulator has reported it. Observable.
    var resizableMode: ResizableMode? { get }
    func setResizableMode(_ mode: ResizableMode) async throws
}
