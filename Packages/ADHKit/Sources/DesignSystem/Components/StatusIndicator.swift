public import SwiftUI

/// The small status dot shown next to devices.
public struct StatusIndicator: View {
    public enum Style: Hashable, Sendable {
        case active
        case inactive
        case busy
        case attention

        var color: Color {
            switch self {
            case .active: .green
            case .inactive: .secondary.opacity(0.5)
            case .busy: .orange
            case .attention: .yellow
            }
        }

        var label: String {
            switch self {
            case .active: "Running"
            case .inactive: "Stopped"
            case .busy: "Starting"
            case .attention: "Needs attention"
            }
        }
    }

    private let style: Style

    public init(_ style: Style) {
        self.style = style
    }

    public var body: some View {
        Group {
            switch style {
            case .attention:
                Image(systemName: Symbol.warning)
                    .foregroundStyle(.yellow)
                    .font(.caption)
            case .busy:
                ProgressView()
                    .controlSize(.mini)
            default:
                Circle()
                    .fill(style.color)
                    .frame(width: 8, height: 8)
            }
        }
        .frame(width: 14, height: 14)
        .accessibilityLabel(style.label)
    }
}

#Preview {
    HStack {
        StatusIndicator(.active)
        StatusIndicator(.inactive)
        StatusIndicator(.busy)
        StatusIndicator(.attention)
    }
    .padding()
}
