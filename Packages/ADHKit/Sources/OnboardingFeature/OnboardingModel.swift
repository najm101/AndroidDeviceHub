public import DeviceDomain
public import Foundation
public import Observation
public import SDKDomain

/// Dependencies of the setup wizard, wired by the app.
@MainActor
public struct OnboardingDependencies {
    public struct Completion: Sendable {
        public var skippedPlatformTools: Bool
        public var openNewEmulator: Bool
    }

    public var context: SDKContext
    public var runChecks: @Sendable () async -> SetupReport
    public var setSDKRoot: @Sendable (URL?) async -> Void
    public var createFolder: @Sendable (URL) throws -> Void
    public var remotePackages: @Sendable (_ forceRefresh: Bool) async throws -> [RemotePackage]
    public var packageForSysdir: @Sendable (String) async -> RemotePackage?
    public var installs: any InstallCoordinating
    public var repository: any DeviceRepository
    public var complete: (Completion) -> Void

    public init(
        context: SDKContext,
        runChecks: @escaping @Sendable () async -> SetupReport,
        setSDKRoot: @escaping @Sendable (URL?) async -> Void,
        createFolder: @escaping @Sendable (URL) throws -> Void,
        remotePackages: @escaping @Sendable (Bool) async throws -> [RemotePackage],
        packageForSysdir: @escaping @Sendable (String) async -> RemotePackage?,
        installs: any InstallCoordinating,
        repository: any DeviceRepository,
        complete: @escaping (Completion) -> Void
    ) {
        self.context = context
        self.runChecks = runChecks
        self.setSDKRoot = setSDKRoot
        self.createFolder = createFolder
        self.remotePackages = remotePackages
        self.packageForSysdir = packageForSysdir
        self.installs = installs
        self.repository = repository
        self.complete = complete
    }
}

/// The three-step first-run wizard.
@MainActor
@Observable
public final class OnboardingModel {
    public enum Step: Int, CaseIterable, Sendable {
        case sdk
        case platformTools
        case ready

        var title: String {
            switch self {
            case .sdk: "Android SDK"
            case .platformTools: "Physical devices (optional)"
            case .ready: "You're ready"
            }
        }
    }

    struct MissingImage: Identifiable, Equatable {
        var sysdir: String
        var deviceNames: [String]
        var package: RemotePackage?

        var id: String { sysdir }
    }

    private(set) var step: Step
    private(set) var isChecking = false
    private(set) var catalog: [RemotePackage] = []
    private(set) var catalogError: String?
    private(set) var missingImages: [MissingImage] = []
    var errorMessage: String?

    let dependencies: OnboardingDependencies
    @ObservationIgnored private var skippedPlatformTools = false

    /// - Parameter startAt: the step to open, e.g. `.sdk` when a required check failed on launch.
    public init(dependencies: OnboardingDependencies, startAt step: Step = .sdk) {
        self.dependencies = dependencies
        self.step = step
    }

    var report: SetupReport? { dependencies.context.report }
    var installs: any InstallCoordinating { dependencies.installs }

    func check(_ id: SetupCheck.ID) -> SetupCheck? {
        report?.check(id)
    }

    var sdkChecks: [SetupCheck] {
        (report?.checks ?? []).filter { $0.id != .platformTools }
    }

    var sdkIsMissing: Bool {
        if case .notFound = report?.resolution { return true }
        return false
    }

    var canContinue: Bool {
        switch step {
        case .sdk: report?.isReady == true && !isChecking
        case .platformTools, .ready: true
        }
    }

    // MARK: - Loading

    func start() async {
        await runChecks()
        await loadCatalog(forceRefresh: false)
    }

    func runChecks() async {
        isChecking = true
        defer { isChecking = false }
        dependencies.context.report = await dependencies.runChecks()
    }

    func loadCatalog(forceRefresh: Bool) async {
        do {
            catalog = try await dependencies.remotePackages(forceRefresh)
            catalogError = nil
        } catch {
            catalogError = error.localizedDescription
        }
    }

    func inventoryChanged() async {
        await runChecks()
        if step == .ready {
            await loadMissingImages()
        }
    }

    /// The newest stable package that can fix a check.
    func package(for check: SetupCheck) -> RemotePackage? {
        check.installablePackagePath.flatMap { catalog.latest(path: $0) }
    }

    // MARK: - SDK folder

    func chooseSDKFolder(_ url: URL) async {
        await dependencies.setSDKRoot(url)
        await runChecks()
    }

    func createSuggestedSDKFolder() async {
        guard let location = report?.location else { return }
        do {
            try dependencies.createFolder(location.sdkRoot)
            await dependencies.setSDKRoot(location.sdkRoot)
            await runChecks()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Navigation

    func goForward() async {
        switch step {
        case .sdk:
            guard canContinue else { return }
            step = report?.hasPlatformTools == true ? .ready : .platformTools
        case .platformTools:
            step = .ready
        case .ready:
            return
        }
        if step == .ready {
            await loadMissingImages()
        }
    }

    func goBack() {
        switch step {
        case .sdk: return
        case .platformTools: step = .sdk
        case .ready: step = report?.hasPlatformTools == true ? .sdk : .platformTools
        }
    }

    func skipPlatformTools() async {
        skippedPlatformTools = true
        await goForward()
    }

    func finish(openNewEmulator: Bool) {
        dependencies.complete(
            .init(
                skippedPlatformTools: skippedPlatformTools && report?.hasPlatformTools != true,
                openNewEmulator: openNewEmulator
            ))
    }

    // MARK: - Existing devices

    var deviceCount: Int { dependencies.repository.devices.count }

    private func loadMissingImages() async {
        await dependencies.repository.reload()
        var grouped: [String: [String]] = [:]
        for device in dependencies.repository.devices {
            if case let .needsAttention(.missingSystemImage(sysdir)) = device.state {
                grouped[sysdir, default: []].append(device.name)
            }
        }
        var result: [MissingImage] = []
        for (sysdir, names) in grouped.sorted(by: { $0.key < $1.key }) {
            let package = await dependencies.packageForSysdir(sysdir)
            result.append(MissingImage(sysdir: sysdir, deviceNames: names.sorted(), package: package))
        }
        missingImages = result
    }
}
