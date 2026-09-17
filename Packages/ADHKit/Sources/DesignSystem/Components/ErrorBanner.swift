public import SwiftUI

/// A dismissible inline error message.
public struct ErrorBanner: View {
    private let message: String
    private let onDismiss: () -> Void

    public init(_ message: String, onDismiss: @escaping () -> Void) {
        self.message = message
        self.onDismiss = onDismiss
    }

    public var body: some View {
        HStack(alignment: .top, spacing: Spacing.small) {
            Image(systemName: Symbol.warning)
                .foregroundStyle(.yellow)
            Text(message)
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
            Button("Dismiss", systemImage: "xmark", action: onDismiss)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
        }
        .padding(Spacing.medium)
        .background(.yellow.opacity(0.12), in: RoundedRectangle(cornerRadius: CornerRadius.medium))
    }
}
