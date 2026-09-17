public import Foundation
public import Foundations
public import SDKDomain
import os

public enum AVDStoreError: LocalizedError, Equatable {
    case invalidName
    case nameInUse(String)
    case missingConfiguration

    public var errorDescription: String? {
        switch self {
        case .invalidName: "Use letters, numbers, spaces, dots, dashes or underscores."
        case let .nameInUse(name): "A device named “\(name)” already exists."
        case .missingConfiguration: "The device's configuration file is missing."
        }
    }
}

/// Reads and writes AVD folders directly.
public struct AVDFileStore: AVDStoring {
    private let fileSystem: any FileSystem
    private let log = ADHLog.logger("AVDStore")

    public init(fileSystem: any FileSystem = LiveFileSystem()) {
        self.fileSystem = fileSystem
    }

    // MARK: - Reading

    public func devices(in location: SDKLocation) async throws -> [VirtualDevice] {
        guard fileSystem.directoryExists(at: location.avdHome) else { return [] }
        return try fileSystem.contentsOfDirectory(at: location.avdHome)
            .filter { $0.pathExtension == "ini" }
            .compactMap { device(pointer: $0, location: location) }
            .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }

    func device(pointer: URL, location: SDKLocation) -> VirtualDevice? {
        let id = pointer.deletingPathExtension().lastPathComponent
        guard let pointerText = try? fileSystem.string(contentsOf: pointer) else { return nil }
        let ini = IniDocument(text: pointerText)
        let directory = resolveDirectory(ini: ini, id: id, location: location)

        let configURL = directory.appending(path: "config.ini", directoryHint: .notDirectory)
        guard let configText = try? fileSystem.string(contentsOf: configURL) else {
            return VirtualDevice(
                id: id, displayName: id, directory: directory, iniFile: pointer,
                issues: [.unreadableConfiguration(reason: "config.ini is missing")]
            )
        }
        let config = IniDocument(text: configText)
        return VirtualDeviceMapper.device(id: id, config: config, pointer: ini, directory: directory, iniFile: pointer)
        {
            fileSystem.directoryExists(at: location.url(forSysdir: $0))
        }
    }

    private func resolveDirectory(ini: IniDocument, id: String, location: SDKLocation) -> URL {
        if let path = ini["path"], fileSystem.directoryExists(at: URL(filePath: path, directoryHint: .isDirectory)) {
            return URL(filePath: path, directoryHint: .isDirectory)
        }
        return location.avdHome.appending(path: "\(id).avd", directoryHint: .isDirectory)
    }

    // MARK: - Writing

    public func create(_ specification: VirtualDeviceSpecification, in location: SDKLocation) async throws
        -> VirtualDevice
    {
        let id = try validatedNewID(specification.id, in: location)
        let directory = location.avdHome.appending(path: "\(id).avd", directoryHint: .isDirectory)
        let pointer = location.avdHome.appending(path: "\(id).ini", directoryHint: .notDirectory)

        var spec = specification
        spec.id = id
        try fileSystem.createDirectory(at: directory)
        do {
            let config = AVDConfigurationBuilder.configuration(for: spec)
            try fileSystem.write(config.text, to: directory.appending(path: "config.ini", directoryHint: .notDirectory))
            if let sdCard = spec.sdCardMiB, sdCard > 0 {
                try await createSDCard(megabytes: sdCard, in: directory, location: location)
            }
            let ini = AVDConfigurationBuilder.pointer(id: id, avdDirectory: directory, image: spec.image)
            try fileSystem.write(ini.text, to: pointer)
        } catch {
            try? fileSystem.removeItem(at: directory)
            throw error
        }
        log.info("Created AVD \(id, privacy: .public)")
        return try loaded(pointer, location)
    }

