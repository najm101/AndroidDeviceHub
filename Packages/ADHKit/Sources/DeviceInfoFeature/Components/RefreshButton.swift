import DesignSystem
import SwiftUI

struct RefreshButton: View {
    let action: @MainActor () async -> Void
    @State private var isRefreshing = false

    var body: some View {
        Button("Refresh", systemImage: Symbol.refresh) {
            isRefreshing = true
            Task {
                await action()
                isRefreshing = false
            }
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .disabled(isRefreshing)
        .help("Refresh")
    }
}

extension View {
    /// A refresh button pinned to the top-right corner of a page.
    func toolbarRefresh(_ action: @escaping @MainActor () async -> Void) -> some View {
        overlay(alignment: .topTrailing) {
            RefreshButton(action: action)
                .padding(Spacing.small)
        }
    }
}
