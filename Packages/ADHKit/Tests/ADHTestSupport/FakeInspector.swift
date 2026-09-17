public import DeviceDomain
public import Foundation

/// An in-memory `DeviceInspecting` with a small file tree, apps and users.
@MainActor
public final class FakeInspector: DeviceInspecting {
    public struct Failure: LocalizedError {
        public var message: String
        public init(_ message: String) { self.message = message }
        public var errorDescription: String? { message }
    }

    public var homeDirectory = "/"
    public var groups = [DevicePropertyGroup("Device", [DeviceProperty("Model", "Pixel")])]
    public var installedApps: [InstalledApp] = [
        InstalledApp(packageName: "com.android.settings", uid: 1000, versionCode: 36, apkPath: nil, isSystem: true),
        InstalledApp(packageName: "com.example.app", uid: 10190, versionCode: 3, apkPath: nil, isSystem: false),
    ]
    public var deviceUsers = DeviceUsers(
        users: [DeviceUser(id: 0, name: "Owner", isRunning: true)],
        currentUserID: 0, maximumUsers: 4, supportsWorkProfiles: true)
    /// Directory path → entries.
    public var tree: [String: [RemoteFile]] = [
        "/": [RemoteFile(name: "sdcard", path: "/sdcard", kind: .directory, size: 0, modified: .distantPast)],
        "/sdcard": [RemoteFile(name: "a.txt", path: "/sdcard/a.txt", kind: .file, size: 5, modified: .distantPast)],
    ]
    public var reports: [CrashReport] = []
    public var logBatches: [[LogEntry]] = []
    public var error: (any Error)?
    public var display = DisplayMetrics(physicalSize: PixelSize(width: 1080, height: 2400), physicalDensity: 420)

    public private(set) var log: [String] = []

    public init() {}

    private func record(_ entry: String) throws {
        log.append(entry)
        if let error { throw error }
    }

    public func properties() async throws -> [DevicePropertyGroup] {
        try record("properties")
        return groups
    }

    public func apps(user: Int) async throws -> [InstalledApp] {
        try record("apps \(user)")
        return installedApps
    }

    public var labels: [String: String] = ["com.example.app": "Example"]

    public func label(for app: InstalledApp) async -> String? {
        log.append("label \(app.packageName)")
        return labels[app.packageName]
    }

    public func install(_ file: URL, user: Int, progress: @escaping TransferProgressHandler) async throws {
        progress(TransferProgress(completed: 5, total: 10))
        try record("install \(file.lastPathComponent) \(user)")
        progress(TransferProgress(completed: 10, total: 10))
        installedApps.append(
            InstalledApp(packageName: "com.new.app", uid: 10200, versionCode: 1, apkPath: nil, isSystem: false))
    }

    public func launch(_ packageName: String, user: Int) async throws { try record("launch \(packageName)") }
    public func forceStop(_ packageName: String, user: Int) async throws { try record("stop \(packageName)") }
    public func clearData(_ packageName: String, user: Int) async throws { try record("clear \(packageName)") }

    public func uninstall(_ packageName: String, user: Int) async throws {
        try record("uninstall \(packageName)")
        installedApps.removeAll { $0.packageName == packageName }
    }

    public func users() async throws -> DeviceUsers {
        try record("users")
        return deviceUsers
    }

    public func switchToUser(_ id: Int) async throws {
        try record("switch \(id)")
        deviceUsers.currentUserID = id
    }

    public func createUser(named name: String) async throws {
        try record("create \(name)")
        deviceUsers.users.append(DeviceUser(id: 10, name: name, isRunning: false))
    }

    public func createWorkProfile(named name: String, for parentID: Int) async throws {
        try record("profile \(name) \(parentID)")
    }

    public func removeUser(_ id: Int) async throws {
        try record("remove \(id)")
        deviceUsers.users.removeAll { $0.id == id }
    }

    public func files(in directory: String) async throws -> [RemoteFile] {
        try record("files \(directory)")
        guard let entries = tree[directory] else { throw Failure("Requires root.") }
        return entries
    }

    public func download(
        _ file: RemoteFile, into folder: URL, progress: @escaping TransferProgressHandler
    ) async throws -> URL {
        try record("download \(file.path)")
        progress(TransferProgress(completed: file.size, total: file.size))
        return folder.appending(path: file.name)
    }

    public func upload(_ url: URL, into directory: String, progress: @escaping TransferProgressHandler) async throws {
        try record("upload \(url.lastPathComponent) \(directory)")
        let path = RemotePath.join(directory, url.lastPathComponent)
        tree[directory, default: []].append(
            RemoteFile(name: url.lastPathComponent, path: path, kind: .file, size: 1, modified: .now))
    }

    public func makeDirectory(at path: String) async throws {
        try record("mkdir \(path)")
        tree[RemotePath.parent(of: path), default: []].append(
            RemoteFile(name: RemotePath.name(of: path), path: path, kind: .directory, size: 0, modified: .now))
    }

    public func delete(_ path: String) async throws {
        try record("delete \(path)")
        tree[RemotePath.parent(of: path)]?.removeAll { $0.path == path }
    }

    public func move(_ path: String, to newPath: String) async throws {
        try record("move \(path) \(newPath)")
    }

    public func crashReports() async throws -> [CrashReport] {
        try record("crashes")
        return reports
    }

    public func logEntries(recent: Int) -> AsyncThrowingStream<[LogEntry], any Error> {
        let batches = logBatches
        return AsyncThrowingStream { continuation in
            for batch in batches { continuation.yield(batch) }
            continuation.finish()
        }
    }

    public func bugReport(into folder: URL, progress: @escaping @Sendable (Double?) -> Void) async throws -> URL {
        progress(0.5)
        try record("bugreport")
        return folder.appending(path: "bugreport.zip")
    }
}

extension LogEntry {
    public static func sample(
        _ id: Int, level: LogLevel = .info, tag: String = "Tag", message: String = "hello", uid: Int? = 1000
    ) -> LogEntry {
        LogEntry(id: id, date: .now, pid: 100, tid: 101, uid: uid, level: level, tag: tag, message: message)
    }
}

extension FakeInspector: DisplayOverriding {
    public func displayMetrics() async throws -> DisplayMetrics {
        try record("wm")
        return display
    }

    public func setDisplayOverride(_ configuration: DisplayConfiguration?) async throws {
        try record("wm \(configuration.map { "\($0.size.width)x\($0.size.height)@\($0.density)" } ?? "reset")")
        display.overrideSize = configuration?.size
        display.overrideDensity = configuration?.density
    }
}
