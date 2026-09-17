import DesignSystem
import SwiftUI

/// Shows a spinner until the setting has a value, and reloads it whenever the section opens.
struct LiveContent<Value: Equatable & Sendable, Content: View>: View {
    let setting: LiveSetting<Value>
    @ViewBuilder let content: (Value) -> Content

    var body: some View {
        Group {
            if let value = setting.value {
                content(value)
            } else if setting.isLoading {
                HStack {
                    Spacer()
                    ProgressView().controlSize(.small)
                    Spacer()
                }
            } else {
                Text("Not available")
                    .foregroundStyle(.secondary)
            }
        }
        .task { await setting.load() }
    }
}

/// A slider that only reports its value when the user lets go, so the device isn't flooded with updates.
struct CommitSlider: View {
    let title: String
    let value: Double
    let range: ClosedRange<Double>
    /// Values snap to this step. It isn't passed to `Slider`, which would draw a tick mark per step.
    var step: Double = 1
    let format: (Double) -> String
    let onCommit: (Double) -> Void

    @State private var draft: Double?

    var body: some View {
        LabeledContent {
            HStack(spacing: Spacing.small) {
                Slider(value: binding, in: range) { editing in
                    if !editing, let draft {
                        onCommit(draft)
                        self.draft = nil
                    }
                }
                .labelsHidden()
                Text(format(draft ?? value))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 56, alignment: .trailing)
            }
        } label: {
            Text(title)
        }
        .accessibilityValue(format(draft ?? value))
    }

    private var binding: Binding<Double> {
        Binding {
            draft ?? value
        } set: {
            draft = (($0 / step).rounded() * step).clamped(to: range)
        }
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
