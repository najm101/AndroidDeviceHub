import AppKit
import DesignSystem
import DeviceDomain
public import SwiftUI
import UniformTypeIdentifiers

/// Inspector ▸ Files: browse, upload by drag and drop, download, rename, delete.
public struct FilesInspectorView: View {
    @Bindable private var model: FilesModel

    @State private var isChoosingDownloadFolder = false
    @State private var downloadRequest: [RemoteFile] = []
    @State private var isNamingFolder = false
    @State private var newName = ""
    @State private var renaming: RemoteFile?
    @State private var pendingDelete: [RemoteFile] = []
    @State private var isDropTargeted = false

    public init(model: FilesModel) {
        self.model = model
    }

    public var body: some View {
        if let reason = model.availability.reason {
            UnavailableHint("Files", systemImage: Symbol.files, reason: reason)
        } else {
            browser
        }
    }

    private var browser: some View {
        VStack(spacing: 0) {
            toolbar
            if let error = model.errorMessage {
                ErrorBanner(error) { model.errorMessage = nil }
                    .padding(.horizontal, Spacing.medium)
                    .padding(.bottom, Spacing.small)
            }
            fileList
            TransfersPanel(model: model)
        }
        .task { await model.loadInitialFolder() }
        .fileImporter(isPresented: $isChoosingDownloadFolder, allowedContentTypes: [.folder]) { result in
            if case let .success(folder) = result {
                let didAccess = folder.startAccessingSecurityScopedResource()
                model.download(downloadRequest, into: folder)
                if didAccess { folder.stopAccessingSecurityScopedResource() }
            }
        }
        .fileDialogConfirmationLabel("Download Here")
        .alert("New Folder", isPresented: $isNamingFolder) {
            TextField("Name", text: $newName)
            Button("Create") { model.makeFolder(named: newName) }
                .disabled(model.nameError(newName) != nil)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(model.nameError(newName) ?? "In \(model.currentPath)")
        }
        .alert("Rename", isPresented: .isPresenting($renaming), presenting: renaming) { file in
            TextField("Name", text: $newName)
            Button("Rename") { model.rename(file, to: newName) }
                .disabled(model.nameError(newName, excluding: file) != nil || newName == file.name)
            Button("Cancel", role: .cancel) {}
        } message: { file in
            Text(model.nameError(newName, excluding: file) ?? "")
        }
        .confirmationDialog(
            deleteTitle,
            isPresented: Binding {
                !pendingDelete.isEmpty
            } set: {
                if !$0 { pendingDelete = [] }
            }
        ) {
            Button("Delete", role: .destructive) { model.delete(pendingDelete) }
        } message: {
            Text("This can't be undone.")
        }
    }

    // MARK: - Parts

    private var toolbar: some View {
        HStack(spacing: Spacing.small) {
            Button("Enclosing Folder", systemImage: Symbol.parentFolder, action: model.openParent)
                .disabled(model.currentPath == "/")
            Menu {
                ForEach(model.breadcrumbs.reversed(), id: \.self) { path in
                    Button(path) { model.open(path) }
                }
            } label: {
                Text(model.currentPath)
                    .lineLimit(1)
                    .truncationMode(.head)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .help(model.currentPath)
            Button("New Folder", systemImage: Symbol.newFolder) {
                newName = "New Folder"
                isNamingFolder = true
            }
            Button("Refresh", systemImage: Symbol.refresh) {
                Task { await model.reload() }
            }
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .controlSize(.small)
        .padding(.horizontal, Spacing.medium)
        .padding(.vertical, Spacing.small)
    }

    private var fileList: some View {
        List(selection: $model.selection) {
            ForEach(model.entries) { file in
                FileRow(file: file)
            }
        }
        .listStyle(.inset)
        .contextMenu(forSelectionType: RemoteFile.ID.self) { ids in
            menu(for: model.entries.filter { ids.contains($0.id) })
        } primaryAction: { ids in
            guard ids.count == 1, let file = model.entries.first(where: { ids.contains($0.id) }) else { return }
            if file.isFolderLike {
                model.activate(file)
            } else {
                requestDownload([file])
            }
        }
        .onDeleteCommand {
            pendingDelete = model.selectedFiles
        }
        .overlay { listOverlay }
        .dropDestination(for: URL.self) { urls, _ in
            model.upload(urls)
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

    @ViewBuilder private var listOverlay: some View {
        if model.isLoading {
            ProgressView()
        } else if let error = model.folderError {
            ContentUnavailableView("Can't Open Folder", systemImage: "lock", description: Text(error))
        } else if model.entries.isEmpty {
            ContentUnavailableView(
                "Empty Folder", systemImage: Symbol.files,
                description: Text("Drop files here to upload them."))
        }
    }

    @ViewBuilder
    private func menu(for files: [RemoteFile]) -> some View {
        if files.count == 1, let file = files.first, file.isFolderLike {
            Button("Open") { model.activate(file) }
        }
        if !files.isEmpty {
            Button("Download…") { requestDownload(files) }
        }
        if files.count == 1, let file = files.first {
            Button("Rename…") {
                newName = file.name
                renaming = file
            }
            Button("Copy Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(file.path, forType: .string)
            }
        }
        if !files.isEmpty {
            Divider()
            Button("Delete…", role: .destructive) { pendingDelete = files }
        } else {
            Button("New Folder…") {
                newName = "New Folder"
                isNamingFolder = true
            }
        }
    }

    private func requestDownload(_ files: [RemoteFile]) {
        downloadRequest = files
        isChoosingDownloadFolder = true
    }

    private var deleteTitle: String {
        pendingDelete.count == 1 ? "Delete “\(pendingDelete[0].name)”?" : "Delete \(pendingDelete.count) items?"
    }
}
