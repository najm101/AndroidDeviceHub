public import SwiftUI

/// The kind of hardware a generated device frame imitates.
public enum DeviceFrameStyle: Hashable, Sendable {
    case phone
    case foldable
    case tablet
    case roundWatch
    case squareWatch
    case tv
    case automotive
    case desktop

    /// Proportions, as fractions of the screen's shorter side.
    struct Metrics {
        var bezel: CGFloat
        var screenCorner: CGFloat
        /// Extra room around the body for buttons or a crown (each side, horizontally).
        var sideExtra: CGFloat = 0
        /// Extra room below the body for a stand.
        var bottomExtra: CGFloat = 0
    }

    var metrics: Metrics {
        switch self {
        case .phone, .foldable: Metrics(bezel: 0.035, screenCorner: 0.09, sideExtra: 0.014)
        case .tablet: Metrics(bezel: 0.06, screenCorner: 0.035)
        case .roundWatch: Metrics(bezel: 0.09, screenCorner: 0.5, sideExtra: 0.07)
        case .squareWatch: Metrics(bezel: 0.09, screenCorner: 0.2, sideExtra: 0.07)
        case .tv: Metrics(bezel: 0.02, screenCorner: 0.006, bottomExtra: 0.13)
        case .automotive: Metrics(bezel: 0.05, screenCorner: 0.03)
        case .desktop: Metrics(bezel: 0.03, screenCorner: 0.012, bottomExtra: 0.16)
        }
    }

    var isRound: Bool { self == .roundWatch }

    /// How round the screen's corners are, as a fraction of its shorter side.
    public var screenCornerFraction: CGFloat { metrics.screenCorner }

    /// The whole frame's size for a screen of `screen` points.
    public func footprint(forScreen screen: CGSize) -> CGSize {
        let short = min(screen.width, screen.height)
        return CGSize(
            width: screen.width + short * 2 * (metrics.bezel + metrics.sideExtra),
            height: screen.height + short * (2 * metrics.bezel + metrics.bottomExtra)
        )
    }
}
