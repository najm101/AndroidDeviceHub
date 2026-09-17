import DesignSystem
import DeviceDomain
import SwiftUI

/// Overrides the screen size and density, like `adb shell wm size` and `wm density`.
struct ScreenSizeSection: View {
    let model: DeviceSettingsModel

    var body: some View {
        if let reason = model.device?.availability(of: .displaySize).reason {
            Text(reason)
                .foregroundStyle(.secondary)
        } else {
            LiveContent(setting: model.display) { metrics in
                ScreenSizeEditor(model: model, metrics: metrics)
            }
        }
    }
}

private struct ScreenSizeEditor: View {
    let model: DeviceSettingsModel
    let metrics: DisplayMetrics

    @State private var width = 0
    @State private var height = 0
    @State private var density = 0
    @State private var keepsPhysicalSize = true
    @State private var isNamingPreset = false
    @State private var presetName = ""

    private var draft: DisplayConfiguration {
        DisplayConfiguration(size: PixelSize(width: width, height: height), density: density)
    }

    private var isBusy: Bool { model.busySections.contains(.screenSize) }

    var body: some View {
        LabeledContent("Current") {
            VStack(alignment: .trailing, spacing: Spacing.xxSmall) {
                Text(Self.describe(metrics.current))
                Text(metrics.isOverridden ? "Physical: \(Self.describe(metrics.physical))" : "Physical screen")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .monospacedDigit()
        }

        presetsMenu

        LabeledContent("Resolution") {
            HStack(spacing: Spacing.xSmall) {
                pixelField("Width", value: $width)
                Text("×").foregroundStyle(.secondary)
                pixelField("Height", value: $height)
            }
        }
        LabeledContent("Density") {
            HStack(spacing: Spacing.xSmall) {
                pixelField("Density", value: $density)
                    .disabled(keepsPhysicalSize)
                Text("dpi").foregroundStyle(.secondary)
            }
        }
        Toggle(isOn: $keepsPhysicalSize) {
            Text("Keep physical size")
            Text("Changes the density with the resolution, so things keep their real-world size.")
        }

        HStack {
            Text(draft.validationError ?? "Apps see \(Self.describe(draft.sizeDP)) dp")
                .font(.caption)
                .foregroundStyle(draft.validationError == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.red))
            Spacer()
            Button("Reset") { model.applyDisplay(nil) }
                .disabled(!metrics.isOverridden || isBusy)
            Button("Apply") { model.applyDisplay(draft) }
                .disabled(draft == metrics.current || draft.validationError != nil || isBusy)
        }
        .onChange(of: metrics, initial: true) { _, newValue in load(newValue.current) }
        .onChange(of: width) { updateDensityIfLocked() }
        .onChange(of: height) { updateDensityIfLocked() }
        .onChange(of: keepsPhysicalSize) { updateDensityIfLocked() }
        .alert("Save Preset", isPresented: $isNamingPreset) {
            TextField("Name", text: $presetName)
            Button("Save") { model.savePreset(named: presetName, from: draft) }
                .disabled(presetName.trimmingCharacters(in: .whitespaces).isEmpty)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Saves \(Self.describe(draft.sizeDP)) dp. Presets fit any screen, keeping this shape.")
        }
    }

    private var presetsMenu: some View {
        LabeledContent("Presets") {
            Menu("Choose") {
                Section("Android Sizes") {
                    ForEach(ScreenPreset.builtIn) { preset in
                        presetButton(preset)
                    }
                }
                if !model.customScreenPresets.isEmpty {
                    Section("Saved") {
                        ForEach(model.customScreenPresets) { preset in
                            presetButton(preset)
                        }
                    }
                }
                Divider()
                Button("Save Current Values as Preset…") {
                    presetName = ""
                    isNamingPreset = true
                }
                .disabled(draft.validationError != nil)
                if !model.customScreenPresets.isEmpty {
                    Menu("Delete Preset") {
                        ForEach(model.customScreenPresets) { preset in
                            Button(preset.name) { model.deletePreset(preset) }
                        }
                    }
                }
            }
            .fixedSize()
            .disabled(isBusy)
        }
    }

    private func presetButton(_ preset: ScreenPreset) -> some View {
        Button {
            model.applyPreset(preset)
        } label: {
            Text(preset.name)
            Text(verbatim: "\(preset.shortSideDP) × \(preset.longSideDP) dp")
        }
    }

    private func pixelField(_ title: String, value: Binding<Int>) -> some View {
        TextField(title, value: value, format: .number.grouping(.never))
            .textFieldStyle(.roundedBorder)
            .labelsHidden()
            .accessibilityLabel(title)
            .multilineTextAlignment(.trailing)
            .monospacedDigit()
            .frame(width: 56)
            .onSubmit {
                if draft != metrics.current, draft.validationError == nil { model.applyDisplay(draft) }
            }
    }

    private func load(_ configuration: DisplayConfiguration) {
        width = configuration.size.width
        height = configuration.size.height
        density = configuration.density
        keepsPhysicalSize = configuration.density == metrics.densityKeepingPhysicalSize(for: configuration.size)
    }

    private func updateDensityIfLocked() {
        guard keepsPhysicalSize, width > 0, height > 0 else { return }
        density = metrics.densityKeepingPhysicalSize(for: PixelSize(width: width, height: height))
    }

    private static func describe(_ configuration: DisplayConfiguration) -> String {
        "\(describe(configuration.size)) · \(configuration.density) dpi"
    }

    private static func describe(_ size: PixelSize) -> String {
        "\(size.width) × \(size.height)"
    }
}
