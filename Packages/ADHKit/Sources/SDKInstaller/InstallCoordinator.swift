import Foundation
import Foundations
public import Observation
public import SDKDomain
import os

/// The app-wide install queue (see `InstallCoordinating`).
@MainActor
@Observable
public final class InstallCoordinator: InstallCoordinating {
    public private(set) var activeInstalls: [String: InstallProgress] = [:]
    public private(set) var failures: [String: String] = [:]
    public private(set) var inventoryRevision = 0

    private let installer: any SDKInstalling
    private let context: SDKContext
    @ObservationIgnored private var tasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private let log = ADHLog.logger("InstallCoordinator")

    public init(installer: any SDKInstalling, context: SDKContext) {
        self.installer = installer
        self.context = context
    }

    public func pendingLicense(for package: RemotePackage) async -> License? {
        guard let license = package.license, let location = context.location else { return nil }
        return await installer.isLicenseAccepted(license, in: location) ? nil : license
    }

    public func acceptLicense(_ license: License) async throws {
        guard let location = context.location else { throw PackageInstallError.sdkNotWritable }
        try await installer.acceptLicense(license, in: location)
    }

    public func install(_ package: RemotePackage) {
        guard tasks[package.path] == nil, let location = context.location else { return }
        failures[package.path] = nil
        activeInstalls[package.path] = InstallProgress(phase: .preparing, totalBytes: package.archive.size)

        // The coordinator lives as long as the app, and the task ends with the install,
        // so capturing `self` strongly doesn't leak.
        let installer = installer
        let path = package.path
        tasks[path] = Task {
            do {
                try await installer.install(package, in: location) { progress in
                    Task { @MainActor in self.updateProgress(progress, for: path) }
                }
                finish(path, error: nil)
            } catch {
                finish(path, error: error)
            }
        }
    }

    private func updateProgress(_ progress: InstallProgress, for path: String) {
        // Ignore late updates that arrive after the install finished.
        guard activeInstalls[path] != nil else { return }
        activeInstalls[path] = progress
    }

    public func cancelInstall(of packagePath: String) {
        tasks[packagePath]?.cancel()
    }

    public func uninstall(_ package: LocalPackage) async throws {
        guard let location = context.location else { throw PackageInstallError.sdkNotWritable }
        try await installer.uninstall(package, in: location)
        inventoryRevision += 1
    }

    private func finish(_ path: String, error: (any Error)?) {
        tasks[path] = nil
        activeInstalls[path] = nil
        switch error {
        case nil:
            inventoryRevision += 1
        case is CancellationError:
            break
        case let urlError as URLError where urlError.code == .cancelled:
            break
        case let error?:
            log.error("Install of \(path, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            failures[path] = error.localizedDescription
        }
    }
}
