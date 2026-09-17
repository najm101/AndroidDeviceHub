public import Foundation

/// A license a package requires before it can be installed.
public struct License: Hashable, Sendable, Identifiable {
    public var id: String
    public var text: String

    public init(id: String, text: String) {
        self.id = id
        self.text = text
    }
}

/// What kind of SDK package this is.
public enum PackageKind: Hashable, Sendable {
    case systemImage(SystemImageDetails)
    case emulator
    case platformTools
    case other
}

/// Details of a `system-images;…` package.
public struct SystemImageDetails: Hashable, Sendable {
    public var apiLevel: APILevel
    public var extensionLevel: Int?
    public var isBaseExtension: Bool
    public var stage: ReleaseStage
    /// All tags (the first is the primary one).
    public var tags: [ImageTag]
    public var vendor: ImageTag?
    public var abi: ABI
    /// The platform folder, e.g. `android-36` or `android-36-ext19`.
    public var platformFolder: String
    /// The tag folder, e.g. `google_apis_playstore_ps16k`.
    public var tagFolder: String

    public init(
        apiLevel: APILevel,
        extensionLevel: Int?,
        isBaseExtension: Bool,
        stage: ReleaseStage,
        tags: [ImageTag],
        vendor: ImageTag?,
        abi: ABI,
        platformFolder: String,
        tagFolder: String
    ) {
        self.apiLevel = apiLevel
        self.extensionLevel = extensionLevel
        self.isBaseExtension = isBaseExtension
        self.stage = stage
        self.tags = tags
        self.vendor = vendor
        self.abi = abi
        self.platformFolder = platformFolder
        self.tagFolder = tagFolder
    }

    public var primaryTag: ImageTag { tags.first ?? ImageTag(id: tagFolder, display: tagFolder) }
    public var services: ImageServices { ImageServices(tagID: tagFolder) }
    public var hasPlayStore: Bool { services == .googlePlay }
    public var usesSixteenKBPages: Bool {
        tagFolder.hasSuffix("_ps16k") || tags.contains { $0.id == "page_size_16kb" }
    }

    /// The package path relative to the SDK root, e.g. `system-images/android-36/google_apis_playstore/arm64-v8a/`.
    public var sysdir: String {
        "system-images/\(platformFolder)/\(tagFolder)/\(abi.rawValue)/"
    }

    /// The form factor this image is built for, derived from its tags.
    public var formFactor: FormFactor? {
        for tag in tags.map(\.id) + [tagFolder] {
            if let factor = FormFactor(imageTagID: tag) { return factor }
        }
        return nil
    }
}

public struct PackageArchive: Hashable, Sendable {
    public var url: URL
    public var size: Int64
    public var sha1: String

    public init(url: URL, size: Int64, sha1: String) {
        self.url = url
        self.size = size
        self.sha1 = sha1
    }
}

public struct PackageDependency: Hashable, Sendable {
    public var path: String
    public var minimumRevision: PackageRevision?

    public init(path: String, minimumRevision: PackageRevision?) {
        self.path = path
        self.minimumRevision = minimumRevision
    }
}

/// A package offered by Google's SDK repository.
public struct RemotePackage: Hashable, Sendable, Identifiable {
    /// The `;`-separated SDK path, e.g. `system-images;android-36;google_apis_playstore;arm64-v8a`.
    public var path: String
    public var displayName: String
    public var revision: PackageRevision
    public var channel: ReleaseChannel
    public var kind: PackageKind
    public var license: License?
    public var archive: PackageArchive
    public var dependencies: [PackageDependency]
    /// The inner XML of `<remotePackage>` (without `<archives>`/`<channelRef>`), used verbatim in `package.xml`.
    public var localPackageXML: String
    /// The XML namespace prefix declarations `localPackageXML` needs.
    public var namespaceDeclarations: [String: String]

    public var id: String { path }

    public init(
        path: String,
        displayName: String,
        revision: PackageRevision,
        channel: ReleaseChannel,
        kind: PackageKind,
        license: License?,
        archive: PackageArchive,
        dependencies: [PackageDependency],
        localPackageXML: String,
        namespaceDeclarations: [String: String]
    ) {
        self.path = path
        self.displayName = displayName
        self.revision = revision
        self.channel = channel
        self.kind = kind
        self.license = license
        self.archive = archive
        self.dependencies = dependencies
        self.localPackageXML = localPackageXML
        self.namespaceDeclarations = namespaceDeclarations
    }

    /// The install folder relative to the SDK root.
    public var relativeInstallPath: String {
        path.replacingOccurrences(of: ";", with: "/")
    }

    public var systemImage: SystemImageDetails? {
        if case let .systemImage(details) = kind { return details }
        return nil
    }
}

/// A package installed in the SDK folder.
public struct LocalPackage: Hashable, Sendable, Identifiable {
    public var path: String
    public var displayName: String
    public var revision: PackageRevision
    public var kind: PackageKind
    public var directory: URL

    public var id: String { path }

    public init(path: String, displayName: String, revision: PackageRevision, kind: PackageKind, directory: URL) {
        self.path = path
        self.displayName = displayName
        self.revision = revision
        self.kind = kind
        self.directory = directory
    }

    public var systemImage: SystemImageDetails? {
        if case let .systemImage(details) = kind { return details }
        return nil
    }
}

/// Well-known package paths.
public enum SDKPackagePath {
    public static let emulator = "emulator"
    public static let platformTools = "platform-tools"
}
