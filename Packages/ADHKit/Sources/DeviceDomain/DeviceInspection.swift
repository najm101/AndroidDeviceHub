public import Foundation

// MARK: - Info

public struct DeviceProperty: Hashable, Sendable, Identifiable {
    public var title: String
    public var value: String

    public init(_ title: String, _ value: String) {
        self.title = title
        self.value = value
    }

    public var id: String { title }
}

public struct DevicePropertyGroup: Hashable, Sendable, Identifiable {
    public var title: String
    public var properties: [DeviceProperty]

    public init(_ title: String, _ properties: [DeviceProperty]) {
        self.title = title
        self.properties = properties
    }

    public var id: String { title }
}

// MARK: - Apps

public struct InstalledApp: Hashable, Sendable, Identifiable {
    public var packageName: String
    public var uid: Int?
    public var versionCode: Int?
    public var apkPath: String?
    public var isSystem: Bool

    public init(packageName: String, uid: Int?, versionCode: Int?, apkPath: String?, isSystem: Bool) {
        self.packageName = packageName
        self.uid = uid
        self.versionCode = versionCode
        self.apkPath = apkPath
        self.isSystem = isSystem
    }

    public var id: String { packageName }
}

/// Byte progress of an upload, download or install.
public struct TransferProgress: Hashable, Sendable {
    public var completed: Int64
    public var total: Int64

    public init(completed: Int64, total: Int64) {
        self.completed = completed
        self.total = total
    }

    public var fraction: Double {
        total > 0 ? min(1, Double(completed) / Double(total)) : 0
    }
}

public typealias TransferProgressHandler = @Sendable (TransferProgress) -> Void

// MARK: - Profiles

public struct DeviceUser: Hashable, Sendable, Identifiable {
    public var id: Int
    public var name: String
    public var isRunning: Bool
    /// A work profile or other managed profile of another user.
    public var isProfile: Bool

    public init(id: Int, name: String, isRunning: Bool, isProfile: Bool = false) {
        self.id = id
        self.name = name
        self.isRunning = isRunning
        self.isProfile = isProfile
    }
}

public struct DeviceUsers: Hashable, Sendable {
    public var users: [DeviceUser]
    public var currentUserID: Int
    public var maximumUsers: Int
    public var supportsWorkProfiles: Bool

    public init(users: [DeviceUser], currentUserID: Int, maximumUsers: Int, supportsWorkProfiles: Bool) {
        self.users = users
        self.currentUserID = currentUserID
        self.maximumUsers = maximumUsers
        self.supportsWorkProfiles = supportsWorkProfiles
    }

    public var canAddUsers: Bool { users.count < maximumUsers }
}

// MARK: - Files

public struct RemoteFile: Hashable, Sendable, Identifiable {
    public enum Kind: Hashable, Sendable {
        case file
        case directory
        case symbolicLink
        case other
    }

    public var name: String
    public var path: String
    public var kind: Kind
    public var size: Int64
    public var modified: Date

    public init(name: String, path: String, kind: Kind, size: Int64, modified: Date) {
        self.name = name
        self.path = path
        self.kind = kind
        self.size = size
        self.modified = modified
    }

    public var id: String { path }
    public var isFolderLike: Bool { kind == .directory || kind == .symbolicLink }
}

public enum RemotePath {
    public static func join(_ directory: String, _ name: String) -> String {
        directory.hasSuffix("/") ? directory + name : directory + "/" + name
    }

    public static func parent(of path: String) -> String {
        let trimmed = path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
        guard let slash = trimmed.lastIndex(of: "/"), trimmed != "/" else { return "/" }
        return slash == trimmed.startIndex ? "/" : String(trimmed[..<slash])
    }

    /// `/sdcard/Download` → `["/", "/sdcard", "/sdcard/Download"]`
    public static func ancestors(of path: String) -> [String] {
        var result = ["/"]
        var current = ""
        for component in path.split(separator: "/") {
            current += "/" + component
            result.append(current)
        }
        return result
    }

    public static func name(of path: String) -> String {
        path == "/" ? "/" : String(path.split(separator: "/").last ?? "")
    }

    /// File names can't contain slashes or be `.`/`..`.
    public static func validationError(forName name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return "Enter a name." }
        if trimmed.contains("/") { return "Names can't contain “/”." }
        if trimmed == "." || trimmed == ".." { return "Choose a different name." }
        return nil
    }
}

// MARK: - Reports

public struct CrashReport: Hashable, Sendable, Identifiable {
    public enum Kind: String, Hashable, Sendable, CaseIterable {
        case appCrash
        case appNotResponding
        case nativeCrash
        case systemCrash

        public var title: String {
            switch self {
            case .appCrash: "Crash"
            case .appNotResponding: "Not Responding"
            case .nativeCrash: "Native Crash"
            case .systemCrash: "System Crash"
            }
        }
    }

    public var id: String
    public var kind: Kind
    public var tag: String
    public var date: Date
    /// The process or package name, when the report names one.
    public var process: String?
    public var text: String

