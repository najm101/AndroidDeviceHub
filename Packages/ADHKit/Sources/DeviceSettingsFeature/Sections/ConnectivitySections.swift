import DesignSystem
import DeviceDomain
import SDKDomain
import SwiftUI

struct NetworkSection: View {
    let model: DeviceSettingsModel

    var body: some View {
        LiveContent(setting: model.network) { network in
            Picker("Speed", selection: binding(network.speed) { $0.speed = $1 }) {
                ForEach(NetworkSpeed.allCases) { Text($0.title).tag($0) }
            }
            Picker("Latency", selection: binding(network.latency) { $0.latency = $1 }) {
                ForEach(NetworkLatency.allCases) { Text($0.title).tag($0) }
            }
            Picker("Signal strength", selection: binding(network.signal) { $0.signal = $1 }) {
                ForEach(SignalStrength.allCases) { Text($0.title).tag($0) }
            }
            Picker("Voice", selection: binding(network.voice) { $0.voice = $1 }) {
                ForEach(CellularRegistration.allCases) { Text($0.title).tag($0) }
            }
            Picker("Data", selection: binding(network.data) { $0.data = $1 }) {
                ForEach(CellularRegistration.allCases) { Text($0.title).tag($0) }
            }
        }
    }

    private func binding<Value>(
        _ value: Value,
        update: @escaping (inout NetworkConditions, Value) -> Void
    ) -> Binding<Value> {
        Binding {
            value
        } set: { newValue in
            model.updateNetwork { update(&$0, newValue) }
        }
    }
}

struct TelephonySection: View {
    @Bindable var model: DeviceSettingsModel

    var body: some View {
        TextField("From", text: $model.phoneNumber, prompt: Text("Phone number"))
        LabeledContent("Call") {
            HStack(spacing: Spacing.xSmall) {
                Button("Call", systemImage: "phone.arrow.down.left") { model.phoneCall(.call) }
                    .help("Simulate an incoming call")
                Button("Hang Up", systemImage: "phone.down") { model.phoneCall(.hangUp) }
                    .help("End the call")
                Menu("More", systemImage: "ellipsis") {
                    Button("Answer") { model.phoneCall(.accept) }
                    Button("Reject") { model.phoneCall(.reject) }
                    Divider()
                    Button("Hold") { model.phoneCall(.hold) }
                    Button("Resume") { model.phoneCall(.resume) }
                }
                .menuIndicator(.hidden)
            }
            .labelStyle(.iconOnly)
            .disabled(model.phoneNumber.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        TextField("Message", text: $model.smsText, prompt: Text("SMS text"), axis: .vertical)
            .lineLimit(1...4)
        HStack {
            Spacer()
            Button("Send SMS", action: model.sendSMS)
                .disabled(!model.canSendSMS)
        }
    }
}
