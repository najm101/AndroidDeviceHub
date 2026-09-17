import Foundation
public import Foundations
public import SDKDomain

/// Runs the first-run checks.
public struct SetupChecker: SetupChecking {
    /// The oldest emulator current system images declare as a dependency.
    public static let minimumEmulator = PackageRevision(major: 35, minor: 4, micro: 9)
    /// Below this, a warning suggests freeing space (a single image needs about 2–5 GB during install).
    public static let lowDiskSpace: Int64 = 20 * .gibibyte

    private let locator: any SDKLocating
    private let inventory: any SDKInventoryProviding
    private let fileSystem: any FileSystem
    private let hypervisorAvailable: @Sendable () -> Bool

    public init(
        locator: any SDKLocating,
        inventory: any SDKInventoryProviding,
        fileSystem: any FileSystem = LiveFileSystem(),
        hypervisorAvailable: @escaping @Sendable () -> Bool = Hypervisor.isAvailable
    ) {
        self.locator = locator
        self.inventory = inventory
        self.fileSystem = fileSystem
        self.hypervisorAvailable = hypervisorAvailable
    }

    public func run() async -> SetupReport {
        let resolution = await locator.resolve()
        let location = resolution.location
        let sdkExists: Bool
        if case .found = resolution { sdkExists = true } else { sdkExists = false }
        let packages = sdkExists ? await inventory.installedPackages(in: location) : []

        var checks = [
            sdkFolderCheck(location, exists: sdkExists),
            writableCheck(location, exists: sdkExists),
            emulatorCheck(packages.package(at: SDKPackagePath.emulator)),
            avdFolderCheck(location),
            hypervisorCheck(),
        ]
        if let disk = diskSpaceCheck(location, exists: sdkExists) {
            checks.append(disk)
        }
        checks.append(platformToolsCheck(packages.package(at: SDKPackagePath.platformTools), location: location))
        return SetupReport(resolution: resolution, checks: checks)
    }

    // MARK: - Checks

    private func sdkFolderCheck(_ location: SDKLocation, exists: Bool) -> SetupCheck {
        let path = location.sdkRoot.path(percentEncoded: false)
        return SetupCheck(
            id: .sdkFolder, title: "Android SDK", level: .required,
            status: exists
                ? .satisfied(detail: path)
                : .missing(detail: "No SDK found. It can be created at \(path)")
        )
    }

    private func writableCheck(_ location: SDKLocation, exists: Bool) -> SetupCheck {
        let status: SetupCheck.Status
        if !exists {
            status = .missing(detail: "Create the SDK folder first")
        } else if fileSystem.isWritableDirectory(at: location.sdkRoot) {
            status = .satisfied(detail: "Writable")
        } else {
            status = .failed(detail: "Android Device App can't write to this folder")
        }
        return SetupCheck(id: .sdkWritable, title: "SDK folder access", level: .required, status: status)
    }

    private func emulatorCheck(_ package: LocalPackage?) -> SetupCheck {
        let status: SetupCheck.Status
        if let package {
            status =
                package.revision >= Self.minimumEmulator
                ? .satisfied(detail: "Version \(package.revision)")
                : .needsUpdate(installed: package.revision, minimum: Self.minimumEmulator)
        } else {
            status = .missing(detail: "Not installed")
        }
        return SetupCheck(
            id: .emulator, title: "Android Emulator", level: .required, status: status,
            installablePackagePath: SDKPackagePath.emulator, installedRevision: package?.revision
        )
    }

    private func avdFolderCheck(_ location: SDKLocation) -> SetupCheck {
        let url = location.avdHome
        if !fileSystem.directoryExists(at: url) {
            try? fileSystem.createDirectory(at: url)
        }
        let status: SetupCheck.Status =
            fileSystem.isWritableDirectory(at: url)
            ? .satisfied(detail: url.path(percentEncoded: false))
            : .failed(detail: "Can't create or write \(url.path(percentEncoded: false))")
        return SetupCheck(id: .avdFolder, title: "Devices folder", level: .required, status: status)
    }

    private func hypervisorCheck() -> SetupCheck {
        #if arch(arm64)
            let detail = "Apple Silicon"
        #else
            let detail = "Intel (Hypervisor.framework)"
        #endif
        return SetupCheck(
            id: .hypervisor, title: "Virtualization", level: .required,
            status: hypervisorAvailable()
                ? .satisfied(detail: detail)
                : .failed(detail: "This Mac doesn't support hardware virtualization")
        )
    }

    private func diskSpaceCheck(_ location: SDKLocation, exists: Bool) -> SetupCheck? {
        let probe = exists ? location.sdkRoot : location.sdkRoot.deletingLastPathComponent()
        guard let available = fileSystem.availableCapacity(at: probe) else { return nil }
        let volume = (try? probe.resourceValues(forKeys: [.volumeNameKey]))?.volumeName.map { " on “\($0)”" } ?? ""
        let detail = "\(available.formattedFileSize) free\(volume)"
        return SetupCheck(
            id: .diskSpace, title: "Disk space", level: .warning,
            status: available < Self.lowDiskSpace ? .warning(detail: detail) : .satisfied(detail: detail)
        )
    }

    private func platformToolsCheck(_ package: LocalPackage?, location: SDKLocation) -> SetupCheck {
        let hasExecutable = fileSystem.fileExists(at: location.adbExecutable)
        let status: SetupCheck.Status =
            if let package, hasExecutable {
                .satisfied(detail: "Version \(package.revision)")
            } else {
                .missing(detail: "Not installed")
            }
        return SetupCheck(
            id: .platformTools, title: "Platform Tools (ADB)", level: .optional, status: status,
            installablePackagePath: SDKPackagePath.platformTools, installedRevision: package?.revision
        )
    }
}

public enum Hypervisor {
    @Sendable public static func isAvailable() -> Bool {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("kern.hv_support", &value, &size, nil, 0) == 0 else { return false }
        return value == 1
    }
}