    public func rename(_ device: VirtualDevice, toDisplayName name: String, in location: SDKLocation) async throws
        -> VirtualDevice
    {
        let displayName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let newID = VirtualDeviceName.id(fromDisplayName: displayName)
        guard !displayName.isEmpty, VirtualDeviceName.isValidID(newID) else { throw AVDStoreError.invalidName }

        var directory = device.directory
        var pointer = device.iniFile
        if newID != device.id {
            _ = try validatedNewID(newID, in: location, ignoring: device.id)
            let newDirectory = location.avdHome.appending(path: "\(newID).avd", directoryHint: .isDirectory)
            let newPointer = location.avdHome.appending(path: "\(newID).ini", directoryHint: .notDirectory)
            try fileSystem.moveItem(at: device.directory, to: newDirectory)
            try fileSystem.moveItem(at: device.iniFile, to: newPointer)
            directory = newDirectory
            pointer = newPointer

            var ini = IniDocument(text: try fileSystem.string(contentsOf: pointer), defaultStyle: .compact)
            ini["path"] = directory.path(percentEncoded: false).trimmingSuffix("/")
            ini["path.rel"] = "avd/\(directory.lastPathComponent)"
            try fileSystem.write(ini.text, to: pointer)
            // The emulator regenerates these with the new paths on the next launch.
            for stale in ["hardware-qemu.ini", "emu-launch-params.txt"] {
                try? fileSystem.removeItem(at: directory.appending(path: stale, directoryHint: .notDirectory))
            }
        }

        try updateConfig(in: directory) { config in
            config["AvdId"] = newID
            config["avd.ini.displayname"] = displayName
        }
        return try loaded(pointer, location)
    }

    public func duplicate(_ device: VirtualDevice, as displayName: String, in location: SDKLocation) async throws
        -> VirtualDevice
    {
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let id = try validatedNewID(VirtualDeviceName.id(fromDisplayName: name), in: location)
        let directory = location.avdHome.appending(path: "\(id).avd", directoryHint: .isDirectory)
        let pointer = location.avdHome.appending(path: "\(id).ini", directoryHint: .notDirectory)

        // A duplicate starts fresh: same hardware and image, no user data or snapshots.
        var config = IniDocument(text: try fileSystem.string(contentsOf: configURL(device.directory)))
        config["AvdId"] = id
        config["avd.ini.displayname"] = name
        try fileSystem.createDirectory(at: directory)
        do {
            try fileSystem.write(config.text, to: configURL(directory))
            var ini = IniDocument(text: try fileSystem.string(contentsOf: device.iniFile), defaultStyle: .compact)
            ini["path"] = directory.path(percentEncoded: false).trimmingSuffix("/")
            ini["path.rel"] = "avd/\(directory.lastPathComponent)"
            try fileSystem.write(ini.text, to: pointer)
        } catch {
            try? fileSystem.removeItem(at: directory)
            throw error
        }
        return try loaded(pointer, location)
    }

    public func wipeData(of device: VirtualDevice) async throws {
        let contents = (try? fileSystem.contentsOfDirectory(at: device.directory)) ?? []
        for file in contents where AVDWipePolicy.shouldRemove(file.lastPathComponent) {
            try fileSystem.removeItem(at: file)
        }
        log.info("Wiped AVD \(device.id, privacy: .public)")
    }

    public func delete(_ device: VirtualDevice, in location: SDKLocation) async throws {
        try fileSystem.removeItem(at: device.directory)
        try fileSystem.removeItem(at: device.iniFile)
        log.info("Deleted AVD \(device.id, privacy: .public)")
    }

    public func changes(in location: SDKLocation) -> AsyncStream<Void> {
        try? fileSystem.createDirectory(at: location.avdHome)
        return DirectoryWatcher.changes(of: location.avdHome)
    }

    // MARK: - Helpers

    private func configURL(_ directory: URL) -> URL {
        directory.appending(path: "config.ini", directoryHint: .notDirectory)
    }

    private func updateConfig(in directory: URL, _ change: (inout IniDocument) -> Void) throws {
        let url = configURL(directory)
        guard let text = try? fileSystem.string(contentsOf: url) else { throw AVDStoreError.missingConfiguration }
        var config = IniDocument(text: text)
        change(&config)
        try fileSystem.write(config.text, to: url)
    }

    private func loaded(_ pointer: URL, _ location: SDKLocation) throws -> VirtualDevice {
        guard let device = device(pointer: pointer, location: location) else {
            throw AVDStoreError.missingConfiguration
        }
        return device
    }

    /// Ids must be unique ignoring case (APFS is case-insensitive by default).
    private func validatedNewID(_ id: String, in location: SDKLocation, ignoring current: String? = nil) throws
        -> String
    {
        guard VirtualDeviceName.isValidID(id) else { throw AVDStoreError.invalidName }
        let existing = ((try? fileSystem.contentsOfDirectory(at: location.avdHome)) ?? [])
            .map { $0.deletingPathExtension().lastPathComponent.lowercased() }
        let taken = Set(existing).subtracting([current?.lowercased()].compactMap { $0 })
        guard !taken.contains(id.lowercased()) else { throw AVDStoreError.nameInUse(id) }
        return id
    }

