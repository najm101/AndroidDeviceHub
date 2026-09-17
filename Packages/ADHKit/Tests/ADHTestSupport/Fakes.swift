public import DeviceDomain
public import Foundation
public import Observation
public import SDKDomain

/// An in-memory `DeviceRepository` that records the actions it receives.
@MainActor
@Observable
public final class FakeDeviceRepository: DeviceRepository {
    public var devices: [Device]
    public var isLoading = false
    public var lastError: String?
    public var error: (any Error)?

    public private(set) var started: [(DeviceID, StartOption)] = []
    public private(set) var created: [VirtualDeviceSpecification] = []
    public private(set) var renamed: [(DeviceID, String)] = []
    public private(set) var wiped: [DeviceID] = []
    public private(set) var removed: [DeviceID] = []
    public private(set) var revealed: [DeviceID] = []
    public private(set) var reloadCount = 0

    public init(devices: [Device] = []) {
        self.devices = devices
    }

    public func device(withID id: DeviceID) -> Device? {
        devices.first { $0.id == id }
    }

    public var sessions: [DeviceID: any DeviceSession] = [:]
    public private(set) var shutDownIDs: [DeviceID] = []
    public private(set) var restartedIDs: [DeviceID] = []

    public func session(for id: DeviceID) -> (any DeviceSession)? {
        sessions[id]
    }

    public var inspectors: [DeviceID: any DeviceInspecting] = [:]

    public func inspector(for id: DeviceID) -> (any DeviceInspecting)? {
        inspectors[id]
    }

    public func reload() async {
        reloadCount += 1
    }

    public func shutDown(_ id: DeviceID) async throws {
        try throwIfNeeded()
        shutDownIDs.append(id)
    }

    public func restart(_ id: DeviceID) async throws {
        try throwIfNeeded()
        restartedIDs.append(id)
    }

    public func start(_ id: DeviceID, option: StartOption) async throws {
        try throwIfNeeded()
        started.append((id, option))
    }

    public func create(_ specification: VirtualDeviceSpecification) async throws -> DeviceID {
        try throwIfNeeded()
        created.append(specification)
        let id = DeviceID.emulator(avdID: specification.id)
        devices.append(.emulator(id: specification.id, name: specification.displayName))
        return id
    }

    public func rename(_ id: DeviceID, to name: String) async throws {
        try throwIfNeeded()
        renamed.append((id, name))
    }

    public func duplicate(_ id: DeviceID, as name: String) async throws -> DeviceID {
        try throwIfNeeded()
        return .emulator(avdID: VirtualDeviceName.id(fromDisplayName: name))
    }

    public func wipeData(_ id: DeviceID) async throws {
        try throwIfNeeded()
        wiped.append(id)
    }

    public func remove(_ id: DeviceID) async throws {
        try throwIfNeeded()
        removed.append(id)
    }

    public func revealInFinder(_ id: DeviceID) {
        revealed.append(id)
    }

    private func throwIfNeeded() throws {
        if let error { throw error }
    }
}

/// An `InstallCoordinating` that completes installs on demand.
@MainActor
@Observable
public final class FakeInstallCoordinator: InstallCoordinating {
    public var activeInstalls: [String: InstallProgress] = [:]
    public var failures: [String: String] = [:]
    public var inventoryRevision = 0
    public var licensesToAccept: Set<String> = []

    public private(set) var installed: [String] = []
    public private(set) var accepted: [String] = []
    public private(set) var uninstalled: [String] = []

    public init() {}

    public func pendingLicense(for package: RemotePackage) async -> License? {
        guard let license = package.license, licensesToAccept.contains(license.id) else { return nil }
        return license
    }

    public func acceptLicense(_ license: License) async throws {
        licensesToAccept.remove(license.id)
        accepted.append(license.id)
    }

    public func install(_ package: RemotePackage) {
        installed.append(package.path)
        activeInstalls[package.path] = InstallProgress(phase: .downloading, totalBytes: package.archive.size)
    }

    public func finishInstall(of path: String) {
        activeInstalls[path] = nil
        inventoryRevision += 1
    }

    public func cancelInstall(of packagePath: String) {
        activeInstalls[packagePath] = nil
    }

