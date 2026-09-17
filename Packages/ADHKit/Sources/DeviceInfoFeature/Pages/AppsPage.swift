import AppKit
import DesignSystem
import DeviceDomain
import SwiftUI
import UniformTypeIdentifiers

struct AppsPage: View {
    @Bindable var model: DeviceInfoModel

    @State private var isImporting = false
    @State private var isDropTargeted = false
    @State private var pendingUninstall: InstalledApp?
    @State private var pendingClear: InstalledApp?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Spacing.small) {
                Picker("Show", selection: $model.appFilter) {
                    ForEach(DeviceInfoModel.AppFilter.allCases) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
                TextField("Search", text: $model.appSearch)
                    .textFieldStyle(.roundedBorder)
                Button("Install…", systemImage: Symbol.add) { isImporting = true }
                    .labelStyle(.iconOnly)
                    .help("Install an APK")
                RefreshButton { await model.loadApps() }
            }
            .controlSize(.small)
            .padding(.horizontal, Spacing.medium)
            .padding(.bottom, Spacing.small)

            ForEach(model.installs, id: \.fileName) { install in
                TransferRow(
                    "Installing \(install.fileName)",
                    fraction: install.progress.map { $0.fraction < 1 ? $0.fraction : nil } ?? nil
                )
                .padding(.horizontal, Spacing.medium)
                .padding(.bottom, Spacing.small)
            }

            List {
                ForEach(model.visibleApps) { app in
                    AppRow(
                        app: app, label: model.labels[app.packageName], isBusy: model.busyApps.contains(app.packageName)
                    )
                    .contextMenu { actions(for: app) }
                    .task { await model.loadLabel(for: app) }
                }
            }
            .listStyle(.inset)
            .overlay { overlay }
            .dropDestination(for: URL.self) { urls, _ in
                model.install(urls)
                return true
            } isTargeted: {
                isDropTargeted = $0
            }
            .overlay {
                if isDropTargeted {
                    RoundedRectangle(cornerRadius: CornerRadius.medium)
                        .strokeBorder(.tint, lineWidth: 2)
                        .padding(Spacing.xSmall)
                }
            }
        }
        .task { await model.loadApps() }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.apk, .apks, .folder],
            allowsMultipleSelection: true
        ) { result in
            if case let .success(urls) = result {
                model.install(urls)
            }
        }
        .confirmationDialog(
            "Uninstall “\(pendingUninstall?.packageName ?? "")”?",
            isPresented: .isPresenting($pendingUninstall),
            presenting: pendingUninstall
        ) { app in
            Button("Uninstall", role: .destructive) { model.uninstall(app) }
        } message: { _ in
            Text("The app and its data are removed from the device.")
        }
        .confirmationDialog(
            "Clear the data of “\(pendingClear?.packageName ?? "")”?",
            isPresented: .isPresenting($pendingClear),
            presenting: pendingClear
        ) { app in
            Button("Clear Data", role: .destructive) { model.clearData(app) }
        } message: { _ in
            Text("Files, settings and accounts of the app are deleted.")
        }
    }

    @ViewBuilder private var overlay: some View {
        if model.isLoadingApps {
            ProgressView()
        } else if model.visibleApps.isEmpty {
            if model.appSearch.isEmpty, model.appFilter == .user {
                ContentUnavailableView(
                    "No Apps Installed", systemImage: Symbol.apps,
                    description: Text("Drop an APK here to install it."))
            } else {
                ContentUnavailableView.search
            }
        }
    }

    @ViewBuilder
    private func actions(for app: InstalledApp) -> some View {
        Button("Open") { model.launch(app) }
        Button("Force Stop") { model.forceStop(app) }
        Divider()
        Button("Copy Package Name") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(app.packageName, forType: .string)
        }
        Divider()
        Button("Clear Data…") { pendingClear = app }
        if !app.isSystem {
            Button("Uninstall…", role: .destructive) { pendingUninstall = app }
        }
    }
}

private struct AppRow: View {
    let app: InstalledApp
    let label: String?
    let isBusy: Bool

    var body: some View {
        HStack(spacing: Spacing.small) {
            Image(systemName: Symbol.app)
                .foregroundStyle(app.isSystem ? Color.secondary : Color.accentColor)
            VStack(alignment: .leading, spacing: 0) {
                Text(label ?? app.packageName)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if label != nil {
                    Text(app.packageName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: Spacing.small)
            if isBusy {
                ProgressView().controlSize(.mini)
            } else if let version = app.versionCode {
                Text(verbatim: "v\(version)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .help("Version code \(version)")
            }
        }
        .accessibilityElement(children: .combine)
        .help(app.packageName)
    }
}

extension UTType {
    static let apk = UTType(filenameExtension: "apk", conformingTo: .data) ?? .data
    static let apks = UTType(filenameExtension: "apks", conformingTo: .archive) ?? .archive
}
