import DesignSystem
import SDKDomain
import SwiftUI

/// Step 1: pick a hardware profile.
struct HardwareStepView: View {
    @Bindable var model: AddEmulatorModel

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.medium) {
            HStack(spacing: Spacing.medium) {
                // Seven form factors don't always fit as segments; fall back to a pop-up menu.
                ViewThatFits(in: .horizontal) {
                    formFactorPicker.pickerStyle(.segmented)
                    formFactorPicker.pickerStyle(.menu).fixedSize()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                TextField("Search devices", text: $model.hardwareSearch)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 180)
            }
            HStack(alignment: .top, spacing: Spacing.large) {
                Table(model.visibleProfiles, selection: $model.selectedProfileID) {
                    TableColumn("Name") { profile in
                        HStack {
                            Text(profile.name)
                            if profile.playStore {
                                Image(systemName: "play.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.green)
                                    .help("Supports Google Play")
                                    .accessibilityLabel("Google Play")
                            }
                        }
                    }
                    .width(min: 160)
                    TableColumn("Size") { Text($0.sizeText).monospacedDigit() }
                        .width(60)
                    TableColumn("Resolution") { Text($0.resolutionText).monospacedDigit() }
                        .width(100)
                    TableColumn("Density") { Text("\($0.density) dpi").monospacedDigit() }
                        .width(70)
                }
                .overlay {
                    if model.visibleProfiles.isEmpty {
                        ContentUnavailableView.search(text: model.hardwareSearch)
                    }
                }
                ProfilePreview(profile: model.selectedProfile)
                    .frame(width: 220)
            }
        }
        .padding(Spacing.large)
        .frame(minWidth: 0, maxWidth: .infinity)
    }

    private var formFactorPicker: some View {
        Picker("Form factor", selection: formFactor) {
            ForEach(model.availableFormFactors) { factor in
                Text(factor.title).tag(factor)
            }
        }
        .labelsHidden()
    }

    private var formFactor: Binding<FormFactor> {
        Binding {
            model.formFactor
        } set: {
            model.selectFormFactor($0)
        }
    }
}
