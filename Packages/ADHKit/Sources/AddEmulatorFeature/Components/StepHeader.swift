import DesignSystem
import SwiftUI

struct StepHeader: View {
    let current: AddEmulatorModel.Step

    var body: some View {
        HStack(spacing: Spacing.small) {
            step(1, "Select Hardware", .hardware)
            Rectangle()
                .fill(.separator)
                .frame(width: 32, height: 1)
            step(2, "Configure", .configure)
            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Step \(current.rawValue + 1) of 2")
    }

    private func step(_ number: Int, _ title: String, _ step: AddEmulatorModel.Step) -> some View {
        let isCurrent = step == current
        let isDone = step.rawValue < current.rawValue
        return HStack(spacing: Spacing.xSmall) {
            Image(systemName: isDone ? "checkmark.circle.fill" : "\(number).circle\(isCurrent ? ".fill" : "")")
                .foregroundStyle(isCurrent || isDone ? Color.accentColor : .secondary)
            Text(title)
                .fontWeight(isCurrent ? .semibold : .regular)
                .foregroundStyle(isCurrent ? .primary : .secondary)
        }
    }
}
