import DesignSystem
import SwiftUI

/// Step 2: name, system image and additional settings.
struct ConfigureStepView: View {
    @Bindable var model: AddEmulatorModel

    var body: some View {
        VStack(spacing: 0) {
            Picker("Section", selection: $model.configureTab) {
                Text("Device").tag(AddEmulatorModel.ConfigureTab.device)
                Text("Additional Settings").tag(AddEmulatorModel.ConfigureTab.additionalSettings)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .padding(.top, Spacing.medium)

            switch model.configureTab {
            case .device:
                DeviceTab(model: model)
            case .additionalSettings:
                AdditionalSettingsTab(model: model)
            }
        }
    }
}