    public func uninstall(_ package: LocalPackage) async throws {
        uninstalled.append(package.path)
        inventoryRevision += 1
    }
}

// MARK: - Sample data

public enum SampleData {
    public static let pixel8 = HardwareProfile(
        id: "pixel_8", name: "Pixel 8", manufacturer: "Google", formFactor: .phone, playStore: true,
        diagonalInches: 6.17, widthPixels: 1080, heightPixels: 2400, density: 420, ramMiB: 7562, skin: "pixel_8"
    )

    public static let smallPhone = HardwareProfile(
        id: "small_phone", name: "Small Phone", manufacturer: "Generic", formFactor: .phone, playStore: false,
        diagonalInches: 4.65, widthPixels: 720, heightPixels: 1280, density: 320, ramMiB: 2048
    )

    public static let wearRound = HardwareProfile(
        id: "wearos_large_round", name: "Wear OS Large Round", manufacturer: "Google", formFactor: .wear,
        tagID: "android-wear", playStore: true, diagonalInches: 1.39, widthPixels: 454, heightPixels: 454,
        density: 320, isRound: true, ramMiB: 2048, source: "wear"
    )

    public static func image(
        api: Int,
        tag: String = "google_apis_playstore",
        display: String = "Google Play",
        stage: ReleaseStage = .stable,
        extensionLevel: Int? = nil,
        isBase: Bool = true
    ) -> SystemImageDetails {
        var platform = isBase ? "android-\(api)" : "android-\(api)-ext\(extensionLevel ?? 0)"
        if let label = stage.label {
            platform += "-\(label.lowercased().replacingOccurrences(of: " ", with: ""))"
        }
        return SystemImageDetails(
            apiLevel: APILevel(major: api), extensionLevel: extensionLevel, isBaseExtension: isBase, stage: stage,
            tags: [ImageTag(id: tag, display: display)], vendor: nil, abi: .arm64,
            platformFolder: platform, tagFolder: tag
        )
    }

    public static func remotePackage(for details: SystemImageDetails, licenseID: String = "android-sdk-arm-dbt-license")
        -> RemotePackage
    {
        let path = "system-images;\(details.platformFolder);\(details.tagFolder);\(details.abi.rawValue)"
        return RemotePackage(
            path: path, displayName: "\(details.primaryTag.display) Image", revision: PackageRevision(major: 1),
            channel: .stable, kind: .systemImage(details), license: License(id: licenseID, text: "Terms"),
            archive: PackageArchive(
                url: URL(string: "https://example.com/\(details.platformFolder).zip")!, size: 1_000, sha1: "00"),
            dependencies: [], localPackageXML: "", namespaceDeclarations: [:]
        )
    }

    public static func entry(_ details: SystemImageDetails, installed: Bool) -> SystemImageEntry {
        let remote = remotePackage(for: details)
        let local =
            installed
            ? LocalPackage(
                path: remote.path, displayName: remote.displayName, revision: remote.revision,
                kind: remote.kind, directory: URL(filePath: "/sdk/\(remote.relativeInstallPath)"))
            : nil
        return SystemImageEntry(
            path: remote.path, displayName: remote.displayName, details: details,
            remote: remote, installed: local)
    }

    public static func location(root: URL = URL(filePath: "/sdk")) -> SDKLocation {
        SDKLocation(
            sdkRoot: root, sdkSource: .defaultLocation,
            avdHome: root.appending(path: "avd"), avdSource: .defaultLocation
        )
    }
}

public extension Device {
    static func emulator(
        id: String,
        name: String? = nil,
        state: DeviceState = .stopped,
        api: Int = 36,
        capabilities: [Capability: Availability] = [
            .start: .available, .rename: .available, .remove: .available, .wipeData: .available,
        ]
    ) -> Device {
        Device(
            id: .emulator(avdID: id), name: name ?? id, kind: .emulator, state: state,
            apiLevel: APILevel(major: api), formFactor: .phone,
            screenSize: PixelSize(width: 1080, height: 2400), hasPlayStore: true,
            capabilities: capabilities, virtualDevice: nil
        )
    }
}
