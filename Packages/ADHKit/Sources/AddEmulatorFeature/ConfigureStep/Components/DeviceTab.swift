import DesignSystem
import SDKDomain
import SwiftUI

struct DeviceTab: View {
    @Bindable var model: AddEmulatorModel

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $model.name)
                if let problem = model.nameProblem, !model.name.isEmpty {
                    Text(problem)
                        .font(.callout)
                        .foregroundStyle(.red)
                }
                if model.selectedProfile?.formFactor.usesMobileImages != false {
                    Picker("Services", selection: $model.services) {
                        ForEach(model.availableServices) { services in
                            Label {
                                Text(services.title)
                            } icon: {
                                ImageServicesGlyph(services: services)
                            }
                            .tag(services)
                        }
                    }
                }
                Picker("API level", selection: $model.selectedAPI) {
                    if model.apiChoices.isEmpty {
                        Text("None available").tag(AddEmulatorModel.APIChoice?.none)
                    }
                    ForEach(model.apiChoices) { choice in
                        apiLabel(choice).tag(Optional(choice))
                    }
                }
                .disabled(model.apiChoices.isEmpty)
                if let choice = model.selectedAPI, !model.availability(of: choice).services.isEmpty {
                    LabeledContent("Images") {
                        HStack(spacing: Spacing.xSmall) {
                            ForEach(model.availability(of: choice).services) { services in
                                ImageServicesBadge(
                                    services: services,
                                    isInstalled: model.availability(of: choice).installedServices.contains(services),
                                    isSelected: services == model.services,
                                    select: { model.services = services }
                                )
                            }
                        }
                    }
                }
            }

            Section {
                imageList
            } header: {
                HStack {
                    Text("System Image")
                    Spacer()
                    Toggle("16 KB page size", isOn: $model.showSixteenKBImages)
                    Toggle("Previews", isOn: $model.showPreviewImages)
                    Button("Refresh", systemImage: "arrow.clockwise") {
                        Task { await model.loadImages(forceRefresh: true) }
                    }
                    .labelStyle(.iconOnly)
                    .help("Refresh the list from Google")
                }
                .toggleStyle(.checkbox)
                .font(.callout)
            }
        }
        .formStyle(.grouped)
    }

    /// A menu item. Menus drop subtitles and tints, so the flavors are drawn into one icon.
    private func apiLabel(_ choice: AddEmulatorModel.APIChoice) -> some View {
        let availability = model.availability(of: choice)
        return Label {
            Text(choice.title)
        } icon: {
            if availability.services.isEmpty {
                Image(systemName: availability.isInstalled ? Symbol.success : Symbol.download)
            } else {
                APIAvailabilityIcon(
                    services: model.availableServices,
                    offered: Set(availability.services),
                    installed: availability.installedServices
                )
                .image
            }
        }
    }

    @ViewBuilder private var imageList: some View {
        switch model.imagesState {
        case .loading where model.images.isEmpty:
            HStack {
                ProgressView().controlSize(.small)
                Text("Loading system images…").foregroundStyle(.secondary)
            }
        case let .failed(message) where model.images.isEmpty:
            VStack(alignment: .leading, spacing: Spacing.small) {
                Text("Couldn't load the system image list.")
                Text(message).font(.callout).foregroundStyle(.secondary)
                Button("Try Again") { Task { await model.loadImages(forceRefresh: true) } }
            }
        default:
            if model.imagesForSelectedAPI.isEmpty {
                Text("No images match these settings.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.imagesForSelectedAPI) { entry in
                    ImageRow(
                        entry: entry,
                        isSelected: entry.path == model.selectedImagePath,
                        installs: model.installs,
                        select: { model.selectedImagePath = entry.path }
                    )
                }
            }
        }
    }
}
