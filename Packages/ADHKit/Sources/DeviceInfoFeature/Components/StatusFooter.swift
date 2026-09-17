import DesignSystem
import SwiftUI

/// A short confirmation at the bottom of an inspector page.
struct StatusFooter: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: Spacing.small) {
            Image(systemName: Symbol.success)
                .foregroundStyle(.green)
            Text(message)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
        }
        .font(.callout)
        .padding(.horizontal, Spacing.medium)
        .padding(.vertical, Spacing.small)
        .background(.bar)
        .task(id: message) {
            try? await Task.sleep(for: .seconds(4))
            onDismiss()
        }
    }
}
