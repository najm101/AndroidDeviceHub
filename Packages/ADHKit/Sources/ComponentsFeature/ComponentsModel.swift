public import DeviceDomain
public import Foundation
public import Observation
public import SDKDomain

/// Dependencies of Settings → Components, wired by the app.
@MainActor
public struct ComponentsDependencies {
    public var context: SDKContext
    public var runChecks: @Sendable () async -> SetupReport
    public var setSDKRoot: @Sendable (URL?) async -> Void
    public var remotePackages: @Sendable (_ forceRefresh: Bool) async throws -> [RemotePackage]
    public var installedPackages: @Sendable (SDKLocation) async -> [LocalPackage]
    public var directorySize: @Sendable (URL) async -> Int64
    public var reveal: (URL) -> Void
    public var installs: any InstallCoordinating
    public var repository: any DeviceRepository

    public init(
        context: SDKContext,
        runChecks: @escaping @Sendable () async -> SetupReport,
        setSDKRoot: @escaping @Sendable (URL?) async -> Void,
        remotePackages: @escaping @Sendable (Bool) async throws -> [RemotePackage],
        installedPackages: @escaping @Sendable (SDKLocation) async -> [LocalPackage],
        directorySize: @escaping @Sendable (URL) async -> Int64,
        reveal: @escaping (URL) -> Void,
        installs: any InstallCoordinating,
        repository: any DeviceRepository
    ) {
        self.context = context
        self.runChecks = runChecks
        self.setSDKRoot = setSDKRoot
        self.remotePackages = remotePackages
        self.installedPackages = installedPackages
        self.directorySize = directorySize
        self.reveal = reveal
        self.installs = installs
        self.repository = repository
    }
}

/// SDK location, tools and installed system images.
@MainActor
@Observable
public final class ComponentsModel {
    struct ToolRow: Identifiable {
        var id: String { path }
        var path: String
        var title: String
        var installed: LocalPackage?
        var latest: RemotePackage?

        var updateAvailable: Bool {
            guard let installed, let latest else { return false }
            return latest.revision > installed.revision
        }
    }

    struct ImageRow: Identifiable {
        var id: String { package.path }
        var package: LocalPackage
        var size: Int64?
        var usedBy: [String]
    }

    private(set) var isLoading = false
    private(set) var installed: [LocalPackage] = []
    private(set) var catalog: [RemotePackage] = []
    private(set) var sizes: [String: Int64] = [:]
    var catalogError: String?
    var errorMessage: String?
    var pendingRemoval: LocalPackage?

    let dependencies: ComponentsDependencies

    public init(dependencies: ComponentsDependencies) {
        self.dependencies = dependencies
    }

    var report: SetupReport? { dependencies.context.report }
    var installs: any InstallCoordinating { dependencies.installs }

    var tools: [ToolRow] {
        [
            ToolRow(path: SDKPackagePath.emulator, title: "Android Emulator"),
            ToolRow(path: SDKPackagePath.platformTools, title: "Platform Tools (ADB)"),
        ].map { row in
            var row = row
            row.installed = installed.package(at: row.path)
            row.latest = catalog.latest(path: row.path)
            return row
        }
    }

    var images: [ImageRow] {
        let devices = dependencies.repository.devices
        return installed.compactMap { package -> ImageRow? in
            guard let details = package.systemImage else { return nil }
            let users =
                devices
                .filter {
                    $0.virtualDevice?.sysdir?.trimmingCharacters(in: ["/"])
                        == details.sysdir.trimmingCharacters(in: ["/"])
                }
                .map(\.name)
            return ImageRow(package: package, size: sizes[package.path], usedBy: users)
        }
        .sorted {
            $0.package.systemImage?.apiLevel ?? .init(major: 0) > $1.package.systemImage?.apiLevel ?? .init(major: 0)
        }
    }

    var totalImageSize: Int64 {
        images.compactMap(\.size).reduce(0, +)
    }

    // MARK: - Loading

    func load() async {
        isLoading = true
        defer { isLoading = false }
        dependencies.context.report = await dependencies.runChecks()
        await dependencies.repository.reload()
        await reloadInstalled()
        do {
            catalog = try await dependencies.remotePackages(false)
            catalogError = nil
        } catch {
            catalogError = error.localizedDescription
        }
    }

    func reloadInstalled() async {
        guard let location = report?.location else {
            installed = []
            return
        }
        installed = await dependencies.installedPackages(location)
        for package in installed where package.systemImage != nil && sizes[package.path] == nil {
            sizes[package.path] = await dependencies.directorySize(package.directory)
        }
    }

    func inventoryChanged() async {
        dependencies.context.report = await dependencies.runChecks()
        // Installing or removing Platform Tools changes what devices offer (ADB-backed inspector tabs).
        await dependencies.repository.reload()
        await reloadInstalled()
    }

    // MARK: - Actions

    func chooseSDKFolder(_ url: URL) async {
        await dependencies.setSDKRoot(url)
        sizes = [:]
        await load()
    }

    func resetSDKFolder() async {
        await dependencies.setSDKRoot(nil)
        sizes = [:]
        await load()
    }

    func reveal(_ url: URL) {
        dependencies.reveal(url)
    }

    func confirmRemoval() async {
        guard let package = pendingRemoval else { return }
        pendingRemoval = nil
        do {
            try await installs.uninstall(package)
            sizes[package.path] = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
