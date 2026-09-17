public import SwiftUI

/// The icon shown by `StatusRow`.
public enum StatusState: Hashable, Sendable {
    case success
    case warning
    case failure
    case optional
    case pending
}

/// A row with a status icon, a title, a detail line and an optional trailing accessory.
public struct StatusRow<Accessory: View>: View {
    private let title: String
    private let detail: String
    private let state: StatusState
    private let accessory: Accessory

    public init(_ title: String, detail: String, state: StatusState, @ViewBuilder accessory: () -> Accessory) {
        self.title = title
        self.detail = detail
        self.state = state
        self.accessory = accessory()
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.medium) {
            icon
                .frame(width: 18)
            VStack(alignment: .leading, spacing: Spacing.xxSmall) {
                Text(title)
                    .font(.body.weight(.medium))
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }
            Spacer(minLength: Spacing.medium)
            accessory
        }
        .padding(.vertical, Spacing.xSmall)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var icon: some View {
        switch state {
        case .success:
            Image(systemName: Symbol.success).foregroundStyle(.green)
        case .warning:
            Image(systemName: Symbol.warning).foregroundStyle(.yellow)
        case .failure:
            Image(systemName: Symbol.failure).foregroundStyle(.red)
        case .optional:
            Image(systemName: Symbol.optional).foregroundStyle(.secondary)
        case .pending:
            ProgressView().controlSize(.small)
        }
    }
}

public extension StatusRow where Accessory == EmptyView {
    init(_ title: String, detail: String, state: StatusState) {
        self.init(title, detail: detail, state: state) { EmptyView() }
    }
}
