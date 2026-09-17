public import SwiftUI

/// A drawn device frame (body, rim, buttons, crown or stand) around a screen of an exact aspect ratio.
/// Used for the live canvas and for previews; no device artwork is needed.
public struct DeviceSilhouette<Content: View>: View {
    private let aspectRatio: CGFloat
    private let style: DeviceFrameStyle
    private let content: Content

    /// - Parameter aspectRatio: screen width divided by height.
    public init(aspectRatio: CGFloat, style: DeviceFrameStyle = .phone, @ViewBuilder content: () -> Content) {
        self.aspectRatio = style.isRound ? 1 : max(0.2, min(aspectRatio, 5))
        self.style = style
        self.content = content()
    }

    public init(aspectRatio: CGFloat, isRound: Bool, @ViewBuilder content: () -> Content) {
        self.init(aspectRatio: aspectRatio, style: isRound ? .roundWatch : .phone, content: content)
    }

    public var body: some View {
        GeometryReader { proxy in
            let layout = FrameLayout(style: style, aspectRatio: aspectRatio, available: proxy.size)
            ZStack(alignment: .topLeading) {
                FrameArtwork(style: style, layout: layout)
                content
                    .frame(width: layout.screen.width, height: layout.screen.height)
                    .background(.black)
                    .clipShape(layout.screenShape)
                    .offset(x: layout.screen.minX, y: layout.screen.minY)
            }
            .frame(width: layout.size.width, height: layout.size.height, alignment: .topLeading)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// The body, rim and hardware details. Everything here is decoration and ignores clicks.
private struct FrameArtwork: View {
    let style: DeviceFrameStyle
    let layout: FrameLayout

    private static let metal = LinearGradient(
        colors: [Color(white: 0.24), Color(white: 0.11)], startPoint: .top, endPoint: .bottom)
    private static let rim = LinearGradient(
        colors: [.white.opacity(0.45), .white.opacity(0.08), .white.opacity(0.2)],
        startPoint: .topLeading, endPoint: .bottomTrailing)

    var body: some View {
        ZStack(alignment: .topLeading) {
            hardware
            bodyShape
                .fill(Self.metal)
                .frame(width: layout.body.width, height: layout.body.height)
                .shadow(color: .black.opacity(0.28), radius: layout.short * 0.05, y: layout.short * 0.02)
                .offset(x: layout.body.minX, y: layout.body.minY)
            bodyShape
                .strokeBorder(Self.rim, lineWidth: max(1, layout.short * 0.006))
                .frame(width: layout.body.width, height: layout.body.height)
                .offset(x: layout.body.minX, y: layout.body.minY)
            // A thin dark ring where the glass meets the bezel.
            layout.screenShape
                .inset(by: -max(0.5, layout.short * 0.004))
                .stroke(.black.opacity(0.9), lineWidth: max(1, layout.short * 0.008))
                .frame(width: layout.screen.width, height: layout.screen.height)
                .offset(x: layout.screen.minX, y: layout.screen.minY)
            details
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var bodyShape: some InsettableShape {
        RoundedRectangle(cornerRadius: layout.bodyCorner, style: .continuous)
    }

    /// Parts that stick out from behind the body.
    @ViewBuilder private var hardware: some View {
        let body = layout.body
        let short = layout.short
        switch style {
        case .phone, .foldable:
            let thickness = short * 0.022
            if layout.isLandscape {
                // Rotated left: the right edge is now on top.
                button(
                    x: body.minX + body.width * 0.24, y: body.minY - thickness * 0.6,
                    width: body.width * 0.08, height: thickness)
                button(
                    x: body.minX + body.width * 0.36, y: body.minY - thickness * 0.6,
                    width: body.width * 0.14, height: thickness)
            } else {
                button(
                    x: body.maxX - thickness * 0.4, y: body.minY + body.height * 0.22,
                    width: thickness, height: body.height * 0.08)
                button(
                    x: body.maxX - thickness * 0.4, y: body.minY + body.height * 0.34,
                    width: thickness, height: body.height * 0.14)
            }
        case .roundWatch, .squareWatch:
            let crownWidth = short * 0.09
            button(
                x: body.maxX - crownWidth * 0.3, y: body.midY - short * 0.1,
                width: crownWidth, height: short * 0.2, corner: crownWidth * 0.3)
            if style == .squareWatch {
                button(
                    x: body.maxX - crownWidth * 0.5, y: body.midY + short * 0.2,
                    width: crownWidth * 0.6, height: short * 0.14)
            }
        case .tv, .desktop:
            let neckWidth = body.width * 0.05
            let footWidth = body.width * (style == .tv ? 0.34 : 0.26)
            let footHeight = short * 0.025
            Rectangle()
                .fill(Self.metal)
                .frame(width: neckWidth, height: layout.size.height - body.maxY)
                .offset(x: body.midX - neckWidth / 2, y: body.maxY - 1)
            Capsule()
                .fill(Self.metal)
                .frame(width: footWidth, height: footHeight)
                .offset(x: body.midX - footWidth / 2, y: layout.size.height - footHeight)
        case .tablet, .automotive:
            EmptyView()
        }
    }

    /// Details drawn on top of the body.
    @ViewBuilder private var details: some View {
        let body = layout.body
        let bezel = layout.screen.minY - body.minY
        switch style {
        case .tablet:
            let diameter = max(3, bezel * 0.22)
            Circle()
                .fill(Color(white: 0.03))
                .overlay(Circle().strokeBorder(.white.opacity(0.15), lineWidth: 0.5))
                .frame(width: diameter, height: diameter)
                .offset(x: body.midX - diameter / 2, y: body.minY + bezel / 2 - diameter / 2)
        case .foldable where abs(layout.screen.width - layout.screen.height) < layout.short * 0.3:
            // The hinge of an unfolded book-style device.
            ForEach([body.minY, body.maxY - bezel * 0.5], id: \.self) { y in
                Rectangle()
                    .fill(.black.opacity(0.5))
                    .frame(width: max(1, layout.short * 0.006), height: bezel * 0.5)
                    .offset(x: body.midX, y: y)
            }
        default:
            EmptyView()
        }
    }

    private func button(
        x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, corner: CGFloat? = nil
    ) -> some View {
        RoundedRectangle(cornerRadius: corner ?? min(width, height) / 2, style: .continuous)
            .fill(Self.metal)
            .overlay(
                RoundedRectangle(cornerRadius: corner ?? min(width, height) / 2, style: .continuous)
                    .strokeBorder(.white.opacity(0.18), lineWidth: 0.5)
            )
            .frame(width: width, height: height)
            .offset(x: x, y: y)
    }
}

#Preview("Styles") {
    HStack(spacing: 24) {
        DeviceSilhouette(aspectRatio: 1080 / 2400, style: .phone) { Color.blue }
        DeviceSilhouette(aspectRatio: 2400 / 1080, style: .phone) { Color.blue }
        DeviceSilhouette(aspectRatio: 1600 / 2560, style: .tablet) { Color.blue }
        DeviceSilhouette(aspectRatio: 1, style: .roundWatch) { Color.blue }
        DeviceSilhouette(aspectRatio: 16 / 9, style: .tv) { Color.blue }
    }
    .padding(40)
    .frame(width: 1200, height: 400)
}
