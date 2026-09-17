import Foundation
import SDKDomain

/// Parses `<remotePackage>` (catalog) and `<localPackage>` (`package.xml`) elements.
///
/// The Android repository schemas use unqualified child elements, so everything is matched by local name.
enum PackageXMLParser {
    struct Host: Sendable {
        var os: String
        var arch: String
        var abis: Set<String>

        static var current: Host {
            #if arch(arm64)
                Host(os: "macosx", arch: "aarch64", abis: ["arm64-v8a"])
            #else
                Host(os: "macosx", arch: "x64", abis: ["x86_64", "x86"])
            #endif
        }
    }

    enum Failure: Error, Equatable {
        case notARepository
    }

    // MARK: Repository documents

    static func remotePackages(fromXML data: Data, baseURL: URL, host: Host) throws -> [RemotePackage] {
        let document = try XMLDocument(data: data)
        guard let root = document.rootElement() else { throw Failure.notARepository }

        let licenses = Dictionary(
            root.childElements(named: "license").compactMap { element -> (String, License)? in
                guard let id = element.attributeValue("id") else { return nil }
                return (id, License(id: id, text: element.stringValue ?? ""))
            },
            uniquingKeysWith: { first, _ in first }
        )
        let channels = Dictionary(
            root.childElements(named: "channel").compactMap { element -> (String, ReleaseChannel)? in
                guard let id = element.attributeValue("id") else { return nil }
                let number = Int(id.split(separator: "-").last ?? "") ?? 0
                return (id, ReleaseChannel(rawValue: number) ?? .canary)
            },
            uniquingKeysWith: { first, _ in first }
        )
        let namespaces = namespaceDeclarations(of: root)

        return root.childElements(named: "remotePackage").compactMap { element in
            remotePackage(
                element, licenses: licenses, channels: channels, namespaces: namespaces,
                baseURL: baseURL, host: host
            )
        }
    }

    static func namespaceDeclarations(of element: XMLElement) -> [String: String] {
        var result: [String: String] = [:]
        for node in element.namespaces ?? [] {
            if let prefix = node.name, !prefix.isEmpty, let uri = node.stringValue {
                result[prefix] = uri
            }
        }
        return result
    }

    private static func remotePackage(
        _ element: XMLElement,
        licenses: [String: License],
        channels: [String: ReleaseChannel],
        namespaces: [String: String],
        baseURL: URL,
        host: Host
    ) -> RemotePackage? {
        guard
            let path = element.attributeValue("path"),
            let revision = revision(in: element.childElement(named: "revision")),
            let kind = kind(forPath: path, typeDetails: element.childElement(named: "type-details")),
            let archive = bestArchive(in: element, baseURL: baseURL, host: host)
        else { return nil }

        if case let .systemImage(details) = kind, !host.abis.contains(details.abi.rawValue) {
            return nil
        }

        let channel = element.childElement(named: "channelRef")?.attributeValue("ref").flatMap { channels[$0] }
        let licenseID = element.childElement(named: "uses-license")?.attributeValue("ref")
        let packageXML = (element.children ?? [])
            .compactMap { $0 as? XMLElement }
            .filter { !["archives", "channelRef"].contains($0.localName) }
            .map { $0.xmlString }
            .joined()

        return RemotePackage(
            path: path,
            displayName: element.childText("display-name") ?? path,
            revision: revision,
            channel: channel ?? .stable,
            kind: kind,
            license: licenseID.flatMap { licenses[$0] },
            archive: archive,
            dependencies: dependencies(in: element),
            localPackageXML: packageXML,
            namespaceDeclarations: namespaces
        )
    }

    private static func bestArchive(in element: XMLElement, baseURL: URL, host: Host) -> PackageArchive? {
        let archives = element.childElement(named: "archives")?.childElements(named: "archive") ?? []
        let compatible = archives.filter { archive in
            let os = archive.childText("host-os")
            let arch = archive.childText("host-arch")
            return (os == nil || os == host.os) && (arch == nil || arch == host.arch)
        }
        // Prefer an archive built specifically for this architecture.
        let chosen = compatible.first { $0.childText("host-arch") == host.arch } ?? compatible.first
        guard
            let complete = chosen?.childElement(named: "complete"),
            let urlText = complete.childText("url"),
            let url = URL(string: urlText, relativeTo: baseURL)?.absoluteURL,
            let size = complete.childText("size").flatMap(Int64.init),
            let checksum = complete.childText("checksum")
        else { return nil }
        return PackageArchive(url: url, size: size, sha1: checksum.lowercased())
    }

