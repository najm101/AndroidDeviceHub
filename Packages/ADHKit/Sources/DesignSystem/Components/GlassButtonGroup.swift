public import SwiftUI

/// Icon buttons sharing one Liquid Glass capsule, sized like the window's toolbar buttons.
///
/// Toolbars group their items this way on their own; this is for controls outside the toolbar.
public struct GlassButtonGroup<Content: View>: View {
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        HStack(spacing: 0) {
            content
        }
        .buttonStyle(GlassGroupItemStyle())
        .toggleStyle(.button)
        .labelStyle(.iconOnly)
        .padding(.horizontal, GlassGroupItemStyle.inset)
        .glassEffect(.regular.interactive(), in: .capsule)
        .fixedSize()
    }
}

/// One button inside a ``GlassButtonGroup``: an icon in a toolbar-sized square with no chrome of its own.
struct GlassGroupItemStyle: ButtonStyle {
    /// Height of a macOS toolbar glass button.
    static let height: CGFloat = 36
    static let inset: CGFloat = 2

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15))
            .padding(.horizontal, Spacing.xSmall)
            .frame(minWidth: Self.height - 2 * Self.inset, minHeight: Self.height)
            .foregroundStyle(isEnabled ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
            .background {
                Capsule()
                    .fill(.primary.opacity(configuration.isPressed ? 0.15 : isHovered ? 0.07 : 0))
                    .padding(.vertical, Self.inset)
            }
            .contentShape(.capsule)
            .onHover { isHovered = isEnabled && $0 }
    }
}
