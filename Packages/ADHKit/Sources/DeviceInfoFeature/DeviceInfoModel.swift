public import DeviceDomain
import Foundation
public import Observation

/// Dependencies of Inspector ▸ Info, wired by the app.
@MainActor
public struct DeviceInfoDependencies {
    public var repository: any DeviceRepository

    public init(repository: any DeviceRepository) {
        self.repository = repository
    }
}

/// Inspector ▸ Info, Apps and Profiles for one device.
@MainActor
@Observable
public final class DeviceInfoModel {
    enum Page: String, CaseIterable, Identifiable {
        case info, apps, profiles

        var id: String { rawValue }
        var title: String {
            switch self {
            case .info: "Info"
            case .apps: "Apps"
            case .profiles: "Profiles"
            }
        }

        var capability: Capability {
            switch self {
            case .info: .info
            case .apps: .apps
            case .profiles: .profiles
            }
        }
    }

    enum AppFilter: String, CaseIterable, Identifiable {
        case user, system, all

        var id: String { rawValue }
        var title: String {
            switch self {
            case .user: "Installed"
            case .system: "System"
            case .all: "All"
            }
        }
    }

    struct InstallState: Equatable {
        var fileName: String
        var progress: TransferProgress?
    }

    var page: Page = .info
    var errorMessage: String?
    private(set) var statusMessage: String?

    // Info
    private(set) var properties: [DevicePropertyGroup] = []
    private(set) var isLoadingInfo = false

    // Apps
    var appFilter: AppFilter = .user
    var appSearch = ""
    private(set) var apps: [InstalledApp] = []
    private(set) var isLoadingApps = false
    private(set) var installs: [InstallState] = []
    private(set) var busyApps: Set<String> = []
    /// Display names by package, filled in as rows appear.
    private(set) var labels: [String: String] = [:]
    @ObservationIgnored private var requestedLabels: Set<String> = []

    // Profiles
    private(set) var users: DeviceUsers?
    private(set) var isLoadingUsers = false
    private(set) var isChangingUsers = false

    let deviceID: DeviceID
    private let dependencies: DeviceInfoDependencies

    public init(deviceID: DeviceID, dependencies: DeviceInfoDependencies) {
        self.deviceID = deviceID
        self.dependencies = dependencies
    }

    var device: Device? { dependencies.repository.device(withID: deviceID) }

    func availability(of page: Page) -> Availability {
        device?.availability(of: page.capability) ?? .hidden
    }

    /// The user whose apps are shown and who receives installs.
    var currentUserID: Int { users?.currentUserID ?? 0 }

    // MARK: - Info

    func loadInfo() async {
        guard let inspector = inspector() else { return }
        isLoadingInfo = properties.isEmpty
        defer { isLoadingInfo = false }
        do {
            properties = try await inspector.properties()
        } catch {
            show(error)
        }
    }

    // MARK: - Apps

    var visibleApps: [InstalledApp] {
        let query = appSearch.trimmingCharacters(in: .whitespaces)
        return apps.filter { app in
            switch appFilter {
            case .user: guard !app.isSystem else { return false }
            case .system: guard app.isSystem else { return false }
            case .all: break
            }
            return query.isEmpty || app.packageName.localizedCaseInsensitiveContains(query)
                || labels[app.packageName]?.localizedCaseInsensitiveContains(query) == true
        }
    }

    func loadApps() async {
        guard let inspector = inspector() else { return }
        isLoadingApps = apps.isEmpty
        defer { isLoadingApps = false }
        do {
            if users == nil { users = try? await inspector.users() }
            apps = try await inspector.apps(user: currentUserID)
        } catch {
            show(error)
        }
    }

    /// Reads the app's display name once, when its row first appears.
    func loadLabel(for app: InstalledApp) async {
        guard !requestedLabels.contains(app.packageName),
            let inspector = dependencies.repository.inspector(for: deviceID)
        else { return }
        requestedLabels.insert(app.packageName)
        if let label = await inspector.label(for: app) {
            labels[app.packageName] = label
        }
    }

