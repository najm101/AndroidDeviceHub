import Foundation
public import Foundations
public import SDKDomain

/// Reads installed packages from the SDK folder.
public struct LocalSDKInventory: SDKInventoryProviding {
    private let fileSystem: any FileSystem

    public init(fileSystem: any FileSystem = LiveFileSystem()) {
        self.fileSystem = fileSystem
    }

    public func installedPackages(in location: SDKLocation) async -> [LocalPackage] {
        var directories = [location.emulatorDirectory, location.platformToolsDirectory]
        directories += systemImageDirectories(in: location.sdkRoot)
        return directories.compactMap(package(in:))
    }

    func package(in directory: URL) -> LocalPackage? {
        let packageXML = directory.appending(path: "package.xml", directoryHint: .notDirectory)
        if let data = try? fileSystem.contents(of: packageXML),
            let package = PackageXMLParser.localPackage(fromXML: data, directory: directory)
        {
            return package
        }
        let properties = directory.appending(path: "source.properties", directoryHint: .notDirectory)
        if let text = try? fileSystem.string(contentsOf: properties) {
            return SourceProperties.package(from: text, directory: directory)
        }
        return nil
    }

    /// `system-images/<platform>/<tag>/<abi>`
    private func systemImageDirectories(in sdkRoot: URL) -> [URL] {
        let root = sdkRoot.appending(path: "system-images", directoryHint: .isDirectory)
        return subdirectories(of: root)
            .flatMap(subdirectories(of:))
            .flatMap(subdirectories(of:))
    }

    private func subdirectories(of url: URL) -> [URL] {
        ((try? fileSystem.contentsOfDirectory(at: url)) ?? []).filter { fileSystem.directoryExists(at: $0) }
    }
}

/// Fallback for packages installed by very old tools that only wrote `source.properties`.
enum SourceProperties {
    static func package(from text: String, directory: URL) -> LocalPackage? {
        var values: [String: String] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count == 2 { values[parts[0]] = parts[1] }
        }
        guard let revision = values["Pkg.Revision"].flatMap(PackageRevision.init(string:)) else { return nil }

        let components = directory.pathComponents.suffix(4)
        if components.first == "system-images", components.count == 4,
            let api = values["AndroidVersion.ApiLevel"].flatMap(APILevel.init(catalogValue:))
        {
            let parts = Array(components)
            let tagID = values["SystemImage.TagId"] ?? parts[2]
            let details = SystemImageDetails(
                apiLevel: api,
                extensionLevel: nil,
                isBaseExtension: true,
                stage: values["AndroidVersion.CodeName"].map { .preview(codename: $0) } ?? .stable,
                tags: [ImageTag(id: tagID, display: values["SystemImage.TagDisplay"] ?? tagID)],
                vendor: nil,
                abi: ABI(rawValue: values["SystemImage.Abi"] ?? parts[3]),
                platformFolder: parts[1],
                tagFolder: parts[2]
            )
            let path = parts.joined(separator: ";")
            return LocalPackage(
                path: path, displayName: values["Pkg.Desc"] ?? path, revision: revision,
                kind: .systemImage(details), directory: directory
            )
        }

        let name = directory.lastPathComponent
        let kind: PackageKind =
            switch name {
            case SDKPackagePath.emulator: .emulator
            case SDKPackagePath.platformTools: .platformTools
            default: .other
            }
        return LocalPackage(
            path: name, displayName: values["Pkg.Desc"] ?? name, revision: revision, kind: kind, directory: directory
        )
    }
}