    private static func dependencies(in element: XMLElement) -> [PackageDependency] {
        (element.childElement(named: "dependencies")?.childElements(named: "dependency") ?? []).compactMap {
            guard let path = $0.attributeValue("path") else { return nil }
            return PackageDependency(path: path, minimumRevision: revision(in: $0.childElement(named: "min-revision")))
        }
    }

    // MARK: package.xml

    static func localPackage(fromXML data: Data, directory: URL) -> LocalPackage? {
        guard
            let document = try? XMLDocument(data: data),
            let element = document.rootElement()?.childElement(named: "localPackage"),
            let path = element.attributeValue("path"),
            let revision = revision(in: element.childElement(named: "revision")),
            let kind = kind(forPath: path, typeDetails: element.childElement(named: "type-details"))
        else { return nil }
        return LocalPackage(
            path: path,
            displayName: element.childText("display-name") ?? path,
            revision: revision,
            kind: kind,
            directory: directory
        )
    }

    // MARK: Shared pieces

    static func revision(in element: XMLElement?) -> PackageRevision? {
        guard let element, let major = element.childText("major").flatMap(Int.init) else { return nil }
        return PackageRevision(
            major: major,
            minor: element.childText("minor").flatMap(Int.init) ?? 0,
            micro: element.childText("micro").flatMap(Int.init) ?? 0,
            preview: element.childText("preview").flatMap(Int.init)
        )
    }

    static func kind(forPath path: String, typeDetails: XMLElement?) -> PackageKind? {
        switch path {
        case SDKPackagePath.emulator: return .emulator
        case SDKPackagePath.platformTools: return .platformTools
        default: break
        }
        let segments = path.split(separator: ";").map(String.init)
        guard segments.first == "system-images" else { return .other }
        guard segments.count == 4, let typeDetails else { return nil }
        return systemImage(typeDetails, platformFolder: segments[1], tagFolder: segments[2], abi: segments[3])
            .map(PackageKind.systemImage)
    }

    private static func systemImage(
        _ details: XMLElement,
        platformFolder: String,
        tagFolder: String,
        abi: String
    ) -> SystemImageDetails? {
        guard let apiLevel = details.childText("api-level").flatMap(APILevel.init(catalogValue:)) else { return nil }

        var tags = details.childElements(named: "tag").compactMap(imageTag)
        tags += details.childElement(named: "tags")?.childElements(named: "tag").compactMap(imageTag) ?? []
        var seen = Set<String>()
        tags = tags.filter { seen.insert($0.id).inserted }

        return SystemImageDetails(
            apiLevel: apiLevel,
            extensionLevel: details.childText("extension-level").flatMap(Int.init),
            isBaseExtension: details.childText("base-extension") != "false",
            stage: stage(details),
            tags: tags,
            vendor: details.childElement(named: "vendor").flatMap(imageTag),
            abi: ABI(rawValue: details.childText("abi") ?? abi),
            platformFolder: platformFolder,
            tagFolder: tagFolder
        )
    }

    private static func stage(_ details: XMLElement) -> ReleaseStage {
        let codename = details.childText("codename")
        if let canary = details.childText("canary-number") {
            return .canary(build: canary)
        }
        if codename == "CANARY" {
            return .canary(build: nil)
        }
        if let beta = details.childText("beta-number").flatMap(Int.init) {
            let target = details.childText("beta-api-level").flatMap(APILevel.init(catalogValue:))
            return .beta(number: beta, targetLevel: target)
        }
        if let codename {
            return .preview(codename: codename)
        }
        return .stable
    }

    private static func imageTag(_ element: XMLElement) -> ImageTag? {
        guard let id = element.childText("id") else { return nil }
        return ImageTag(id: id, display: element.childText("display") ?? id)
    }
}

// MARK: - XMLElement helpers

extension XMLElement {
    func childElements(named name: String) -> [XMLElement] {
        (children ?? []).compactMap { $0 as? XMLElement }.filter { $0.localName == name }
    }

    func childElement(named name: String) -> XMLElement? {
        (children ?? []).lazy.compactMap { $0 as? XMLElement }.first { $0.localName == name }
    }

    func childText(_ name: String) -> String? {
        guard let text = childElement(named: name)?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
            !text.isEmpty
        else { return nil }
        return text
    }

    func attributeValue(_ name: String) -> String? {
        attribute(forName: name)?.stringValue
    }
}
