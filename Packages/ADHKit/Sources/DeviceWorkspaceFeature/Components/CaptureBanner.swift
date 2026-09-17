import DesignSystem
import SwiftUI

/// "Screenshot saved" confirmation with a Show in Finder button.
struct CaptureBanner: View {
    let model: DeviceWorkspaceModel

    var body: some View {
        if let url = model.lastCapture {
            HStack(spacing: Spacing.small) {
                Image(systemName: Symbol.success)
                    .foregroundStyle(.green)
                Text("Saved \(url.lastPathComponent)")
                    .lineLimit(1)
                    .truncationMode(.middle)
                Button("Show in Finder", action: model.revealLastCapture)
                    .buttonStyle(.borderless)
                Button("Dismiss", systemImage: "xmark", action: model.dismissCapture)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
            }
            .font(.callout)
            .padding(.horizontal, Spacing.medium)
            .padding(.vertical, Spacing.small)
            .glassEffect()
            .padding(.top, Spacing.medium)
            .transition(.move(edge: .top).combined(with: .opacity))
            .task(id: url) {
                try? await Task.sleep(for: .seconds(6))
                if model.lastCapture == url { model.dismissCapture() }
            }
        }
    }
}
