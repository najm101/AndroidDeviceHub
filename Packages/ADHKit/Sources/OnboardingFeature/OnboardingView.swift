import DesignSystem
import Foundations
import PackageInstallUI
import SDKDomain
public import SwiftUI

/// The first-run setup wizard.
public struct OnboardingView: View {
    @Bindable private var model: OnboardingModel

    public init(model: OnboardingModel) {
        self.model = model
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
                .padding(Spacing.xLarge)
            Divider()
            ScrollView {
                Group {
                    switch model.step {
                    case .sdk: SDKStepView(model: model)
                    case .platformTools: PlatformToolsStepView(model: model)
                    case .ready: ReadyStepView(model: model)
                    }
                }
                .padding(Spacing.xLarge)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            footer
                .padding(Spacing.large)
        }
        .frame(width: Layout.onboardingWidth, height: 520)
        .background(.background, in: RoundedRectangle(cornerRadius: CornerRadius.large))
        .overlay(RoundedRectangle(cornerRadius: CornerRadius.large).strokeBorder(.separator))
        .shadow(color: .black.opacity(0.12), radius: 24, y: 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background.secondary)
        .task { await model.start() }
        .onChange(of: model.installs.inventoryRevision) {
            Task { await model.inventoryChanged() }
        }
        .alert("Something went wrong", isPresented: isShowingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private var header: some View {
        HStack(spacing: Spacing.large) {
            Image(systemName: "iphone.gen3.radiowaves.left.and.right")
                .font(.system(size: 36))
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: Spacing.xSmall) {
                Text("Welcome to Android Device Hub")
                    .font(.title2.bold())
                Text("Step \(model.step.rawValue + 1) of \(OnboardingModel.Step.allCases.count) — \(model.step.title)")
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    @ViewBuilder private var footer: some View {
        HStack {
            if model.step != .sdk {
                Button("Back", action: model.goBack)
            }
            Spacer()
            switch model.step {
            case .sdk:
                Button("Quit") { NSApplication.shared.terminate(nil) }
                Button("Continue") { Task { await model.goForward() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.canContinue)
            case .platformTools:
                Button("Skip") { Task { await model.skipPlatformTools() } }
                Button("Continue") { Task { await model.goForward() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.report?.hasPlatformTools != true)
            case .ready:
                Button("Create a Device…") { model.finish(openNewEmulator: true) }
                Button("Open Android Device Hub") { model.finish(openNewEmulator: false) }
                    .keyboardShortcut(.defaultAction)
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

// MARK: - Steps

struct SDKStepView: View {
    let model: OnboardingModel
    @State private var isChoosingFolder = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.medium) {
            Text(
                "Android Device Hub uses the Android SDK folder shared with Android Studio and Flutter. It doesn't need Java or Android Studio."
            )
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            if model.isChecking && model.report == nil {
                ProgressView("Checking…")
            }
            ForEach(model.sdkChecks) { check in
                StatusRow(check.title, detail: detail(for: check), state: CheckPresentation.state(check)) {
                    accessory(for: check)
                }
                Divider()
            }
            if let error = model.catalogError {
                Text("Google's download list couldn't be loaded: \(error)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .fileImporter(isPresented: $isChoosingFolder, allowedContentTypes: [.folder]) { result in
            if case let .success(url) = result {
                Task { await model.chooseSDKFolder(url) }
            }
        }
    }

    private func detail(for check: SetupCheck) -> String {
        guard check.id == .sdkFolder, let location = model.report?.location, check.status.isSatisfied else {
            return check.status.detail
        }
        return "\(check.status.detail)\n\(location.sdkSource.title)"
    }

    @ViewBuilder
    private func accessory(for check: SetupCheck) -> some View {
        switch check.id {
        case .sdkFolder:
            HStack {
                if model.sdkIsMissing {
                    Button("Create Folder") { Task { await model.createSuggestedSDKFolder() } }
                }
                Button("Change…") { isChoosingFolder = true }
            }
        case .emulator:
            if !check.status.isSatisfied || updateAvailable(for: check) {
                if let package = model.package(for: check) {
                    PackageInstallButton(
                        check.status.isSatisfied ? "Update" : "Install", package: package, coordinator: model.installs
                    )
                    .disabled(model.sdkIsMissing)
                } else if model.catalogError == nil {
                    ProgressView().controlSize(.small)
                }
            }
        default:
            EmptyView()
        }
    }

    private func updateAvailable(for check: SetupCheck) -> Bool {
        guard let installed = check.installedRevision, let latest = model.package(for: check) else { return false }
        return latest.revision > installed
    }
}

struct PlatformToolsStepView: View {
    let model: OnboardingModel

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.large) {
            Text("ADB (Android Platform Tools) is needed to:")
            VStack(alignment: .leading, spacing: Spacing.small) {
                Label("Connect physical Android devices over USB or Wi-Fi", systemImage: Symbol.physicalDevice)
                Label("Manage apps, files, users and crash reports on any device", systemImage: "square.stack.3d.up")
            }
            .padding(.leading, Spacing.small)
            if let check = model.check(.platformTools) {
                StatusRow(check.title, detail: check.status.detail, state: CheckPresentation.state(check)) {
                    if !check.status.isSatisfied, let package = model.package(for: check) {
                        PackageInstallButton(
                            "Install · \(package.archive.size.formattedFileSize)", package: package,
                            coordinator: model.installs)
                    }
                }
            }
            Text("You can install it later in Settings → Components.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}

struct ReadyStepView: View {
    let model: OnboardingModel

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.large) {
            if model.deviceCount == 0 {
                Text("You don't have any virtual devices yet. Create one to get started.")
            } else {
                Text("Found \(model.deviceCount) existing \(model.deviceCount == 1 ? "device" : "devices").")
            }
            if !model.missingImages.isEmpty {
                Text("Some devices need a system image before they can start:")
                    .foregroundStyle(.secondary)
                ForEach(model.missingImages) { missing in
                    StatusRow(
                        missing.deviceNames.joined(separator: ", "),
                        detail: missing.package?.displayName ?? missing.sysdir,
                        state: .warning
                    ) {
                        if let package = missing.package {
                            PackageInstallButton(
                                "Install · \(package.archive.size.formattedFileSize)",
                                package: package,
                                coordinator: model.installs
                            )
                        }
                    }
                    Divider()
                }
            }
        }
    }
}

enum CheckPresentation {
    static func state(_ check: SetupCheck) -> StatusState {
        switch (check.status, check.level) {
        case (.satisfied, _): .success
        case (.warning, _): .warning
        case (_, .optional): .optional
        case (_, .warning): .warning
        default: .failure
        }
    }
}
