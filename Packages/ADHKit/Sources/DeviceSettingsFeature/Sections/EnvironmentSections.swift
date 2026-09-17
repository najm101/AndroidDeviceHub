import DeviceDomain
import SwiftUI

struct SensorsSection: View {
    let model: DeviceSettingsModel

    var body: some View {
        LiveContent(setting: model.sensors) { values in
            let sensors = AmbientSensor.allCases.filter { values[$0] != nil }
            if sensors.isEmpty {
                Text("This device has no adjustable sensors.")
                    .foregroundStyle(.secondary)
            }
            ForEach(sensors) { sensor in
                CommitSlider(
                    title: sensor.title,
                    value: values[sensor] ?? 0,
                    range: sensor.range,
                    step: sensor.step,
                    format: { "\($0.formatted(.number.precision(.fractionLength(0...1)))) \(sensor.unit)" },
                    onCommit: { model.setSensor(sensor, to: $0) }
                )
            }
        }
    }
}

private extension AmbientSensor {
    var step: Double {
        switch self {
        case .light: 10
        case .proximity: 0.5
        default: 1
        }
    }
}

struct PostureSection: View {
    let model: DeviceSettingsModel

    var body: some View {
        Picker(
            "Posture",
            selection: Binding {
                model.posture
            } set: {
                if let value = $0 { model.setPosture(value) }
            }
        ) {
            if model.posture == nil {
                Text("Choose…").tag(FoldPosture?.none)
            }
            ForEach(FoldPosture.allCases) { Text($0.title).tag(FoldPosture?.some($0)) }
        }
    }
}
