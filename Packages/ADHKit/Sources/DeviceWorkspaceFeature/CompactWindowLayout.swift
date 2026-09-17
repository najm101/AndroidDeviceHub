public import CoreGraphics
import DesignSystem

/// Sizes of the compact window: the device drawing plus a fixed margin and footer.
///
/// Sizes are the window's content area below the title bar. Only the device area scales; the margin
/// and footer keep their size, so the device keeps its shape at any window size.
public struct CompactWindowLayout: Equatable, Sendable {
    /// Width divided by height of the whole device drawing (frame included).
    public var deviceAspectRatio: CGFloat

    /// Empty space around the device, on every side.
    public static let margin = Spacing.medium
    /// Height of the compact footer.
    public static let footerHeight: CGFloat = 52
    /// The footer's controls need this much width.
    public static let minimumWidth: CGFloat = 260
    /// Below this width the title is hidden, so the toolbar buttons don't move into the overflow menu.
    public static let titleMinimumWidth: CGFloat = 400
    /// The device is never drawn shorter than this.
    public static let minimumDeviceHeight: CGFloat = 200

    public init(deviceAspectRatio: CGFloat) {
        self.deviceAspectRatio = max(deviceAspectRatio, 0.05)
    }

    /// The content size that shows the device `deviceHeight` points tall.
    public func contentSize(deviceHeight: CGFloat) -> CGSize {
        CGSize(
            width: (deviceHeight * deviceAspectRatio + 2 * Self.margin).rounded(),
            height: (deviceHeight + 2 * Self.margin + Self.footerHeight).rounded()
        )
    }

    /// The device height shown by a content area of `size`.
    public func deviceHeight(in size: CGSize) -> CGFloat {
        size.height - 2 * Self.margin - Self.footerHeight
    }

    /// The smallest content size: wide enough for the footer, and not below the minimum device height.
    public var minimumContentSize: CGSize {
        let heightForWidth = (Self.minimumWidth - 2 * Self.margin) / deviceAspectRatio
        return contentSize(deviceHeight: max(Self.minimumDeviceHeight, heightForWidth))
    }

    /// The largest device height whose content fits in `bounds`.
    public func maximumDeviceHeight(fitting bounds: CGSize) -> CGFloat {
        let byHeight = bounds.height - 2 * Self.margin - Self.footerHeight
        let byWidth = (bounds.width - 2 * Self.margin) / deviceAspectRatio
        return max(0, min(byHeight, byWidth))
    }

    /// Snaps a size proposed by a window resize to the device's shape.
    ///
    /// The dimension the user changed more (measured in device points) decides the new size, so
    /// dragging a side edge scales by width and dragging the bottom edge scales by height.
    public func resized(from current: CGSize, to proposed: CGSize, within bounds: CGSize) -> CGSize {
        let byWidth = (proposed.width - 2 * Self.margin) / deviceAspectRatio
        let byHeight = proposed.height - 2 * Self.margin - Self.footerHeight
        let widthChange = abs(proposed.width - current.width) / deviceAspectRatio
        let heightChange = abs(proposed.height - current.height)
        let wanted = widthChange >= heightChange ? byWidth : byHeight
        return contentSize(deviceHeight: clampedDeviceHeight(wanted, within: bounds))
    }

    /// The size for a device that changed shape (e.g. rotated): its longer side keeps its length.
    public func rotated(from previous: CompactWindowLayout, content: CGSize, within bounds: CGSize) -> CGSize {
        let height = previous.deviceHeight(in: content)
        let longSide = max(height, height * previous.deviceAspectRatio)
        let newHeight = deviceAspectRatio >= 1 ? longSide / deviceAspectRatio : longSide
        return contentSize(deviceHeight: clampedDeviceHeight(newHeight, within: bounds))
    }

    /// Clamps a device height between the minimum size and what fits in `bounds`.
    public func clampedDeviceHeight(_ height: CGFloat, within bounds: CGSize) -> CGFloat {
        let minimum = deviceHeight(in: minimumContentSize)
        return max(minimum, min(height, maximumDeviceHeight(fitting: bounds)))
    }
}
