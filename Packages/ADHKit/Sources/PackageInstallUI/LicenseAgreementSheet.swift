import DesignSystem
import SwiftUI

/// A full-text license with Accept/Decline, shown before a download.
struct LicenseAgreementSheet: View {
    private let title: String
    private let text: String
    private let onAccept: () -> Void
    private let onDecline: () -> Void

    init(title: String, text: String, onAccept: @escaping () -> Void, onDecline: @escaping () -> Void) {
        self.title = title
        self.text = text
        self.onAccept = onAccept
        self.onDecline = onDecline
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.large) {
            VStack(alignment: .leading, spacing: Spacing.xSmall) {
                Text("License Agreement")
                    .font(.title2.bold())
                Text(title)
                    .foregroundStyle(.secondary)
            }
            ScrollView {
                Text(text)
                    .font(.callout.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Spacing.medium)
            }
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: CornerRadius.medium))
            HStack {
                Spacer()
                Button("Decline", role: .cancel, action: onDecline)
                    .keyboardShortcut(.cancelAction)
                Button("Accept", action: onAccept)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Spacing.xLarge)
        .frame(width: 620, height: 560)
    }
}
