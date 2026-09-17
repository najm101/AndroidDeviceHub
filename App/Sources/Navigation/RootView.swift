import DesignSystem
import OnboardingFeature
import SwiftUI

struct RootView: View {
    @Bindable var app: AppModel

    var body: some View {
        Group {
            switch app.phase {
            case .launching:
                ProgressView("Checking your Android SDK…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case let .onboarding(model):
                OnboardingView(model: model)
            case .ready:
                MainSplitView(app: app)
            }
        }
        // The compact window is only as big as the device.
        .frame(
            minWidth: app.isCompact ? nil : Layout.mainWindowMinWidth,
            minHeight: app.isCompact ? nil : Layout.mainWindowMinHeight
        )
        .task { await app.launch() }
    }
}
