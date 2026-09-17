import DesignSystem
import DeviceDomain
public import SwiftUI

/// Inspector ▸ Info with its Info, Apps and Profiles pages.
public struct DeviceInfoInspectorView: View {
    @Bindable private var model: DeviceInfoModel

    public init(model: DeviceInfoModel) {
        self.model = model
    }

    public var body: some View {
        VStack(spacing: 0) {
            Picker("Page", selection: $model.page) {
                ForEach(DeviceInfoModel.Page.allCases) { page in
                    Text(page.title).tag(page)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            .padding(.horizontal, Spacing.medium)
            .padding(.vertical, Spacing.small)

            if let error = model.errorMessage {
                ErrorBanner(error) { model.errorMessage = nil }
                    .padding(.horizontal, Spacing.medium)
                    .padding(.bottom, Spacing.small)
            }

            let availability = model.availability(of: model.page)
            Group {
                if let reason = availability.reason {
                    UnavailableHint(model.page.title, systemImage: Symbol.info, reason: reason)
                } else {
                    switch model.page {
                    case .info: InfoPage(model: model)
                    case .apps: AppsPage(model: model)
                    case .profiles: ProfilesPage(model: model)
                    }
                }
            }
            .frame(maxHeight: .infinity)

            if let status = model.statusMessage {
                StatusFooter(message: status, onDismiss: model.dismissStatus)
            }
        }
    }
}
