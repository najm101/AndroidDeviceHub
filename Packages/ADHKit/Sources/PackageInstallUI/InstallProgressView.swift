import DesignSystem
public import SDKDomain
public import SwiftUI

/// A compact progress indicator with a cancel button.
public struct InstallProgressView: View {
    private let progress: InstallProgress
    private let onCancel: () -> Void

    public init(progress: InstallProgress, onCancel: @escaping () -> Void) {
        self.progress = progress
        self.onCancel = onCancel
    }

    public var body: some View {
        HStack(spacing: Spacing.small) {
            VStack(alignment: .trailing, spacing: Spacing.xxSmall) {
                if let fraction = progress.fractionCompleted {
                    ProgressView(value: fraction)
                        .frame(width: 140)
                } else {
                    ProgressView()
                        .progressViewStyle(.linear)
                        .frame(width: 140)
                }
                Text(progress.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Button("Cancel", systemImage: "xmark.circle.fill", action: onCancel)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .disabled(progress.phase == .extracting || progress.phase == .finishing)
        }
    }
}
