import Foundations
import SDKDomain
import SwiftUI

struct AdditionalSettingsTab: View {
    @Bindable var model: AddEmulatorModel

    var body: some View {
        Form {
            Section("Startup") {
                Picker("Orientation", selection: $model.orientation) {
                    ForEach(Orientation.allCases) { Text($0.title).tag($0) }
                }
                Picker("Boot", selection: $model.bootMode) {
                    ForEach(BootMode.allCases) { Text($0.title).tag($0) }
                }
            }
            Section("Performance") {
                Picker("CPU cores", selection: $model.cpuCores) {
                    ForEach(1...max(1, model.dependencies.hostCPUCount), id: \.self) { Text("\($0)").tag($0) }
                }
                Picker("Graphics", selection: $model.graphics) {
                    ForEach(GraphicsMode.allCases) { Text($0.title).tag($0) }
                }
                Stepper(value: $model.ramMiB, in: 1024...16384, step: 512) {
                    LabeledContent("RAM", value: Int64(model.ramMiB * 1024 * 1024).formattedFileSize)
                }
                Stepper(value: $model.vmHeapMiB, in: 64...1024, step: 64) {
                    LabeledContent("VM heap", value: "\(model.vmHeapMiB) MB")
                }
            }
            Section("Storage") {
                Stepper(value: $model.internalStorageGiB, in: 2...128) {
                    LabeledContent("Internal storage", value: "\(model.internalStorageGiB) GB")
                }
                Toggle("SD card", isOn: $model.hasSDCard)
                if model.hasSDCard {
                    Stepper(value: $model.sdCardMiB, in: 64...8192, step: 128) {
                        LabeledContent("SD card size", value: "\(model.sdCardMiB) MB")
                    }
                }
            }
            Section("Devices") {
                if model.selectedProfile?.hasFrontCamera != false {
                    Picker("Front camera", selection: $model.frontCamera) {
                        ForEach(CameraMode.allCases.filter { $0 != .virtualScene }) { Text($0.title).tag($0) }
                    }
                }
                if model.selectedProfile?.hasBackCamera != false {
                    Picker("Back camera", selection: $model.backCamera) {
                        ForEach(CameraMode.allCases) { Text($0.title).tag($0) }
                    }
                }
                Toggle("Use Mac keyboard", isOn: $model.useHostKeyboard)
            }
            Section("Network") {
                Picker("Speed", selection: $model.networkSpeed) {
                    ForEach(NetworkSpeed.allCases) { Text($0.title).tag($0) }
                }
                Picker("Latency", selection: $model.networkLatency) {
                    ForEach(NetworkLatency.allCases) { Text($0.title).tag($0) }
                }
            }
        }
        .formStyle(.grouped)
    }
}
