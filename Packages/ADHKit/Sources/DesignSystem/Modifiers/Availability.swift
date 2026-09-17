public import SwiftUI

public extension View {
    /// Hides or disables a control based on a capability's availability.
    @ViewBuilder
    func availability(isVisible: Bool, isEnabled: Bool, reason: String?) -> some View {
        if isVisible {
            disabled(!isEnabled)
                .help(reason ?? "")
        }
    }
}
