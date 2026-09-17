import CryptoKit
public import Foundation
public import Foundations
public import SDKDomain
import ZIPFoundation
import os

public enum PackageInstallError: LocalizedError, Equatable {
    case licenseNotAccepted(String)
    case notEnoughSpace(needed: Int64, available: Int64)
    case checksumMismatch
    case unexpectedArchiveLayout
    case sdkNotWritable

    public var errorDescription: String? {
        switch self {
        case let .licenseNotAccepted(id): "The license \(id) hasn't been accepted."
        case let .notEnoughSpace(needed, available):
            "Not enough disk space: \(needed.formattedFileSize) needed, \(available.formattedFileSize) available."
        case .checksumMismatch: "The download is damaged (checksum mismatch). Try again."
        case .unexpectedArchiveLayout: "The downloaded archive has an unexpected layout."
        case .sdkNotWritable: "The Android SDK folder isn't writable."
        }
    }
}

/// Installs and removes SDK packages without `sdkmanager`.
public struct PackageInstaller: SDKInstalling {
    private let fileSystem: any FileSystem
    private let downloader: FileDownloader
    private let licenses: LicenseStore
    private let log = ADHLog.logger("SDKInstaller")

    public init(fileSystem: any FileSystem = LiveFileSystem(), session: URLSession = .shared) {
        self.fileSystem = fileSystem
        downloader = FileDownloader(session: session)
        licenses = LicenseStore(fileSystem: fileSystem)
    }

    public func isLicenseAccepted(_ license: License, in location: SDKLocation) async -> Bool {
        licenses.isAccepted(license, in: location)
    }

    public func acceptLicense(_ license: License, in location: SDKLocation) async throws {
        try licenses.accept(license, in: location)
    }

    public func install(
        _ package: RemotePackage,
        in location: SDKLocation,
        progress: @escaping @Sendable (InstallProgress) -> Void
    ) async throws {
        progress(InstallProgress(phase: .preparing, totalBytes: package.archive.size))
        if let license = package.license, !licenses.isAccepted(license, in: location) {
            throw PackageInstallError.licenseNotAccepted(license.id)
        }
        try fileSystem.createDirectory(at: location.sdkRoot)
        guard fileSystem.isWritableDirectory(at: location.sdkRoot) else { throw PackageInstallError.sdkNotWritable }
        try checkFreeSpace(for: package, in: location)

        let workDirectory = location.temporaryDirectory
        let archive = workDirectory.appending(path: "\(package.archive.sha1).zip", directoryHint: .notDirectory)
        let extraction = workDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? fileSystem.removeItem(at: extraction) }

        if !(fileSystem.fileExists(at: archive) && (try? sha1(of: archive)) == package.archive.sha1) {
            try await downloader.download(package.archive.url, to: archive, expectedSize: package.archive.size) {
                received, total, speed in
                progress(
                    InstallProgress(
                        phase: .downloading, receivedBytes: received, totalBytes: total, bytesPerSecond: speed))
            }
            try Task.checkCancellation()
            progress(InstallProgress(phase: .verifying, totalBytes: package.archive.size))
            guard try sha1(of: archive) == package.archive.sha1 else {
                try? fileSystem.removeItem(at: archive)
                throw PackageInstallError.checksumMismatch
            }
        }

        try Task.checkCancellation()
        progress(InstallProgress(phase: .extracting, totalBytes: package.archive.size))
        try fileSystem.createDirectory(at: extraction)
        // The SHA-1 of the whole archive was verified, so per-entry CRC checks are skipped.
        try FileManager.default.unzipItem(at: archive, to: extraction, skipCRC32: true)

        progress(InstallProgress(phase: .finishing, totalBytes: package.archive.size))
        let extractedRoot = try singleTopLevelDirectory(in: extraction)
        let destination = location.sdkRoot.appending(path: package.relativeInstallPath, directoryHint: .isDirectory)
        try replace(destination, with: extractedRoot, workDirectory: workDirectory)
        try fileSystem.write(
            PackageXMLWriter.document(for: package),
            to: destination.appending(path: "package.xml", directoryHint: .notDirectory)
        )
        try? fileSystem.removeItem(at: archive)
        log.info("Installed \(package.path, privacy: .public) \(package.revision, privacy: .public)")
    }

    public func uninstall(_ package: LocalPackage, in location: SDKLocation) async throws {
        let trash = location.temporaryDirectory.appending(
            path: "removed-\(UUID().uuidString)", directoryHint: .isDirectory)
        try fileSystem.moveItem(at: package.directory, to: trash)
        try fileSystem.removeItem(at: trash)
        log.info("Removed \(package.path, privacy: .public)")
    }

    // MARK: - Steps

    private func checkFreeSpace(for package: RemotePackage, in location: SDKLocation) throws {
        // Archive + extracted files + some headroom.
        let needed = package.archive.size * 5 / 2
        if let available = fileSystem.availableCapacity(at: location.sdkRoot), available < needed {
            throw PackageInstallError.notEnoughSpace(needed: needed, available: available)
        }
    }

    private func singleTopLevelDirectory(in directory: URL) throws -> URL {
        let entries = try fileSystem.contentsOfDirectory(at: directory)
            .filter { $0.lastPathComponent != "__MACOSX" }
        guard entries.count == 1, let root = entries.first, fileSystem.directoryExists(at: root) else {
            throw PackageInstallError.unexpectedArchiveLayout
        }
        return root
    }

    /// Moves the new folder into place; the old one is removed only after the move succeeded.
    private func replace(_ destination: URL, with newFolder: URL, workDirectory: URL) throws {
        var previous: URL?
        if fileSystem.fileExists(at: destination) {
            let backup = workDirectory.appending(path: "previous-\(UUID().uuidString)", directoryHint: .isDirectory)
            try fileSystem.moveItem(at: destination, to: backup)
            previous = backup
        }
        do {
            try fileSystem.moveItem(at: newFolder, to: destination)
        } catch {
            if let previous { try? fileSystem.moveItem(at: previous, to: destination) }
            throw error
        }
        if let previous { try? fileSystem.removeItem(at: previous) }
    }

    private func sha1(of file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hasher = Insecure.SHA1()
        while let chunk = try handle.read(upToCount: 4 * 1024 * 1024), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
