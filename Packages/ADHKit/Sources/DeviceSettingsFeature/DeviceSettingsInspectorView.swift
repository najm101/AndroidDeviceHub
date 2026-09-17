import DesignSystem
import DeviceDomain
public import SwiftUI

/// Inspector ▸ Settings: collapsible sections for the device's simulated hardware.
public struct DeviceSettingsInspectorView: View {
    @Bindable private var model: DeviceSettingsModel

    public init(model: DeviceSettingsModel) {
        self.model = model
    }

    public var body: some View {
        if model.visibleSections.isEmpty {
            ContentUnavailableView(
                "No Settings", systemImage: Symbol.settings,
                description: Text("Settings appear here while the device runs in the app."))
        } else {
            Form {
                ForEach(model.visibleSections) { section in
                    Section(isExpanded: expansion(of: section)) {
                        if let error = model.errors[section] {
                            ErrorBanner(error) { model.dismissError(in: section) }
                        }
                        content(for: section)
                    } header: {
                        SectionHeader(section: section, isBusy: model.busySections.contains(section))
                    }
                }
            }
            .formStyle(.grouped)
            .controlSize(.small)
        }
    }

    private func expansion(of section: SettingsSection) -> Binding<Bool> {
        Binding {
            model.isExpanded(section)
        } set: {
            model.setExpanded(section, $0)
        }
    }

    @ViewBuilder
    private func content(for section: SettingsSection) -> some View {
        switch section {
        case .location: LocationSection(model: model)
        case .battery: BatterySection(model: model)
        case .network: NetworkSection(model: model)
        case .telephony: TelephonySection(model: model)
        case .sensors: SensorsSection(model: model)
        case .posture: PostureSection(model: model)
        case .fingerprint: FingerprintSection(model: model)
        case .display: DisplaySection(model: model)
        case .screenSize: ScreenSizeSection(model: model)
        case .microphone: MicrophoneSection(model: model)
        case .clipboard: ClipboardSection(model: model)
        case .snapshots: SnapshotsSection(model: model)
        }
    }
}

private struct SectionHeader: View {
    let section: SettingsSection
    let isBusy: Bool

    var body: some View {
        HStack {
            Label(section.title, systemImage: section.systemImage)
            Spacer()
            if isBusy {
                ProgressView().controlSize(.mini)
            }
        }
    }
}
