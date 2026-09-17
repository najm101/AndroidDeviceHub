import Foundation

/// The result of the first-run checks.
public struct SetupReport: Hashable, Sendable {
    public var resolution: SDKLocationResolution
    public var checks: [SetupCheck]

    public init(resolution: SDKLocationResolution, checks: [SetupCheck]) {
        self.resolution = resolution
        self.checks = checks
    }

    public var location: SDKLocation { resolution.location }

    public func check(_ id: SetupCheck.ID) -> SetupCheck? {
        checks.first { $0.id == id }
    }

    /// `true` when every required check passed.
    public var isReady: Bool {
        checks.allSatisfy { $0.level != .required || $0.status.isSatisfied }
    }

    public var hasPlatformTools: Bool {
        check(.platformTools)?.status.isSatisfied == true
    }
}

public struct SetupCheck: Hashable, Sendable, Identifiable {
    public enum ID: String, Hashable, Sendable, CaseIterable {
        case sdkFolder
        case sdkWritable
        case emulator
        case avdFolder
        case hypervisor
        case diskSpace
        case platformTools
    }

    public enum Level: Hashable, Sendable {
        case required
        case warning
        case optional
    }

    public enum Status: Hashable, Sendable {
        case satisfied(detail: String)
        case needsUpdate(installed: PackageRevision, minimum: PackageRevision)
        case missing(detail: String)
        case failed(detail: String)
        case warning(detail: String)

        public var isSatisfied: Bool {
            switch self {
            case .satisfied, .warning: true
            case .needsUpdate, .missing, .failed: false
            }
        }

        public var detail: String {
            switch self {
            case let .satisfied(detail), let .missing(detail), let .failed(detail), let .warning(detail): detail
            case let .needsUpdate(installed, minimum): "Version \(installed) is older than the required \(minimum)"
            }
        }
    }

    public var id: ID
    public var title: String
    public var level: Level
    public var status: Status
    /// The package that fixes this check, when it can be installed.
    public var installablePackagePath: String?
    /// The installed version of that package, if any.
    public var installedRevision: PackageRevision?

    public init(
        id: ID,
        title: String,
        level: Level,
        status: Status,
        installablePackagePath: String? = nil,
        installedRevision: PackageRevision? = nil
    ) {
        self.id = id
        self.title = title
        self.level = level
        self.status = status
        self.installablePackagePath = installablePackagePath
        self.installedRevision = installedRevision
    }
}
