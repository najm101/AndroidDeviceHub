import ADBRuntime
import AVDStore
import AddEmulatorFeature
import AppKit
import ComponentsFeature
import DeviceControllers
import DeviceDomain
import DeviceInfoFeature
import DeviceListFeature
import DeviceSettingsFeature
import DeviceWorkspaceFeature
import EmulatorRuntime
import FilesFeature
import Foundation
import Foundations
import HardwareProfiles
import OnboardingFeature
import ReportsFeature
import SDKCatalog
import SDKDomain
import SDKInstaller
import SDKLocator
import SetupChecks

/// The composition root: the only place that creates concrete implementations.
@MainActor
final class AppComposition {
    let preferences: any KeyValueStore
    let context = SDKContext()
    let installs: InstallCoordinator
    let repository: LiveDeviceRepository
    let profiles: [HardwareProfile]

    private let fileSystem: any FileSystem = LiveFileSystem()
    private let locator: SDKLocator
    private let inventory = LocalSDKInventory()
    private let catalog: RemoteSDKCatalog
    private let checker: SetupChecker

    init(preferences: any KeyValueStore = UserDefaultsStore()) {
        self.preferences = preferences
        let caches = URL.cachesDirectory.appending(
            path: "io.github.najm101.AndroidDeviceApp", directoryHint: .isDirectory)

        locator = SDKLocator(preferences: preferences)
        catalog = RemoteSDKCatalog(cacheDirectory: caches.appending(path: "catalog", directoryHint: .isDirectory))
        checker = SetupChecker(locator: locator, inventory: inventory)
        installs = InstallCoordinator(installer: PackageInstaller(), context: context)

        let hardware = BundledHardwareProfiles()
        profiles = hardware.profiles()
        repository = LiveDeviceRepository(
            context: context,
            avdStore: AVDFileStore(),
            profiles: hardware,
            discovery: EmulatorDiscovery(),
            launcher: EmulatorLauncher(logDirectory: caches.appending(path: "logs", directoryHint: .isDirectory)),
            frameDirectory: caches.appending(path: "frames", directoryHint: .isDirectory),
            showsEmulatorWindow: { [preferences] in preferences.bool(forKey: PreferenceKey.showEmulatorWindow) },
            adb: ADBRuntime(logFile: caches.appending(path: "logs/adb-server.log", directoryHint: .notDirectory)),
            labelCache: AppLabelCache(file: caches.appending(path: "app-labels.json", directoryHint: .notDirectory)),
            reveal: { NSWorkspace.shared.activateFileViewerSelecting([$0]) }
        )
    }

    // MARK: - Onboarding state

    var isOnboardingCompleted: Bool {
        preferences.integer(forKey: PreferenceKey.onboardingCompletedVersion) >= OnboardingVersion.current
    }

    func markOnboardingCompleted(skippedPlatformTools: Bool) {
        preferences.set(OnboardingVersion.current, forKey: PreferenceKey.onboardingCompletedVersion)
        preferences.set(skippedPlatformTools, forKey: PreferenceKey.platformToolsSkipped)
    }

    func runSetupChecks() async -> SetupReport {
        let report = await checker.run()
        context.report = report
        return report
    }

    // MARK: - Shared operations

    private var systemImagesOperation: @Sendable (Bool) async throws -> [SystemImageEntry] {
        let catalog = catalog
        let inventory = inventory
        let context = context
        return { forceRefresh in
            guard let location = await context.location else { return [] }
            async let remote = catalog.remotePackages(forceRefresh: forceRefresh)
            let installed = await inventory.installedPackages(in: location)
            return SystemImageEntry.merge(remote: try await remote, installed: installed)
        }
    }

    private var packageForSysdirOperation: @Sendable (String) async -> RemotePackage? {
        let catalog = catalog
        return { sysdir in
            let path = sysdir.trimmingCharacters(in: ["/"]).replacingOccurrences(of: "/", with: ";")
            return try? await catalog.remotePackages(forceRefresh: false).latest(path: path, upTo: .canary)
        }
    }

    private var remotePackagesOperation: @Sendable (Bool) async throws -> [RemotePackage] {
        let catalog = catalog
        return { try await catalog.remotePackages(forceRefresh: $0) }
    }

    private var setSDKRootOperation: @Sendable (URL?) async -> Void {
        let locator = locator
        return { await locator.setUserSDKRoot($0) }
    }

