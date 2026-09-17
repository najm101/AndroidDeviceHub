public import Foundation
public import Observation

// MARK: - Infrastructure protocols (implemented in Layer 2)

public protocol SDKLocating: Sendable {
    /// Resolves the SDK and AVD folders (user selection → environment → Android Studio → default).
    func resolve() async -> SDKLocationResolution
    /// Stores or clears the user's SDK folder choice.
    func setUserSDKRoot(_ url: URL?) async
}

public protocol SDKCatalogProviding: Sendable {
    /// Every package Google offers for this Mac (host OS and architecture already filtered).
    func remotePackages(forceRefresh: Bool) async throws -> [RemotePackage]
}

public protocol SDKInventoryProviding: Sendable {
    /// Packages installed in the SDK folder, read from their `package.xml`.
    func installedPackages(in location: SDKLocation) async -> [LocalPackage]
}

public protocol SDKInstalling: Sendable {
    func isLicenseAccepted(_ license: License, in location: SDKLocation) async -> Bool
    func acceptLicense(_ license: License, in location: SDKLocation) async throws
    func install(
        _ package: RemotePackage,
        in location: SDKLocation,
        progress: @escaping @Sendable (InstallProgress) -> Void
    ) async throws
    func uninstall(_ package: LocalPackage, in location: SDKLocation) async throws
}

public protocol SetupChecking: Sendable {
    func run() async -> SetupReport
}

public protocol AVDStoring: Sendable {
    func devices(in location: SDKLocation) async throws -> [VirtualDevice]
    func create(_ specification: VirtualDeviceSpecification, in location: SDKLocation) async throws -> VirtualDevice
    func rename(_ device: VirtualDevice, toDisplayName name: String, in location: SDKLocation) async throws
        -> VirtualDevice
    func duplicate(_ device: VirtualDevice, as displayName: String, in location: SDKLocation) async throws
        -> VirtualDevice
    func wipeData(of device: VirtualDevice) async throws
    func delete(_ device: VirtualDevice, in location: SDKLocation) async throws
    /// Emits whenever the AVD folder changes.
    func changes(in location: SDKLocation) -> AsyncStream<Void>
}

public protocol HardwareProfileProviding: Sendable {
    func profiles() -> [HardwareProfile]
}

// MARK: - Installs

public struct InstallProgress: Hashable, Sendable {
    public enum Phase: Hashable, Sendable {
        case preparing
        case downloading
        case verifying
        case extracting
        case finishing
    }

    public var phase: Phase
    public var receivedBytes: Int64
    public var totalBytes: Int64
    /// Bytes per second while downloading.
    public var bytesPerSecond: Double?

    public init(phase: Phase, receivedBytes: Int64 = 0, totalBytes: Int64 = 0, bytesPerSecond: Double? = nil) {
        self.phase = phase
        self.receivedBytes = receivedBytes
        self.totalBytes = totalBytes
        self.bytesPerSecond = bytesPerSecond
    }

    public var fractionCompleted: Double? {
        guard phase == .downloading, totalBytes > 0 else { return nil }
        return min(1, Double(receivedBytes) / Double(totalBytes))
    }

    public var title: String {
        switch phase {
        case .preparing:
            return "Preparing…"
        case .downloading:
            let received = receivedBytes.formatted(.byteCount(style: .file))
            let total = totalBytes.formatted(.byteCount(style: .file))
            if let bytesPerSecond, bytesPerSecond > 0 {
                let speed = Int64(bytesPerSecond).formatted(.byteCount(style: .file))
                return "\(received) of \(total) · \(speed)/s"
            }
            return "\(received) of \(total)"
        case .verifying:
            return "Verifying…"
        case .extracting:
            return "Extracting…"
        case .finishing:
            return "Finishing…"
        }
    }
}

/// App-wide download queue shared by onboarding, Components and the New Emulator dialog.
@MainActor
public protocol InstallCoordinating: AnyObject {
    /// In-flight installs keyed by package path.
    var activeInstalls: [String: InstallProgress] { get }
    /// Failure messages keyed by package path, cleared when retried.
    var failures: [String: String] { get }
    /// Increments after every successful install or uninstall, so views can reload.
    var inventoryRevision: Int { get }

    /// The license the user still has to accept before `package` can be installed.
    func pendingLicense(for package: RemotePackage) async -> License?
    func acceptLicense(_ license: License) async throws
    /// Starts an install. The license must already be accepted.
    func install(_ package: RemotePackage)
    func cancelInstall(of packagePath: String)
    func uninstall(_ package: LocalPackage) async throws
}

// MARK: - Shared state

/// The SDK location and last setup report, shared by every feature.
@MainActor
@Observable
public final class SDKContext {
    public var report: SetupReport?

    public init(report: SetupReport? = nil) {
        self.report = report
    }

    public var location: SDKLocation? { report?.location }
    public var hasPlatformTools: Bool { report?.hasPlatformTools ?? false }
}
