import DesignSystem
import SDKDomain
public import SwiftUI

/// The New Emulator sheet: Select Hardware → Configure.
public struct AddEmulatorView: View {
    @Bindable private var model: AddEmulatorModel
    @Environment(\.dismiss) private var dismiss

    public init(model: AddEmulatorModel) {
        self.model = model
    }

    public var body: some View {
        VStack(spacing: 0) {
            StepHeader(current: model.step)
                .padding(.horizontal, Spacing.xLarge)
                .padding(.vertical, Spacing.medium)
            Divider()
            Group {
                switch model.step {
                case .hardware:
                    HardwareStepView(model: model)
                case .configure:
                    ConfigureStepView(model: model)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            footer
                .padding(Spacing.large)
        }
        .frame(width: Layout.sheetWidth, height: 600)
        .task(id: model.installs.inventoryRevision) {
            if model.installs.inventoryRevision > 0 {
                await model.inventoryChanged()
            }
        }
        .alert("Couldn't Create Device", isPresented: isShowingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private var footer: some View {
        HStack(spacing: Spacing.medium) {
            if model.step == .configure, let hint = model.finishHint {
                Text(hint)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            if model.step == .configure {
                Toggle("Start after creating", isOn: $model.startAfterCreating)
                    .disabled(model.imageStatus != .installed)
                Button("Back", action: model.goBack)
            }
            Button("Cancel", role: .cancel) { dismiss() }
                .keyboardShortcut(.cancelAction)
            switch model.step {
            case .hardware:
                Button("Next", action: model.goForward)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.canContinue)
            case .configure:
                Button {
                    Task { await model.finish() }
                } label: {
                    if model.isCreating {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Finish")
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!model.canFinish)
            }
        }
    }

    private var isShowingError: Binding<Bool> {
        Binding {
            model.errorMessage != nil
        } set: {
            if !$0 { model.errorMessage = nil }
        }
    }
}
