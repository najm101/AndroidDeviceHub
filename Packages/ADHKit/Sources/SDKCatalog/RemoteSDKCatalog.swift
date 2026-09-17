public import Foundation
import Foundations
public import SDKDomain
import os

/// Google's SDK repository.
///
/// Uses the schema versions the current Android tools understand (`repository2-3`, `sys-img2-4`),
/// so `package.xml` files written from these catalogs stay readable by Android Studio and `sdkmanager`.
public actor RemoteSDKCatalog: SDKCatalogProviding {
    public static let defaultBaseURL = URL(string: "https://dl.google.com/android/repository/")!

    private let baseURL: URL
    private let fetcher: CachedFetcher
    private let host: PackageXMLParser.Host
    private let log = ADHLog.logger("SDKCatalog")
    private var memoryCache: (packages: [RemotePackage], date: Date)?
    private var inFlight: Task<[RemotePackage], any Error>?

    public init(
        cacheDirectory: URL,
        session: URLSession = .shared,
        baseURL: URL = RemoteSDKCatalog.defaultBaseURL,
        maxAge: TimeInterval = 24 * 60 * 60
    ) {
        self.baseURL = baseURL
        fetcher = CachedFetcher(session: session, cacheDirectory: cacheDirectory, maxAge: maxAge)
        host = .current
    }

    public func remotePackages(forceRefresh: Bool) async throws -> [RemotePackage] {
        if !forceRefresh, let memoryCache, Date.now.timeIntervalSince(memoryCache.date) < 60 * 10 {
            return memoryCache.packages
        }
        if let inFlight, !forceRefresh {
            return try await inFlight.value
        }
        let task = Task { try await load(forceRefresh: forceRefresh) }
        inFlight = task
        defer { inFlight = nil }
        let packages = try await task.value
        memoryCache = (packages, .now)
        return packages
    }

    private func load(forceRefresh: Bool) async throws -> [RemotePackage] {
        let repositoryURL = baseURL.appending(path: "repository2-3.xml")
        let siteListURL = baseURL.appending(path: "addons_list-6.xml")

        async let repositoryData = fetcher.data(from: repositoryURL, forceRefresh: forceRefresh)
        let siteURLs = try SiteList.systemImageSites(
            fromXML: await fetcher.data(from: siteListURL, forceRefresh: forceRefresh),
            baseURL: baseURL
        )

        var packages = try PackageXMLParser.remotePackages(
            fromXML: await repositoryData, baseURL: repositoryURL, host: host
        ).filter { $0.kind == .emulator || $0.kind == .platformTools }

        let host = host
        let fetcher = fetcher
        let log = log
        try await withThrowingTaskGroup(of: [RemotePackage].self) { group in
            for siteURL in siteURLs {
                group.addTask {
                    do {
                        let data = try await fetcher.data(from: siteURL, forceRefresh: forceRefresh)
                        return try PackageXMLParser.remotePackages(fromXML: data, baseURL: siteURL, host: host)
                    } catch {
                        // One broken site shouldn't hide every other image.
                        log.error(
                            "Skipping \(siteURL, privacy: .public): \(error.localizedDescription, privacy: .public)")
                        return []
                    }
                }
            }
            for try await sitePackages in group {
                packages += sitePackages
            }
        }
        return packages
    }
}

/// The list of system image catalogs (`addons_list-N.xml`).
enum SiteList {
    /// Sites that aren't meant for interactive emulators.
    static let excludedFragments = ["_atd/", "-cn/"]

    static func systemImageSites(fromXML data: Data, baseURL: URL) throws -> [URL] {
        let document = try XMLDocument(data: data)
        guard let root = document.rootElement() else { throw PackageXMLParser.Failure.notARepository }
        return root.childElements(named: "site").compactMap { site in
            let type =
                site.attribute(forLocalName: "type", uri: "http://www.w3.org/2001/XMLSchema-instance")?
                .stringValue ?? ""
            guard type.hasSuffix("sysImgSiteType"), let path = site.childText("url") else { return nil }
            guard !excludedFragments.contains(where: path.contains) else { return nil }
            return URL(string: path, relativeTo: baseURL)?.absoluteURL
        }
    }
}

/// Downloads small XML files, keeping an on-disk copy with its ETag.
actor CachedFetcher {
    private let session: URLSession
    private let cacheDirectory: URL
    private let maxAge: TimeInterval

    init(session: URLSession, cacheDirectory: URL, maxAge: TimeInterval) {
        self.session = session
        self.cacheDirectory = cacheDirectory
        self.maxAge = maxAge
    }

    func data(from url: URL, forceRefresh: Bool) async throws -> Data {
        let file = cacheFile(for: url)
        let etagFile = file.appendingPathExtension("etag")
        let cached = try? Data(contentsOf: file)
        let age = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            .map { Date.now.timeIntervalSince($0) }

        if let cached, !forceRefresh, let age, age < maxAge {
            return cached
        }

        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        if cached != nil, let etag = try? String(contentsOf: etagFile, encoding: .utf8) {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }

        do {
            let (data, response) = try await session.data(for: request)
            let http = response as? HTTPURLResponse
            if http?.statusCode == 304, let cached {
                try? FileManager.default.setAttributes([.modificationDate: Date.now], ofItemAtPath: file.path)
                return cached
            }
            guard let http, (200..<300).contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }
            try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
            try data.write(to: file, options: .atomic)
            if let etag = http.value(forHTTPHeaderField: "ETag") {
                try? etag.write(to: etagFile, atomically: true, encoding: .utf8)
            }
            return data
        } catch {
            // Offline: an old catalog is better than none.
            if let cached { return cached }
            throw error
        }
    }

    private func cacheFile(for url: URL) -> URL {
        let name = url.path(percentEncoded: false)
            .split(separator: "/")
            .suffix(3)
            .joined(separator: "_")
        return cacheDirectory.appending(path: name, directoryHint: .notDirectory)
    }
}
