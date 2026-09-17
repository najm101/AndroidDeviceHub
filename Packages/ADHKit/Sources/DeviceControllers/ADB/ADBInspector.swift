public import ADBClient
public import DeviceDomain
public import Foundation
import Foundations
import ZIPFoundation

/// Info, apps, profiles, files and reports for one device, over ADB.
@MainActor
public final class ADBInspector: DeviceInspecting {
    public let serial: String
    public let homeDirectory: String
    let device: ADBDevice
    /// Extra rows shown at the end of Info (the emulator's own details).
    private let extraProperties: [DevicePropertyGroup]
    private let temporaryDirectory: URL
    private let labelCache: AppLabelCache

    public init(
        device: ADBDevice,
        homeDirectory: String,
        extraProperties: [DevicePropertyGroup] = [],
        temporaryDirectory: URL = FileManager.default.temporaryDirectory,
        labelCache: AppLabelCache = AppLabelCache(file: nil)
    ) {
        self.labelCache = labelCache
        self.device = device
        serial = device.serial
        self.homeDirectory = homeDirectory
        self.extraProperties = extraProperties
        self.temporaryDirectory = temporaryDirectory.appending(path: "adh-adb", directoryHint: .isDirectory)
    }

    // MARK: - Info

    public func properties() async throws -> [DevicePropertyGroup] {
        let output = try await device.run(
            "getprop; echo @@; wm size; echo @@; wm density; echo @@; cat /proc/meminfo; echo @@; "
                + "df -k /data; echo @@; cat /proc/uptime; echo @@; nproc")
        let parts = DeviceOutputParsers.sections(output)
        func part(_ index: Int) -> String { index < parts.count ? parts[index] : "" }
        let props = DeviceOutputParsers.properties(part(0))
        func prop(_ key: String) -> String? { props[key].flatMap { $0.isEmpty ? nil : $0 } }

        var device: [DeviceProperty] = []
        func add(_ list: inout [DeviceProperty], _ title: String, _ value: String?) {
            if let value, !value.isEmpty { list.append(DeviceProperty(title, value)) }
        }
        add(&device, "Model", prop("ro.product.model"))
        add(&device, "Manufacturer", prop("ro.product.manufacturer"))
        add(&device, "Serial", serial)

        var software: [DeviceProperty] = []
        let sdk = prop("ro.build.version.sdk")
        add(&software, "Android", prop("ro.build.version.release_or_codename") ?? prop("ro.build.version.release"))
        add(&software, "API level", sdk)
        add(&software, "Security patch", prop("ro.build.version.security_patch"))
        add(&software, "Build", prop("ro.build.display.id"))
        add(&software, "Build type", prop("ro.build.type"))
        add(&software, "Locale", prop("persist.sys.locale") ?? prop("ro.product.locale"))
        add(&software, "Time zone", prop("persist.sys.timezone"))

        var hardware: [DeviceProperty] = []
        add(&hardware, "ABI", prop("ro.product.cpu.abilist") ?? prop("ro.product.cpu.abi"))
        add(&hardware, "CPU cores", part(6).trimmingCharacters(in: .whitespacesAndNewlines))
        add(
            &hardware, "RAM",
            DeviceOutputParsers.memInfo(part(3), key: "MemTotal").map { $0.formatted(.byteCount(style: .memory)) })
        add(&hardware, "Resolution", DeviceOutputParsers.screenSize(part(1)))
        add(&hardware, "Density", DeviceOutputParsers.lastInteger(part(2)).map { "\($0) dpi" })
        if let disk = DeviceOutputParsers.diskUsage(part(4)) {
            let used = disk.used.formatted(.byteCount(style: .file))
            let total = disk.total.formatted(.byteCount(style: .file))
            add(&hardware, "Storage", "\(used) of \(total) used")
        }
        if let seconds = part(5).split(separator: " ").first.flatMap({ Double($0) }) {
            let uptime = Duration.seconds(Int(seconds))
                .formatted(.units(allowed: [.days, .hours, .minutes], width: .abbreviated))
            add(&hardware, "Uptime", uptime)
        }

        return [
            DevicePropertyGroup("Device", device),
            DevicePropertyGroup("Software", software),
            DevicePropertyGroup("Hardware", hardware),
        ].filter { !$0.properties.isEmpty } + extraProperties
    }

    // MARK: - Apps

    public func apps(user: Int) async throws -> [InstalledApp] {
        let output = try await device.run(
            "pm list packages -f -U --show-versioncode --user \(user); echo @@; pm list packages -3 --user \(user)")
        let parts = DeviceOutputParsers.sections(output)
        let thirdParty = DeviceOutputParsers.packageNames(parts.count > 1 ? parts[1] : "")
        return DeviceOutputParsers.packages(parts[0], thirdParty: thirdParty)
            .sorted { $0.packageName.localizedStandardCompare($1.packageName) == .orderedAscending }
    }

    public func label(for app: InstalledApp) async -> String? {
        guard let path = app.apkPath else { return nil }
        return await labelCache.label(
            packageName: app.packageName, apkPath: path, versionCode: app.versionCode, device: device)
    }

