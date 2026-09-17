import DesignSystem
import DeviceDomain
import SwiftUI

struct InfoPage: View {
    let model: DeviceInfoModel

    var body: some View {
        Form {
            ForEach(model.properties) { group in
                Section(group.title) {
                    ForEach(group.properties) { property in
                        KeyValueRow(property.title, value: property.value)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .controlSize(.small)
        .overlay {
            if model.isLoadingInfo {
                ProgressView()
            }
        }
        .toolbarRefresh { await model.loadInfo() }
        .task { await model.loadInfo() }
    }
}