    /// Installs each file in turn: `.apk`, `.apks`, or a folder of split APKs.
    func install(_ files: [URL]) {
        guard let inspector = inspector() else { return }
        let files = files.filter(Self.isInstallable)
        guard !files.isEmpty else {
            errorMessage = "Drop an .apk or .apks file, or a folder of split APKs."
            return
        }
        let user = currentUserID
        Task {
            for file in files {
                let name = file.lastPathComponent
                installs.append(InstallState(fileName: name))
                defer { installs.removeAll { $0.fileName == name } }
                do {
                    let updates = AsyncStream<TransferProgress>.makeStream()
                    let watcher = Task {
                        for await progress in updates.stream {
                            if let index = installs.firstIndex(where: { $0.fileName == name }) {
                                installs[index].progress = progress
                            }
                        }
                    }
                    defer { watcher.cancel() }
                    try await inspector.install(file, user: user) { updates.continuation.yield($0) }
                    updates.continuation.finish()
                    statusMessage = "Installed \(name)"
                } catch {
                    show(error, prefix: "Couldn't install \(name)")
                }
            }
            await loadApps()
        }
    }

    nonisolated static func isInstallable(_ url: URL) -> Bool {
        let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        return isDirectory || ["apk", "apks", "xapk"].contains(url.pathExtension.lowercased())
    }

    func launch(_ app: InstalledApp) {
        runAppAction(app, done: "Opened \(app.packageName)") { try await $0.launch($1, user: $2) }
    }

    func forceStop(_ app: InstalledApp) {
        runAppAction(app, done: "Stopped \(app.packageName)") { try await $0.forceStop($1, user: $2) }
    }

    func clearData(_ app: InstalledApp) {
        runAppAction(app, done: "Cleared data of \(app.packageName)") { try await $0.clearData($1, user: $2) }
    }

    func uninstall(_ app: InstalledApp) {
        runAppAction(app, done: "Uninstalled \(app.packageName)", reload: true) {
            try await $0.uninstall($1, user: $2)
        }
    }

    private func runAppAction(
        _ app: InstalledApp,
        done message: String,
        reload: Bool = false,
        _ action: @escaping @MainActor (any DeviceInspecting, String, Int) async throws -> Void
    ) {
        guard let inspector = inspector(), !busyApps.contains(app.packageName) else { return }
        busyApps.insert(app.packageName)
        let user = currentUserID
        Task {
            defer { busyApps.remove(app.packageName) }
            do {
                try await action(inspector, app.packageName, user)
                statusMessage = message
                if reload { await loadApps() }
            } catch {
                show(error)
            }
        }
    }

    // MARK: - Profiles

    func loadUsers() async {
        guard let inspector = inspector() else { return }
        isLoadingUsers = users == nil
        defer { isLoadingUsers = false }
        do {
            users = try await inspector.users()
        } catch {
            show(error)
        }
    }

    func switchToUser(_ user: DeviceUser) {
        changeUsers(done: "Switched to \(user.name)") { try await $0.switchToUser(user.id) }
    }

    func createUser(named name: String) {
        let name = name.trimmingCharacters(in: .whitespaces)
        changeUsers(done: "Created \(name)") { try await $0.createUser(named: name) }
    }

    func createWorkProfile(named name: String) {
        let name = name.trimmingCharacters(in: .whitespaces)
        let parent = currentUserID
        changeUsers(done: "Created \(name)") { try await $0.createWorkProfile(named: name, for: parent) }
    }

    func removeUser(_ user: DeviceUser) {
        changeUsers(done: "Removed \(user.name)") { try await $0.removeUser(user.id) }
    }

    func canRemove(_ user: DeviceUser) -> Bool {
        user.id != 0 && user.id != currentUserID
    }

    private func changeUsers(
        done message: String, _ action: @escaping @MainActor (any DeviceInspecting) async throws -> Void
    ) {
        guard let inspector = inspector(), !isChangingUsers else { return }
        isChangingUsers = true
        Task {
            defer { isChangingUsers = false }
            do {
                try await action(inspector)
                statusMessage = message
            } catch {
                show(error)
            }
            await loadUsers()
            // Apps are listed per user.
            apps = []
        }
    }

    // MARK: - Messages

    func dismissStatus() {
        statusMessage = nil
    }

    private func show(_ error: any Error, prefix: String? = nil) {
        guard !(error is CancellationError) else { return }
        let text = error.localizedDescription
        errorMessage = prefix.map { "\($0): \(text)" } ?? text
    }

    private func inspector() -> (any DeviceInspecting)? {
        guard let inspector = dependencies.repository.inspector(for: deviceID) else {
            errorMessage = availability(of: page).reason ?? "The device isn't connected."
            return nil
        }
        return inspector
    }
}
