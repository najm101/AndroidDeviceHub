import DesignSystem
import DeviceDomain
import SwiftUI

struct BatterySection: View {
    let model: DeviceSettingsModel

    var body: some View {
        LiveContent(setting: model.battery) { battery in
            CommitSlider(
                title: "Charge level",
                value: Double(battery.level),
                range: 0...100,
                format: { ($0 / 100).formatted(.percent.precision(.fractionLength(0))) },
                onCommit: { level in model.updateBattery { $0.level = Int(level) } }
            )
            Picker("Charger", selection: binding(battery.charger) { $0.charger = $1 }) {
                ForEach(BatteryState.Charger.allCases) { Text($0.title).tag($0) }
            }
            Picker("Status", selection: binding(battery.status) { $0.status = $1 }) {
                ForEach(BatteryState.Status.allCases) { Text($0.title).tag($0) }
            }
            Picker("Health", selection: binding(battery.health) { $0.health = $1 }) {
                ForEach(BatteryState.Health.allCases) { Text($0.title).tag($0) }
            }
        }
    }

    private func binding<Value>(_ value: Value, update: @escaping (inout BatteryState, Value) -> Void) -> Binding<Value>
    {
        Binding {
            value
        } set: { newValue in
            model.updateBattery { update(&$0, newValue) }
        }
    }
}

struct FingerprintSection: View {
    @Bindable var model: DeviceSettingsModel

    var body: some View {
        Picker("Finger", selection: $model.fingerprintID) {
            ForEach(1...10, id: \.self) { Text("Finger \($0)").tag($0) }
        }
        HStack {
            Text("Enroll a fingerprint in Android Settings first, then touch with the same finger to unlock.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Touch Sensor", systemImage: "touchid", action: model.touchFingerprint)
                .disabled(model.busySections.contains(.fingerprint))
        }
    }
}

struct DisplaySection: View {
    let model: DeviceSettingsModel

    var body: some View {
        LiveContent(setting: model.brightness) { brightness in
            CommitSlider(
                title: "Brightness",
                value: Double(brightness),
                range: 0...255,
                format: { ($0 / 255).formatted(.percent.precision(.fractionLength(0))) },
                onCommit: { value in Task { await model.brightness.apply(Int(value)) } }
            )
        }
    }
}

struct MicrophoneSection: View {
    let model: DeviceSettingsModel

    var body: some View {
        LiveContent(setting: model.hostMicrophone) { enabled in
            Toggle(
                isOn: Binding {
                    enabled
                } set: { value in
                    Task { await model.hostMicrophone.apply(value) }
                }
            ) {
                Text("Use Mac microphone")
                Text("The device hears audio from this Mac's input. macOS asks for permission the first time.")
            }
        }
    }
}

struct ClipboardSection: View {
    let model: DeviceSettingsModel

    @State private var draft = ""

    var body: some View {
        LiveContent(setting: model.clipboard) { text in
            TextField("Clipboard", text: $draft, prompt: Text("Empty"), axis: .vertical)
                .lineLimit(3...6)
                .labelsHidden()
                .onChange(of: text, initial: true) { _, newValue in draft = newValue }
            HStack {
                Button("Refresh", systemImage: "arrow.clockwise") {
                    Task { await model.clipboard.load() }
                }
                Spacer()
                Button("Send to Device") { model.sendClipboard(draft) }
                    .disabled(draft == text)
            }
        }
    }
}