    private func createSDCard(megabytes: Int, in directory: URL, location: SDKLocation) async throws {
        let tool = location.emulatorDirectory.appending(path: "mksdcard", directoryHint: .notDirectory)
        let image = directory.appending(path: "sdcard.img", directoryHint: .notDirectory)
        guard fileSystem.fileExists(at: tool) else {
            log.notice("mksdcard not found; the emulator will run without an SD card image")
            return
        }
        try await ProcessRunner.run(tool, arguments: ["\(megabytes)M", image.path(percentEncoded: false)])
    }
}

/// Files removed by "Reset Device" (wipe data).
enum AVDWipePolicy {
    static func shouldRemove(_ name: String) -> Bool {
        name.hasPrefix("userdata-qemu.img")
            || name.hasPrefix("cache.img")
            || name.hasPrefix("encryptionkey.img")
            || name == "snapshots"
            || name.hasSuffix(".lock")
            || name == "hardware-qemu.ini"
            || name == "emu-launch-params.txt"
    }
}

/// Maps `config.ini` values to a `VirtualDevice`.
enum VirtualDeviceMapper {
    static func device(
        id: String,
        config: IniDocument,
        pointer: IniDocument,
        directory: URL,
        iniFile: URL,
        sysdirExists: (String) -> Bool
    ) -> VirtualDevice {
        let sysdir = config["image.sysdir.1"]
        var issues: [VirtualDeviceIssue] = []
        if let sysdir, !sysdirExists(sysdir) {
            issues.append(.missingSystemImage(sysdir: sysdir))
        }
        let tagID = config["tag.id"] ?? sysdir.flatMap(tagFolder(fromSysdir:))
        return VirtualDevice(
            id: id,
            displayName: config["avd.ini.displayname"] ?? id.replacingOccurrences(of: "_", with: " "),
            directory: directory,
            iniFile: iniFile,
            sysdir: sysdir,
            apiLevel: apiLevel(sysdir: sysdir, target: pointer["target"]),
            tagID: tagID,
            tagDisplay: config["tag.display"],
            abi: config["abi.type"].map(ABI.init(rawValue:)),
            hasPlayStore: config.bool("PlayStore.enabled")
                ?? (tagID.map { ImageServices(tagID: $0) == .googlePlay } ?? false),
            hardwareProfileID: config["hw.device.name"],
            manufacturer: config["hw.device.manufacturer"],
            screenWidth: config.int("hw.lcd.width"),
            screenHeight: config.int("hw.lcd.height"),
            density: config.int("hw.lcd.density"),
            ramMiB: config["hw.ramSize"].flatMap(ramMiB),
            cpuCores: config.int("hw.cpu.ncore"),
            dataPartitionBytes: config["disk.dataPartition.size"].flatMap(SizeValue.bytes),
            skinName: config["skin.name"],
            skinPath: config["skin.path"],
            networkSpeed: config["runtime.network.speed"].flatMap(NetworkSpeed.init(rawValue:)),
            networkLatency: config["runtime.network.latency"].flatMap(NetworkLatency.init(rawValue:)),
            issues: issues
        )
    }

    /// `system-images/android-36.1/google_apis/arm64-v8a/` → 36.1; falls back to `target=android-36`.
    static func apiLevel(sysdir: String?, target: String?) -> APILevel? {
        let platform = sysdir?.split(separator: "/").dropFirst().first.map(String.init) ?? target
        guard let platform, platform.hasPrefix("android-") else { return nil }
        let version = platform.dropFirst("android-".count).split(separator: "-").first.map(String.init) ?? ""
        return APILevel(catalogValue: version)
    }

    static func tagFolder(fromSysdir sysdir: String) -> String? {
        let parts = sysdir.split(separator: "/")
        return parts.count >= 3 ? String(parts[2]) : nil
    }

    /// `hw.ramSize` is MiB, but some tools write `2G` / `2048M`.
    static func ramMiB(_ value: String) -> Int? {
        if let plain = Int(value) { return plain }
        return SizeValue.bytes(value).map { Int($0 / .mebibyte) }
    }
}
