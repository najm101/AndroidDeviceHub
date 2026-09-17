import DesignSystem
import DeviceDomain
import SwiftUI

/// The device outline sized to the window (or the chosen zoom).
struct DeviceCanvas<Content: View>: View {
    let aspectSize: PixelSize?
    let style: DeviceFrameStyle
    let zoom: DeviceWorkspaceModel.Zoom
    var cornerScale: CGFloat = 1
    @ViewBuilder let content: Content

    var body: some View {
        let size = aspectSize ?? PixelSize(width: 1080, height: 2400)
        let silhouette = DeviceSilhouette(
            aspectRatio: CGFloat(size.aspectRatio), style: style, cornerScale: cornerScale
        ) {
            content
        }
        switch zoom {
        case .fit:
            silhouette
        case let .scale(scale):
            // 100 % shows one device pixel per Mac pixel on a Retina display.
            let screen = CGSize(width: Double(size.width) / 2 * scale, height: Double(size.height) / 2 * scale)
            let footprint = style.footprint(forScreen: screen)
            ScrollView([.horizontal, .vertical]) {
                silhouette
                    .frame(width: footprint.width, height: footprint.height)
            }
        }
    }
}
