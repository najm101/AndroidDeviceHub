import ComponentsFeature
import PreferencesFeature
import SwiftUI

struct SettingsView: View {
    let app: AppModel

    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") {
                GeneralSettingsView()
            }
            Tab("Components", systemImage: "shippingbox") {
                ComponentsView(model: app.componentsModel)
            }
        }
        .frame(width: 640, height: 560)
    }
}
