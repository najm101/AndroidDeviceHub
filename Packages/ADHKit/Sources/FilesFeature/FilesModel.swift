public import DeviceDomain
public import Foundation
public import Observation

/// Dependencies of Inspector ▸ Files, wired by the app.
@MainActor
public struct FilesDependencies {
    public var repository: any DeviceRepository
    public var reveal: @MainActor (URL) -> Void

    public init(repository: any DeviceRepository, reveal: @escaping @MainActor (URL) -> Void) {
        self.repository = repository
        self.reveal = reveal
    }
}

/// Inspector ▸ Files for one device.
@MainActor
@Observable
public final class FilesModel {
    struct Transfer: Identifiable, Equatable {
        enum Direction { case upload, download }

        let id = UUID()
        var name: String
        var direction: Direction
        var progress: TransferProgress?
    }

    private(set) var path: String?
    private(set) var entries: [RemoteFile] = []
    private(set) var isLoading = false
    /// A problem with the current folder, shown in place of the list.
    private(set) var folderError: String?
    var errorMessage: String?
    var selection: Set<RemoteFile.ID> = []
    private(set) var transfers: [Transfer] = []
    private(set) var lastDownload: URL?

    let deviceID: DeviceID
    private let dependencies: FilesDependencies
    @ObservationIgnored private var tasks: [UUID: Task<Void, Never>] = [:]

    public init(deviceID: DeviceID, dependencies: FilesDependencies) {
        self.deviceID = deviceID
        self.dependencies = dependencies
    }

    var availability: Availability {
        dependencies.repository.device(withID: deviceID)?.availability(of: .files) ?? .hidden
    }

    var currentPath: String { path ?? "/" }
    var breadcrumbs: [String] { RemotePath.ancestors(of: currentPath) }
    var selectedFiles: [RemoteFile] { entries.filter { selection.contains($0.id) } }

    // MARK: - Browsing

    func loadInitialFolder() async {
        if path == nil {
            path = dependencies.repository.inspector(for: deviceID)?.homeDirectory ?? "/"
        }
        await reload()
    }

    func open(_ directory: String) {
        guard directory != path else { return }
        path = directory
        selection = []
        entries = []
        Task { await reload() }
    }

    func openParent() {
        open(RemotePath.parent(of: currentPath))
    }

    /// Folders open in place; files are downloaded.
    func activate(_ file: RemoteFile) {
        if file.isFolderLike {
            open(file.path)
        }
    }

    func reload() async {
        guard let inspector = inspector() else { return }
        let directory = currentPath
        isLoading = entries.isEmpty
        defer { isLoading = false }
        do {
            let files = try await inspector.files(in: directory)
            guard directory == currentPath else { return }
            entries = files
            folderError = nil
            selection = selection.intersection(files.map(\.id))
        } catch {
            guard directory == currentPath else { return }
            entries = []
            folderError = error.localizedDescription
        }
    }

    // MARK: - Changes

    func nameError(_ name: String, excluding file: RemoteFile? = nil) -> String? {
        if let error = RemotePath.validationError(forName: name) { return error }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if entries.contains(where: { $0.name == trimmed && $0 != file }) {
            return "An item with this name already exists."
        }
        return nil
    }

    func makeFolder(named name: String) {
        let path = RemotePath.join(currentPath, name.trimmingCharacters(in: .whitespaces))
        change { try await $0.makeDirectory(at: path) }
    }

    func rename(_ file: RemoteFile, to name: String) {
        let target = RemotePath.join(RemotePath.parent(of: file.path), name.trimmingCharacters(in: .whitespaces))
        change { try await $0.move(file.path, to: target) }
    }

    func delete(_ files: [RemoteFile]) {
        change {
            for file in files {
                try await $0.delete(file.path)
            }
        }
    }

    private func change(_ operation: @escaping @MainActor (any DeviceInspecting) async throws -> Void) {
        guard let inspector = inspector() else { return }
        Task {
            do {
                try await operation(inspector)
            } catch {
                show(error)
            }
            await reload()
        }
    }

    // MARK: - Transfers

    func upload(_ urls: [URL]) {
        guard let inspector = inspector() else { return }
        let directory = currentPath
        for url in urls {
            startTransfer(name: url.lastPathComponent, direction: .upload) { progress in
                try await inspector.upload(url, into: directory, progress: progress)
            } completion: { [weak self] in
                if self?.currentPath == directory { await self?.reload() }
            }
        }
    }

    func download(_ files: [RemoteFile], into folder: URL) {
        guard let inspector = inspector() else { return }
        for file in files {
            startTransfer(name: file.name, direction: .download) { [weak self] progress in
                let url = try await inspector.download(file, into: folder, progress: progress)
                self?.lastDownload = url
            } completion: {
            }
        }
    }

    func revealLastDownload() {
        if let lastDownload { dependencies.reveal(lastDownload) }
    }

    func dismissLastDownload() {
        lastDownload = nil
    }

    func cancel(_ transfer: Transfer) {
        tasks[transfer.id]?.cancel()
    }

    private func startTransfer(
        name: String,
        direction: Transfer.Direction,
        _ operation: @escaping @MainActor (@escaping TransferProgressHandler) async throws -> Void,
        completion: @escaping @MainActor () async -> Void
    ) {
        let transfer = Transfer(name: name, direction: direction)
        transfers.append(transfer)
        let id = transfer.id
        tasks[id] = Task {
            let updates = AsyncStream<TransferProgress>.makeStream(bufferingPolicy: .bufferingNewest(1))
            let watcher = Task {
                for await progress in updates.stream {
                    if let index = transfers.firstIndex(where: { $0.id == id }) {
                        transfers[index].progress = progress
                    }
                }
            }
            do {
                try await operation { updates.continuation.yield($0) }
            } catch {
                show(error, prefix: direction == .upload ? "Couldn't upload \(name)" : "Couldn't download \(name)")
            }
            updates.continuation.finish()
            watcher.cancel()
            transfers.removeAll { $0.id == id }
            tasks[id] = nil
            await completion()
        }
    }

    // MARK: - Helpers

    private func show(_ error: any Error, prefix: String? = nil) {
        guard !(error is CancellationError) else { return }
        errorMessage = prefix.map { "\($0): \(error.localizedDescription)" } ?? error.localizedDescription
    }

    private func inspector() -> (any DeviceInspecting)? {
        guard let inspector = dependencies.repository.inspector(for: deviceID) else {
            folderError = availability.reason ?? "The device isn't connected."
            return nil
        }
        return inspector
    }
}
