public import SwiftUI

/// A row with a title, a progress bar and an optional cancel button.
public struct TransferRow: View {
    private let title: String
    private let fraction: Double?
    private let detail: String?
    private let onCancel: (() -> Void)?

    public init(_ title: String, fraction: Double?, detail: String? = nil, onCancel: (() -> Void)? = nil) {
        self.title = title
        self.fraction = fraction
        self.detail = detail
        self.onCancel = onCancel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xSmall) {
            HStack {
                Text(title)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                if let onCancel {
                    Button("Cancel", systemImage: "xmark.circle.fill", action: onCancel)
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                }
            }
            if let fraction {
                ProgressView(value: fraction)
            } else {
                ProgressView()
                    .progressViewStyle(.linear)
            }
            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .font(.callout)
    }
}
