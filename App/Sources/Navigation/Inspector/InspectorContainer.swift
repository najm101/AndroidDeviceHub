import DesignSystem
import DeviceInfoFeature
import DeviceSettingsFeature
import FilesFeature
import ReportsFeature
import SwiftUI

/// The right-hand inspector with its four tabs.
struct InspectorContainer: View {
    @Bindable var app: AppModel

    var body: some View {
        VStack(spacing: 0) {
            let tabs = app.visibleInspectorTabs
            if tabs.count > 1 {
                Picker("Inspector", selection: selectedTab) {
                    ForEach(tabs) { tab in
                        Label(tab.title, systemImage: tab.symbol).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .labelStyle(.iconOnly)
                .labelsHidden()
                .padding(Spacing.medium)
                Divider()
            }
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
            .frame(maxHeight: .infinity)
        }
    }

    private var selectedTab: Binding<AppModel.InspectorTab> {
        Binding {
            app.effectiveInspectorTab ?? .settings
        } set: {
            app.inspectorTab = $0
        }
    }
}
