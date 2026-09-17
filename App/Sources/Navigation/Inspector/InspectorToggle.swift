import DesignSystem
import SwiftUI

/// Shows or hides the right-hand inspector.
struct InspectorToggle: View {
    @Binding var isVisible: Bool

    var body: some View {
        Toggle(isOn: $isVisible) {
            Label("Inspector", systemImage: Symbol.inspector)
        }
        .toggleStyle(.button)
        .help(isVisible ? "Hide the inspector (⌥⌘I)" : "Show the inspector (⌥⌘I)")
    }
}
