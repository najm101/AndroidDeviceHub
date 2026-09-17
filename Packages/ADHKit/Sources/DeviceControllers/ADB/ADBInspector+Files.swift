import ADBClient
public import DeviceDomain
public import Foundation

extension ADBInspector {
    public func files(in directory: String) async throws -> [RemoteFile] {
        let sync = try await device.sync()
        defer { sync.close() }
        let entries = try await sync.list(directory)
        // Unreadable folders list as empty; tell them apart from folders that are really empty.
        if entries.isEmpty {
            let quoted = shellQuoted(directory)
            let readable = try await device.shell("test -r \(quoted) && test -x \(quoted)").exitCode == 0
            if !readable { throw InspectorError.permissionDenied }
        }
        return entries.map { Self.remoteFile($0, in: directory) }
            .sorted { lhs, rhs in
                if lhs.isFolderLike != rhs.isFolderLike { return lhs.isFolderLike }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
    }

    nonisolated static func remoteFile(_ entry: ADBFileEntry, in directory: String) -> RemoteFile {
        let kind: RemoteFile.Kind =
            if entry.isDirectory { .directory } else if entry.isSymbolicLink {
                .symbolicLink
            } else if entry.isRegularFile { .file } else { .other }
        return RemoteFile(
            name: entry.name,
            path: RemotePath.join(directory, entry.name),
            kind: kind,
            size: entry.size,
            modified: entry.modified
        )
    }

    public func download(
        _ file: RemoteFile, into folder: URL, progress: @escaping TransferProgressHandler
    ) async throws -> URL {
        let sync = try await device.sync()
        defer { sync.close() }
        let root = try await sync.stat(file.path)
        guard root.exists else { throw InspectorError.permissionDenied }
        let destination = Self.availableURL(for: file.name, in: folder)

        guard root.isDirectory else {
            try await sync.pull(file.path, to: destination, size: root.size) { completed, total in
                progress(TransferProgress(completed: completed, total: total))
            }
            return destination
        }

        // Folders: find every file first so progress covers the whole download.
        var files: [(remote: String, local: URL, size: Int64)] = []
        var folders: [URL] = [destination]
        var pending: [(remote: String, local: URL)] = [(file.path, destination)]
        while let (remote, local) = pending.popLast() {
            for entry in try await sync.list(remote) {
                let childRemote = RemotePath.join(remote, entry.name)
                let childLocal = local.appending(
                    path: entry.name, directoryHint: entry.isDirectory ? .isDirectory : .notDirectory)
                if entry.isDirectory {
                    folders.append(childLocal)
                    pending.append((childRemote, childLocal))
                } else if entry.isRegularFile {
                    files.append((childRemote, childLocal, entry.size))
                }
            }
        }
        for folder in folders {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        let total = files.reduce(0) { $0 + $1.size }
        var done: Int64 = 0
        for item in files {
            try Task.checkCancellation()
            let base = done
            try await sync.pull(item.remote, to: item.local, size: item.size) { completed, _ in
                progress(TransferProgress(completed: base + completed, total: total))
            }
            done += item.size
        }
        progress(TransferProgress(completed: total, total: total))
        return destination
    }

    public func upload(_ url: URL, into directory: String, progress: @escaping TransferProgressHandler) async throws {
        let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        let target = RemotePath.join(directory, url.lastPathComponent)
        var files: [(local: URL, remote: String, size: Int64)] = []
        var folders: [String] = []
        if isDirectory {
            folders.append(target)
            let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey]
            let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys)
            let base = url.standardizedFileURL.pathComponents.count
            while let child = enumerator?.nextObject() as? URL {
                let values = try child.resourceValues(forKeys: Set(keys))
                let relative = child.standardizedFileURL.pathComponents.dropFirst(base).joined(separator: "/")
                let remote = RemotePath.join(target, relative)
                if values.isDirectory == true {
                    folders.append(remote)
                } else {
                    files.append((child, remote, Int64(values.fileSize ?? 0)))
                }
            }
        } else {
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            files.append((url, target, Int64(size)))
        }

        if !folders.isEmpty {
            try await device.run("mkdir -p " + folders.map(shellQuoted).joined(separator: " "))
        }
        let sync = try await device.sync()
        defer { sync.close() }
        let total = files.reduce(0) { $0 + $1.size }
        var done: Int64 = 0
        for item in files {
            try Task.checkCancellation()
            let base = done
            do {
                try await sync.push(item.local, to: item.remote) { completed, _ in
                    progress(TransferProgress(completed: base + completed, total: total))
                }
            } catch let ADBError.failed(message) where message.localizedCaseInsensitiveContains("permission") {
                throw InspectorError.permissionDenied
            }
            done += item.size
        }
        progress(TransferProgress(completed: total, total: total))
    }

    public func makeDirectory(at path: String) async throws {
        try await runFileCommand("mkdir -p \(shellQuoted(path))")
    }

    public func delete(_ path: String) async throws {
        try await runFileCommand("rm -rf \(shellQuoted(path))")
    }

    public func move(_ path: String, to newPath: String) async throws {
        try await runFileCommand("mv -n \(shellQuoted(path)) \(shellQuoted(newPath))")
    }

    private func runFileCommand(_ command: String) async throws {
        do {
            try await device.run(command)
        } catch let ADBError.commandFailed(_, _, message) {
            if message.localizedCaseInsensitiveContains("permission denied")
                || message.localizedCaseInsensitiveContains("read-only file system")
            {
                throw InspectorError.permissionDenied
            }
            throw InspectorError.commandFailed(message)
        }
    }

    /// `name`, or `name 2`, `name 3`… when it already exists.
    nonisolated static func availableURL(for name: String, in folder: URL) -> URL {
        let fileManager = FileManager.default
        var candidate = folder.appending(path: name)
        let stem = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var index = 2
        while fileManager.fileExists(atPath: candidate.path(percentEncoded: false)) {
            let numbered = ext.isEmpty ? "\(stem) \(index)" : "\(stem) \(index).\(ext)"
            candidate = folder.appending(path: numbered)
            index += 1
        }
        return candidate
    }
}
