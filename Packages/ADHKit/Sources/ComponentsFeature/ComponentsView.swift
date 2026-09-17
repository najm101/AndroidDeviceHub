import DesignSystem
import Foundations
import PackageInstallUI
import SDKDomain
public import SwiftUI

/// Settings → Components.
public struct ComponentsView: View {
    @Bindable private var model: ComponentsModel
    @State private var isChoosingFolder = false

    public init(model: ComponentsModel) {
        self.model = model
    }

    public var body: some View {
        Form {
            locationSection
            toolsSection
            imagesSection
            checksSection
        }
        .formStyle(.grouped)
        .task { await model.load() }
        .onChange(of: model.installs.inventoryRevision) {
            Task { await model.inventoryChanged() }
        }
        .fileImporter(isPresented: $isChoosingFolder, allowedContentTypes: [.folder]) { result in
            if case let .success(url) = result {
                Task { await model.chooseSDKFolder(url) }
            }
        }
        .confirmationDialog(
            "Remove \(model.pendingRemoval?.displayName ?? "")?",
            isPresented: isConfirmingRemoval,
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) { Task { await model.confirmRemoval() } }
        } message: {
            Text(removalMessage)
        }
        .alert("Something went wrong", isPresented: isShowingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    // MARK: - Sections

    @ViewBuilder private var locationSection: some View {
        Section("Android SDK") {
            if let location = model.report?.location {
                LabeledContent("SDK folder") {
                    VStack(alignment: .trailing, spacing: Spacing.xxSmall) {
                        Text(location.sdkRoot.path(percentEncoded: false))
                            .textSelection(.enabled)
                        Text(location.sdkSource.title)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                LabeledContent("Devices folder") {
                    VStack(alignment: .trailing, spacing: Spacing.xxSmall) {
                        Text(location.avdHome.path(percentEncoded: false))
                            .textSelection(.enabled)
                        Text(location.avdSource.title)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                HStack {
                    Spacer()
                    if location.sdkSource == .userSelection {
                        Button("Use Default") { Task { await model.resetSDKFolder() } }
                    }
                    Button("Show in Finder") { model.reveal(location.sdkRoot) }
                    Button("Change…") { isChoosingFolder = true }
                }
            } else {
                ProgressView()
            }
        }
    }

    private var toolsSection: some View {
        Section {
            ForEach(model.tools) { tool in
                LabeledContent {
                    toolAccessory(tool)
                } label: {
                    Text(tool.title)
                    Text(toolDetail(tool))
                }
            }
        } header: {
            Text("Tools")
        } footer: {
            if let error = model.catalogError {
                Text("Google's download list couldn't be loaded: \(error)")
            }
        }
    }

    @ViewBuilder
    private func toolAccessory(_ tool: ComponentsModel.ToolRow) -> some View {
        if let latest = tool.latest, tool.installed == nil || tool.updateAvailable {
            PackageInstallButton(
                tool.installed == nil ? "Install" : "Update", package: latest, coordinator: model.installs)
        } else if let installed = tool.installed, tool.path == SDKPackagePath.platformTools {
            Button("Remove", role: .destructive) { model.pendingRemoval = installed }
        }
    }

    private func toolDetail(_ tool: ComponentsModel.ToolRow) -> String {
        switch (tool.installed, tool.latest) {
        case let (installed?, latest?) where tool.updateAvailable:
            "Version \(installed.revision) · \(latest.revision) available"
        case let (installed?, _):
            "Version \(installed.revision)"
        case let (nil, latest?):
            "Not installed · \(latest.archive.size.formattedFileSize)"
        case (nil, nil):
            "Not installed"
        }
    }

    private var imagesSection: some View {
        Section {
            if model.images.isEmpty {
                Text("No system images installed. Download one when creating a device.")
                    .foregroundStyle(.secondary)
            }
            ForEach(model.images) { image in
                LabeledContent {
                    HStack {
                        Text(image.size.map(\.formattedFileSize) ?? "…")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                        Button("Remove", systemImage: Symbol.remove) { model.pendingRemoval = image.package }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.borderless)
                            .help("Remove this system image")
                    }
                } label: {
                    Text(imageTitle(image))
                    Text(
                        image.usedBy.isEmpty
                            ? "Not used by any device" : "Used by \(image.usedBy.joined(separator: ", "))")
                }
            }
        } header: {
            Text("System Images")
        } footer: {
            if model.totalImageSize > 0 {
                Text("\(model.totalImageSize.formattedFileSize) in total")
            }
        }
    }

    private func imageTitle(_ image: ComponentsModel.ImageRow) -> String {
        guard let details = image.package.systemImage else { return image.package.displayName }
        return
            "\(details.apiLevel.androidVersionTitle) (API \(details.apiLevel)) · \(details.primaryTag.display) · \(details.abi)"
    }

    private var checksSection: some View {
        Section {
            ForEach(model.report?.checks ?? []) { check in
                StatusRow(check.title, detail: check.status.detail, state: state(for: check))
            }
            HStack {
                Spacer()
                Button("Run Checks Again") { Task { await model.load() } }
                    .disabled(model.isLoading)
            }
        } header: {
            Text("Setup Checks")
        }
    }

    // MARK: - Helpers

    private func state(for check: SetupCheck) -> StatusState {
        switch (check.status, check.level) {
        case (.satisfied, _): .success
        case (.warning, _): .warning
        case (_, .optional): .optional
        default: .failure
        }
    }

    private var removalMessage: String {
        guard let package = model.pendingRemoval else { return "" }
        let users = model.images.first { $0.package.path == package.path }?.usedBy ?? []
        if users.isEmpty {
            return "It can be downloaded again later."
        }
        return "\(users.joined(separator: ", ")) won't start until it's installed again."
    }

    private var isConfirmingRemoval: Binding<Bool> {
        Binding {
            model.pendingRemoval != nil
        } set: {
            if !$0 { model.pendingRemoval = nil }
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
