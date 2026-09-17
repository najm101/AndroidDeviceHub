import SwiftUI

/// Where everything goes, in the frame's own coordinates.
struct FrameLayout {
    let size: CGSize
    let body: CGRect
    let screen: CGRect
    let short: CGFloat
    let bodyCorner: CGFloat
    let screenCorner: CGFloat
    let isLandscape: Bool

    init(style: DeviceFrameStyle, aspectRatio: CGFloat, available: CGSize) {
        let metrics = style.metrics
        // Scale a unit-height screen so the whole footprint fits.
        let unitShort = min(aspectRatio, 1)
        let widthPerUnit = aspectRatio + unitShort * 2 * (metrics.bezel + metrics.sideExtra)
        let heightPerUnit = 1 + unitShort * (2 * metrics.bezel + metrics.bottomExtra)
        let scale = max(0, min(available.width / widthPerUnit, available.height / heightPerUnit))

        let screenSize = CGSize(width: aspectRatio * scale, height: scale)
        short = min(screenSize.width, screenSize.height)
        let bezel = short * metrics.bezel
        let side = short * metrics.sideExtra
        size = CGSize(width: widthPerUnit * scale, height: heightPerUnit * scale)
        body = CGRect(
            x: side, y: 0, width: screenSize.width + bezel * 2, height: screenSize.height + bezel * 2)
        screen = CGRect(x: side + bezel, y: bezel, width: screenSize.width, height: screenSize.height)
        screenCorner = style.isRound ? short / 2 : short * metrics.screenCorner
        bodyCorner = style.isRound ? body.height / 2 : screenCorner + bezel
        isLandscape = aspectRatio > 1
    }

    var screenShape: some InsettableShape {
        RoundedRectangle(cornerRadius: screenCorner, style: .continuous)
    }
}