    private var runChecksOperation: @Sendable () async -> SetupReport {
        let checker = checker
        return { await checker.run() }
    }

    // MARK: - Feature factories

    func makeDeviceListModel() -> DeviceListModel {
        DeviceListModel(repository: repository)
    }

    func makeWorkspaceModel(for id: DeviceID, setCompact: @escaping (Bool) -> Void) -> DeviceWorkspaceModel {
        let preferences = preferences
        return DeviceWorkspaceModel(
            deviceID: id,
            dependencies: DeviceWorkspaceDependencies(
                repository: repository,
                installs: installs,
                packageForSysdir: packageForSysdirOperation,
                captureFolder: { CaptureFolder.url(preferences: preferences) },
                reveal: { NSWorkspace.shared.activateFileViewerSelecting([$0]) },
                setCompact: setCompact,
                recordingQuality: {
                    preferences.string(forKey: PreferenceKey.recordingQuality)
                        .flatMap(RecordingQuality.init(rawValue:)) ?? .standard
                }
            )
        )
    }

    func makeSettingsModel(for id: DeviceID) -> DeviceSettingsModel {
        DeviceSettingsModel(deviceID: id, dependencies: DeviceSettingsDependencies(repository: repository))
    }

    func makeDeviceInfoModel(for id: DeviceID) -> DeviceInfoModel {
        DeviceInfoModel(deviceID: id, dependencies: DeviceInfoDependencies(repository: repository))
    }

    func makeFilesModel(for id: DeviceID) -> FilesModel {
        FilesModel(
            deviceID: id,
            dependencies: FilesDependencies(
                repository: repository,
                reveal: { NSWorkspace.shared.activateFileViewerSelecting([$0]) }
            )
        )
    }

    func makeReportsModel(for id: DeviceID, openLogcat: @escaping @MainActor (DeviceID) -> Void) -> ReportsModel {
        let preferences = preferences
        return ReportsModel(
            deviceID: id,
            dependencies: ReportsDependencies(
                repository: repository,
                outputFolder: { CaptureFolder.url(preferences: preferences) },
                reveal: { NSWorkspace.shared.activateFileViewerSelecting([$0]) },
                openLogcat: openLogcat
            )
        )
    }

    func makeLogcatModel(for id: DeviceID) -> LogcatModel {
        LogcatModel(deviceID: id, repository: repository)
    }

    func makeAddEmulatorModel(onFinished: @escaping (DeviceID) -> Void) -> AddEmulatorModel {
        let skins = context.location?.skinsDirectory
        let fileSystem = fileSystem
        let bootMode = preferences.string(forKey: PreferenceKey.defaultBootMode).flatMap(BootMode.init(rawValue:))
        return AddEmulatorModel(
            dependencies: AddEmulatorDependencies(
                profiles: profiles,
                systemImages: systemImagesOperation,
                skinFolder: { name in
                    guard let folder = skins?.appending(path: name, directoryHint: .isDirectory),
                        fileSystem.directoryExists(at: folder)
                    else { return nil }
                    return folder
                },
                repository: repository,
                installs: installs,
                defaultBootMode: bootMode ?? .quick
            ),
            onFinished: onFinished
        )
    }

    func makeOnboardingModel(
        startAt step: OnboardingModel.Step,
        complete: @escaping (OnboardingDependencies.Completion) -> Void
    ) -> OnboardingModel {
        let fileSystem = fileSystem
        return OnboardingModel(
            dependencies: OnboardingDependencies(
                context: context,
                runChecks: runChecksOperation,
                setSDKRoot: setSDKRootOperation,
                createFolder: { try fileSystem.createDirectory(at: $0) },
                remotePackages: remotePackagesOperation,
                packageForSysdir: packageForSysdirOperation,
                installs: installs,
                repository: repository,
                complete: complete
            ),
            startAt: step
        )
    }

    func makeComponentsModel() -> ComponentsModel {
        let inventory = inventory
        let fileSystem = fileSystem
        return ComponentsModel(
            dependencies: ComponentsDependencies(
                context: context,
                runChecks: runChecksOperation,
                setSDKRoot: setSDKRootOperation,
                remotePackages: remotePackagesOperation,
                installedPackages: { await inventory.installedPackages(in: $0) },
                directorySize: { fileSystem.allocatedSize(ofDirectory: $0) },
                reveal: { NSWorkspace.shared.activateFileViewerSelecting([$0]) },
                installs: installs,
                repository: repository
            )
        )
    }
}