    public init(id: String, kind: Kind, tag: String, date: Date, process: String?, text: String) {
        self.id = id
        self.kind = kind
        self.tag = tag
        self.date = date
        self.process = process
        self.text = text
    }

    /// A one-line description: the abort message or signal for native crashes, otherwise the first line
    /// of the report body (after the `Key: value` header block), which is usually the exception.
    public var summary: String {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        if let abort = lines.first(where: { $0.hasPrefix("Abort message:") }) {
            return abort.dropFirst("Abort message:".count).trimmingCharacters(in: CharacterSet(charactersIn: " '"))
        }
        if let signal = lines.first(where: { $0.hasPrefix("signal ") }) {
            return signal
        }
        let body = lines.firstIndex(of: "").map { lines[($0 + 1)...] } ?? lines[...]
        return body.first { !$0.isEmpty && !$0.hasPrefix("***") } ?? kind.title
    }
}

public enum LogLevel: Int, Hashable, Sendable, CaseIterable, Comparable, Identifiable {
    case verbose = 2
    case debug = 3
    case info = 4
    case warning = 5
    case error = 6
    case fatal = 7

    public var id: Int { rawValue }
    public var letter: String {
        switch self {
        case .verbose: "V"
        case .debug: "D"
        case .info: "I"
        case .warning: "W"
        case .error: "E"
        case .fatal: "F"
        }
    }

    public var title: String {
        switch self {
        case .verbose: "Verbose"
        case .debug: "Debug"
        case .info: "Info"
        case .warning: "Warning"
        case .error: "Error"
        case .fatal: "Fatal"
        }
    }

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

public struct LogEntry: Hashable, Sendable, Identifiable {
    public var id: Int
    public var date: Date
    public var pid: Int
    public var tid: Int
    public var uid: Int?
    public var level: LogLevel
    public var tag: String
    public var message: String

    public init(id: Int, date: Date, pid: Int, tid: Int, uid: Int?, level: LogLevel, tag: String, message: String) {
        self.id = id
        self.date = date
        self.pid = pid
        self.tid = tid
        self.uid = uid
        self.level = level
        self.tag = tag
        self.message = message
    }
}

// MARK: - Protocols

/// Inspector ▸ Info.
@MainActor
public protocol DeviceInfoProviding: AnyObject {
    func properties() async throws -> [DevicePropertyGroup]
}

/// Inspector ▸ Info ▸ Apps.
@MainActor
public protocol AppManaging: AnyObject {
    func apps(user: Int) async throws -> [InstalledApp]
    /// The app's display name, read from its APK. `nil` when the app has none or it can't be read.
    func label(for app: InstalledApp) async -> String?
    /// Installs one app from an `.apk`, an `.apks` archive or a folder of split APKs.
    func install(_ file: URL, user: Int, progress: @escaping TransferProgressHandler) async throws
    func launch(_ packageName: String, user: Int) async throws
    func forceStop(_ packageName: String, user: Int) async throws
    func clearData(_ packageName: String, user: Int) async throws
    func uninstall(_ packageName: String, user: Int) async throws
}

/// Inspector ▸ Info ▸ Profiles.
@MainActor
public protocol ProfileManaging: AnyObject {
    func users() async throws -> DeviceUsers
    func switchToUser(_ id: Int) async throws
    func createUser(named name: String) async throws
    func createWorkProfile(named name: String, for parentID: Int) async throws
    func removeUser(_ id: Int) async throws
}

/// Inspector ▸ Files.
@MainActor
public protocol FileBrowsing: AnyObject {
    /// Where browsing starts.
    var homeDirectory: String { get }
    func files(in directory: String) async throws -> [RemoteFile]
    /// Downloads a file or folder into `folder` and returns the local URL.
    func download(_ file: RemoteFile, into folder: URL, progress: @escaping TransferProgressHandler) async throws -> URL
    /// Uploads a local file or folder into `directory`.
    func upload(_ url: URL, into directory: String, progress: @escaping TransferProgressHandler) async throws
    func makeDirectory(at path: String) async throws
    func delete(_ path: String) async throws
    func move(_ path: String, to newPath: String) async throws
}

/// Inspector ▸ Reports and the Logcat window.
@MainActor
public protocol ReportProviding: AnyObject {
    func crashReports() async throws -> [CrashReport]
    /// Recent entries first, then new ones as they're logged, in batches.
    func logEntries(recent: Int) -> AsyncThrowingStream<[LogEntry], any Error>
    /// Writes a bug report zip into `folder` and returns its URL. `progress` is 0–1 when known.
    func bugReport(into folder: URL, progress: @escaping @Sendable (Double?) -> Void) async throws -> URL
}

/// Everything the ADB-backed inspector tabs need.
public typealias DeviceInspecting = AppManaging & DeviceInfoProviding & FileBrowsing & ProfileManaging
    & ReportProviding

/// Why the ADB-backed tabs are unavailable.
public enum InspectorHint {
    public static let installPlatformTools =
        "Install Platform Tools in Settings → Components to enable this."
    public static let connecting = "Waiting for the device to connect over ADB…"
    public static let startFirst = "Start the device to use this."
}
