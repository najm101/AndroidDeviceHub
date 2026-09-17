import Foundation

/// A system image as the UI sees it: what the catalog offers merged with what is installed.
public struct SystemImageEntry: Hashable, Sendable, Identifiable {
    public var path: String
    public var displayName: String
    public var details: SystemImageDetails
    public var remote: RemotePackage?
    public var installed: LocalPackage?

    public var id: String { path }

    public init(
        path: String,
        displayName: String,
        details: SystemImageDetails,
        remote: RemotePackage?,
        installed: LocalPackage?
    ) {
        self.path = path
        self.displayName = displayName
        self.details = details
        self.remote = remote
        self.installed = installed
    }

    public var isInstalled: Bool { installed != nil }
    public var downloadSize: Int64? { remote?.archive.size }
    public var hasUpdate: Bool {
        guard let installed, let remote else { return false }
        return remote.revision > installed.revision
    }

    /// Merges catalog and installed packages into one list, newest API first.
    public static func merge(remote: [RemotePackage], installed: [LocalPackage]) -> [SystemImageEntry] {
        var entries: [String: SystemImageEntry] = [:]
        for package in remote {
            guard let details = package.systemImage else { continue }
            if let existing = entries[package.path], let current = existing.remote, current.revision >= package.revision
            {
                continue
            }
            entries[package.path] = SystemImageEntry(
                path: package.path, displayName: package.displayName, details: details,
                remote: package, installed: nil
            )
        }
        for package in installed {
            guard let details = package.systemImage else { continue }
            if var entry = entries[package.path] {
                entry.installed = package
                entries[package.path] = entry
            } else {
                entries[package.path] = SystemImageEntry(
                    path: package.path, displayName: package.displayName, details: details,
                    remote: nil, installed: package
                )
            }
        }
        return entries.values.sorted { lhs, rhs in
            if lhs.details.apiLevel != rhs.details.apiLevel { return lhs.details.apiLevel > rhs.details.apiLevel }
            if lhs.details.stage.isPrerelease != rhs.details.stage.isPrerelease {
                return !lhs.details.stage.isPrerelease
            }
            return lhs.path < rhs.path
        }
    }
}
