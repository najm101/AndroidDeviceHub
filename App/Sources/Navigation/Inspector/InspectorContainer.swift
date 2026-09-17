import DesignSystem
import DeviceInfoFeature
import DeviceSettingsFeature
import FilesFeature
import ReportsFeature
import SwiftUI

/// The right-hand inspector: the selected tab's content.
struct InspectorContainer: View {
    @Bindable var app: AppModel

    var body: some View {
        Group {
            if let id = app.selection, let tab = app.effectiveInspectorTab {
                switch tab {
                case .settings: DeviceSettingsInspectorView(model: app.settings(for: id))
                case .reports: ReportsInspectorView(model: app.reports(for: id))
                case .info: DeviceInfoInspectorView(model: app.info(for: id))
                case .files: FilesInspectorView(model: app.files(for: id))
                }
            }
        }
        .id(app.selection)
    }
}

/// The inspector's tabs, shown in the toolbar next to the inspector toggle.
struct InspectorTabPicker: View {
    @Bindable var app: AppModel

    var body: some View {
        Picker("Inspector", selection: selectedTab) {
            ForEach(app.visibleInspectorTabs) { tab in
                Label(tab.title, systemImage: tab.symbol)
                    .help(tab.title)
                    .tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .labelStyle(.iconOnly)
        .labelsHidden()
    }

    private var selectedTab: Binding<AppModel.InspectorTab> {
        Binding {
            app.effectiveInspectorTab ?? .settings
        } set: {
            app.inspectorTab = $0
        }
    }
}