    public func install(_ file: URL, user: Int, progress: @escaping TransferProgressHandler) async throws {
        let workspace = temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: workspace) }
        let apks = try Self.apkFiles(for: file, workspace: workspace)
        try await device.install(apks, user: user) { completed, total in
            progress(TransferProgress(completed: completed, total: total))
        }
    }

    /// The APKs to install for a file the user picked.
    nonisolated static func apkFiles(for file: URL, workspace: URL) throws -> [URL] {
        let fileManager = FileManager.default
        let isDirectory = (try? file.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        if isDirectory {
            return try apks(inFolder: file)
        }
        switch file.pathExtension.lowercased() {
        case "apk":
            return [file]
        case "apks", "xapk", "zip":
            try fileManager.createDirectory(at: workspace, withIntermediateDirectories: true)
            try fileManager.unzipItem(at: file, to: workspace)
            // bundletool's universal mode produces one APK that fits every device.
            if let universal = try apks(inFolder: workspace).first(where: { $0.lastPathComponent == "universal.apk" }) {
                return [universal]
            }
            return try apks(inFolder: workspace)
        default:
            throw InspectorError.unsupportedFile(file.lastPathComponent)
        }
    }

    nonisolated private static func apks(inFolder folder: URL) throws -> [URL] {
        let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil)
        let apks = (enumerator?.allObjects as? [URL] ?? [])
            .filter { $0.pathExtension.lowercased() == "apk" }
            // The base APK first, then splits in a stable order.
            .sorted { lhs, rhs in
                let lhsBase = lhs.lastPathComponent.hasPrefix("base")
                let rhsBase = rhs.lastPathComponent.hasPrefix("base")
                return lhsBase != rhsBase ? lhsBase : lhs.path < rhs.path
            }
        guard !apks.isEmpty else { throw InspectorError.noAPKs }
        return apks
    }

    public func launch(_ packageName: String, user: Int) async throws {
        let package = shellQuoted(packageName)
        let resolved = try await device.run(
            "cmd package resolve-activity --brief --user \(user) -a android.intent.action.MAIN "
                + "-c android.intent.category.LAUNCHER \(package)")
        guard let component = resolved.split(whereSeparator: \.isNewline).last(where: { $0.contains("/") }) else {
            throw InspectorError.noLaunchableActivity
        }
        let output = try await device.run("am start --user \(user) -n \(shellQuoted(String(component)))")
        if output.contains("Error") { throw InspectorError.commandFailed(output) }
    }

    public func forceStop(_ packageName: String, user: Int) async throws {
        try await device.run("am force-stop --user \(user) \(shellQuoted(packageName))")
    }

    public func clearData(_ packageName: String, user: Int) async throws {
        try PackageManagerOutput.check(try await device.run("pm clear --user \(user) \(shellQuoted(packageName))"))
    }

    public func uninstall(_ packageName: String, user: Int) async throws {
        try PackageManagerOutput.check(try await device.run("pm uninstall --user \(user) \(shellQuoted(packageName))"))
    }

    // MARK: - Profiles

    public func users() async throws -> DeviceUsers {
        let output = try await device.run(
            "pm list users; echo @@; am get-current-user; echo @@; pm get-max-users; echo @@; "
                + "pm has-feature android.software.managed_users")
        let parts = DeviceOutputParsers.sections(output)
        func part(_ index: Int) -> String { index < parts.count ? parts[index] : "" }
        return DeviceUsers(
            users: DeviceOutputParsers.users(part(0)),
            currentUserID: DeviceOutputParsers.lastInteger(part(1)) ?? 0,
            maximumUsers: DeviceOutputParsers.lastInteger(part(2)) ?? 1,
            supportsWorkProfiles: part(3).contains("true")
        )
    }

    public func switchToUser(_ id: Int) async throws {
        try await device.run("am switch-user \(id)")
    }

    public func createUser(named name: String) async throws {
        try Self.checkUserCommand(try await device.shell("pm create-user \(shellQuoted(name))"))
    }

    public func createWorkProfile(named name: String, for parentID: Int) async throws {
        let result = try await device.shell("pm create-user --profileOf \(parentID) --managed \(shellQuoted(name))")
        try Self.checkUserCommand(result)
        if let id = DeviceOutputParsers.lastInteger(result.output) {
            _ = try? await device.run("am start-user \(id)")
        }
    }

    public func removeUser(_ id: Int) async throws {
        try Self.checkUserCommand(try await device.shell("pm remove-user \(id)"))
    }

    nonisolated static func checkUserCommand(_ result: ShellResult) throws {
        let output = (result.output + result.errorOutput).trimmingCharacters(in: .whitespacesAndNewlines)
        guard result.exitCode == 0, output.hasPrefix("Success") else {
            throw InspectorError.commandFailed(output.isEmpty ? "The device refused the change." : output)
        }
    }
}

public enum InspectorError: LocalizedError, Equatable {
    case unsupportedFile(String)
    case noAPKs
    case noLaunchableActivity
    case commandFailed(String)
    case permissionDenied
    case bugReportFailed(String)

    public var errorDescription: String? {
        switch self {
        case let .unsupportedFile(name): "“\(name)” isn't an APK, APKS archive or folder of APKs."
        case .noAPKs: "No APK files were found."
        case .noLaunchableActivity: "This app has no screen to open."
        case let .commandFailed(output): output
        case .permissionDenied: "Requires root."
        case let .bugReportFailed(reason): "The bug report failed: \(reason)"
        }
    }
}
