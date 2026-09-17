import DesignSystem
import DeviceDomain
import SwiftUI

/// Controls under the canvas: rotate on the left, navigation keys in the center, capture on the right.
struct WorkspaceFooter: View {
    let model: DeviceWorkspaceModel

    var body: some View {
        HStack(spacing: Spacing.small) {
            GlassButtonGroup {
                button("Rotate", Symbol.rotateLeft, .rotate, help: "Rotate left", action: model.rotate)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            GlassButtonGroup {
                button("Back", Symbol.back, .navigationKeys) { model.press(.back) }
                button("Home", Symbol.home, .navigationKeys) { model.press(.home) }
                button("Recents", Symbol.recents, .navigationKeys) { model.press(.recents) }
            }

            GlassButtonGroup {
                recordButton
                button("Screenshot", Symbol.screenshot, .screenshot, action: model.takeScreenshot)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, model.isCompact ? CompactWindowLayout.margin : Spacing.large)
        .padding(.vertical, model.isCompact ? 0 : Spacing.medium)
        .frame(height: model.isCompact ? CompactWindowLayout.footerHeight : nil)
    }

    @ViewBuilder private var recordButton: some View {
        if let start = model.recordingStart {
            Button(action: model.toggleRecording) {
                HStack(spacing: Spacing.xSmall) {
                    Image(systemName: "stop.circle.fill")
                        .foregroundStyle(.red)
                    // The timer is left out of the narrow compact footer.
                    if !model.isCompact {
                        Text(start, style: .timer)
                            .monospacedDigit()
                            .font(.callout)
                    }
                }
            }
            .help("Stop recording")
            .accessibilityLabel("Stop recording")
        } else {
            button("Record", Symbol.record, .record, action: model.toggleRecording)
        }
    }

    @ViewBuilder
    private func button(
        _ title: String,
        _ symbol: String,
        _ capability: Capability,
        help: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        let availability = model.availability(capability)
        Button(title, systemImage: symbol, action: action)
            .availability(
                isVisible: availability.isVisible,
                isEnabled: availability.isAvailable,
                reason: availability.reason ?? help ?? title
            )
    }
}
