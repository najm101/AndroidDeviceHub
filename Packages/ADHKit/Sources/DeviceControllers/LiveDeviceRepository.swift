import ADBClient
public import ADBRuntime
import AVDStore
public import DeviceDomain
public import EmulatorRuntime
public import Foundation
import Foundations
public import Observation
public import SDKDomain
import os

/// Merges AVDs and running emulators into the device list, and owns the live sessions.
/// Physical devices join here in M7 through a second source.
@MainActor
@Observable
public final class LiveDeviceRepository: DeviceRepository {
    public private(set) var devices: [Device] = []
    public private(set) var isLoading = false
    public private(set) var lastError: String?

    private let context: SDKContext
    private let avdStore: any AVDStoring
    private let profiles: [String: HardwareProfile]
    private let discovery: EmulatorDiscovery
    private let launcher: EmulatorLauncher
    private let reveal: @MainActor (URL) -> Void
    private let frameDirectory: URL
    private let showsEmulatorWindow: @MainActor () -> Bool
    private let adb: ADBRuntime?
    private let labelCache: AppLabelCache

    /// Devices the ADB server reports, by serial.
    private var adbDevices: [String: ADBDeviceEntry] = [:]

    @ObservationIgnored private var starting: Set<String> = []
    /// Live gRPC sessions keyed by AVD id, for emulators this app can control.
    @ObservationIgnored private var sessions: [String: EmulatorSession] = [:]
    /// ADB inspectors keyed by AVD id, for emulators that ADB reports as ready.
    @ObservationIgnored private var inspectors: [String: ADBInspector] = [:]
    @ObservationIgnored private var watchTask: Task<Void, Never>?
    @ObservationIgnored private var adbTask: Task<Void, Never>?
    @ObservationIgnored private var watchedLocation: SDKLocation?
    @ObservationIgnored private let log = ADHLog.logger("DeviceRepository")

    public init(
        context: SDKContext,
        avdStore: any AVDStoring,
        profiles: any HardwareProfileProviding,
        discovery: EmulatorDiscovery,
        launcher: EmulatorLauncher,
        frameDirectory: URL,
        showsEmulatorWindow: @escaping @MainActor () -> Bool = { false },
        adb: ADBRuntime? = nil,
        labelCache: AppLabelCache = AppLabelCache(file: nil),
        reveal: @escaping @MainActor (URL) -> Void
    ) {
        self.adb = adb
        self.labelCache = labelCache
        self.context = context
        self.avdStore = avdStore
        self.profiles = Dictionary(profiles.profiles().map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        self.discovery = discovery
        self.launcher = launcher
        self.reveal = reveal
        self.frameDirectory = frameDirectory
        self.showsEmulatorWindow = showsEmulatorWindow
    }

    // MARK: - Loading

    public func device(withID id: DeviceID) -> Device? {
        devices.first { $0.id == id }
    }

    public func session(for id: DeviceID) -> (any DeviceSession)? {
        guard case let .emulator(avdID) = id else { return nil }
        return sessions[avdID]
    }

    public func inspector(for id: DeviceID) -> (any DeviceInspecting)? {
        guard case let .emulator(avdID) = id else { return nil }
        return inspectors[avdID]
    }

    public func reload() async {
        guard let location = context.location else {
            devices = []
            return
        }
        startWatching(location)
        startTrackingADB()
        isLoading = devices.isEmpty
        defer { isLoading = false }
        do {
            let virtualDevices = try await avdStore.devices(in: location)
            let running = discovery.runningEmulators()
            syncSessions(running: running, devices: virtualDevices)
            devices = virtualDevices.map { makeDevice($0, running: running) }
            lastError = nil
        } catch {
            log.error("Loading devices failed: \(error.localizedDescription, privacy: .public)")
            lastError = error.localizedDescription
        }
    }

    /// Reloads whenever the AVD folder changes or emulators start/stop.
    private func startWatching(_ location: SDKLocation) {
        guard watchedLocation != location else { return }
        watchedLocation = location
        watchTask?.cancel()
        let folderChanges = avdStore.changes(in: location)
        let runtimeChanges = discovery.changes()
        // The repository lives as long as the app; the task is replaced when the SDK location changes.
        watchTask = Task {
            await withTaskGroup(of: Void.self) { group in
                group.addTask { for await _ in folderChanges { await self.reload() } }
                group.addTask { for await _ in runtimeChanges { await self.refreshRunningState() } }
            }
        }
    }

    /// Follows the ADB device list once Platform Tools are installed.
    private func startTrackingADB() {
        guard let adb, adbTask == nil, context.hasPlatformTools else { return }
        let context = context
        let updates = adb.deviceUpdates { @MainActor [context] in context.location?.adbExecutable }
        adbTask = Task { [weak self] in
            for await entries in updates {
                guard let self else { return }
                adbDevices = Dictionary(entries.map { ($0.serial, $0) }, uniquingKeysWith: { _, last in last })
                await refreshRunningState()
            }
        }
    }

    private func refreshRunningState() async {
        let running = discovery.runningEmulators()
        syncSessions(running: running, devices: devices.compactMap(\.virtualDevice))
        let updated = devices.map { device in
            device.virtualDevice.map { makeDevice($0, running: running) } ?? device
        }
        if updated != devices {
            devices = updated
        }
    }

    /// Opens sessions for newly running emulators and closes those that stopped.
    private func syncSessions(running: [RunningEmulator], devices: [VirtualDevice]) {
        starting.subtract(running.map(\.avdID))
        syncInspectors(running: running, devices: devices)
        let controllable = Dictionary(
            running.filter(\.hasGRPCToken).map { ($0.avdID, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        for (avdID, session) in sessions where controllable[avdID] == nil {
            session.close()
            sessions[avdID] = nil
        }
        for (avdID, emulator) in controllable where sessions[avdID] == nil {
            guard let avd = devices.first(where: { $0.id == avdID }) else { continue }
            let size = PixelSize(width: avd.screenWidth ?? 1080, height: avd.screenHeight ?? 2400)
            do {
                let network = NetworkConditions(speed: avd.networkSpeed ?? .full, latency: avd.networkLatency ?? .none)
                sessions[avdID] = try EmulatorSession(
                    emulator: emulator, displaySize: size, frameDirectory: frameDirectory, network: network
                )
            } catch {
                log.error(
                    "Can't connect to \(avdID, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Creates inspectors for emulators that ADB reports as ready and drops the rest.
    private func syncInspectors(running: [RunningEmulator], devices: [VirtualDevice]) {
        let ready = Dictionary(
            running.compactMap { emulator in
                emulator.adbSerial.flatMap { adbDevices[$0]?.isReady == true ? (emulator.avdID, emulator) : nil }
            },
            uniquingKeysWith: { first, _ in first }
        )
        for (avdID, inspector) in inspectors where ready[avdID]?.adbSerial != inspector.serial {
            inspectors[avdID] = nil
        }
        guard let server = adb?.server else { return }
        for (avdID, emulator) in ready where inspectors[avdID] == nil {
            guard let serial = emulator.adbSerial, let avd = devices.first(where: { $0.id == avdID }) else { continue }
            inspectors[avdID] = ADBInspector(
                device: server.device(serial: serial),
                homeDirectory: "/",
                extraProperties: [Self.emulatorProperties(avd, emulator: emulator)],
                labelCache: labelCache
            )
        }
    }

    private static func emulatorProperties(_ avd: VirtualDevice, emulator: RunningEmulator) -> DevicePropertyGroup {
        var properties = [DeviceProperty("AVD", avd.id)]
        if let image = avd.tagDisplay ?? avd.tagID {
            properties.append(DeviceProperty("System image", image))
        }
        if let version = emulator.emulatorVersion {
            properties.append(DeviceProperty("Emulator version", version))
        }
        properties.append(DeviceProperty("Folder", avd.directory.path(percentEncoded: false)))
        return DevicePropertyGroup("Emulator", properties)
    }

    private func adbStatus(for avdID: String, running: [RunningEmulator]) -> EmulatorCapabilities.ADBStatus {
        guard adb != nil, context.hasPlatformTools else { return .unavailable }
        return inspectors[avdID] != nil ? .ready : .connecting
    }

    func makeDevice(_ avd: VirtualDevice, running: [RunningEmulator]) -> Device {
        let state: DeviceState
        if running.contains(where: { $0.avdID == avd.id }) {
            state = .running(inAppControl: sessions[avd.id] != nil)
        } else if starting.contains(avd.id) {
            state = .starting
        } else if let issue = avd.issues.first {
            switch issue {
            case let .missingSystemImage(sysdir): state = .needsAttention(.missingSystemImage(sysdir: sysdir))
            case let .unreadableConfiguration(reason): state = .needsAttention(.unreadable(reason: reason))
            }
        } else {
            state = .stopped
        }

        let profile = avd.hardwareProfileID.flatMap { profiles[$0] }
        let formFactor = profile?.formFactor ?? avd.tagID.flatMap(FormFactor.init(imageTagID:)) ?? .phone
        let screen = zip(avd.screenWidth, avd.screenHeight).map { PixelSize(width: $0, height: $1) }
        return Device(
            id: .emulator(avdID: avd.id),
            name: avd.displayName,
            kind: .emulator,
            state: state,
            apiLevel: avd.apiLevel,
            formFactor: formFactor,
            screenSize: screen,
            hasPlayStore: avd.hasPlayStore,
            capabilities: EmulatorCapabilities.capabilities(
                for: state, formFactor: formFactor, adb: adbStatus(for: avd.id, running: running)
            ),
            virtualDevice: avd
        )
    }

    // MARK: - Actions

    public func start(_ id: DeviceID, option: StartOption) async throws {
        let (avd, location) = try emulator(id, requiring: .start)
        starting.insert(avd.id)
        updateState(of: id)
        do {
            try await launcher.launch(
                avdID: avd.id,
                options: LaunchOptions(coldBoot: option == .coldBoot, hideWindow: !showsEmulatorWindow()),
                location: location
            )
            // Stays "starting" until the discovery file appears.
            scheduleStartTimeout(for: avd.id)
        } catch {
            starting.remove(avd.id)
            updateState(of: id)
            throw error
        }
    }

    public func shutDown(_ id: DeviceID) async throws {
        _ = try emulator(id, requiring: .shutDown)
        guard let session = session(for: id) else { throw DeviceActionError.notSupported }
        try await session.shutDown()
    }

    public func restart(_ id: DeviceID) async throws {
        _ = try emulator(id, requiring: .restart)
        guard let session = session(for: id) else { throw DeviceActionError.notSupported }
        try await session.restart()
    }

    public func create(_ specification: VirtualDeviceSpecification) async throws -> DeviceID {
        guard let location = context.location else { throw DeviceActionError.missingSDK }
        let avd = try await avdStore.create(specification, in: location)
        await reload()
        return .emulator(avdID: avd.id)
    }

    public func rename(_ id: DeviceID, to name: String) async throws {
        let (avd, location) = try emulator(id, requiring: .rename)
        _ = try await avdStore.rename(avd, toDisplayName: name, in: location)
        await reload()
    }

    public func duplicate(_ id: DeviceID, as name: String) async throws -> DeviceID {
        let (avd, location) = try emulator(id, requiring: .duplicate)
        let copy = try await avdStore.duplicate(avd, as: name, in: location)
        await reload()
        return .emulator(avdID: copy.id)
    }

    public func wipeData(_ id: DeviceID) async throws {
        let (avd, _) = try emulator(id, requiring: .wipeData)
        try await avdStore.wipeData(of: avd)
        await reload()
    }

    public func remove(_ id: DeviceID) async throws {
        let (avd, location) = try emulator(id, requiring: .remove)
        try await avdStore.delete(avd, in: location)
        await reload()
    }

    public func revealInFinder(_ id: DeviceID) {
        guard let avd = device(withID: id)?.virtualDevice else { return }
        reveal(avd.directory)
    }

    // MARK: - Helpers

    private func emulator(_ id: DeviceID, requiring capability: Capability) throws -> (VirtualDevice, SDKLocation) {
        guard let location = context.location else { throw DeviceActionError.missingSDK }
        guard let device = device(withID: id), let avd = device.virtualDevice else { throw DeviceActionError.notFound }
        switch device.availability(of: capability) {
        case .available: return (avd, location)
        case .disabled where device.state.isRunning: throw DeviceActionError.deviceIsRunning
        default: throw DeviceActionError.notSupported
        }
    }

    private func updateState(of id: DeviceID) {
        guard let index = devices.firstIndex(where: { $0.id == id }), let avd = devices[index].virtualDevice else {
            return
        }
        let running = discovery.runningEmulators()
        syncSessions(running: running, devices: [avd])
        devices[index] = makeDevice(avd, running: running)
    }

    private func scheduleStartTimeout(for avdID: String) {
        Task {
            try? await Task.sleep(for: .seconds(60))
            guard starting.remove(avdID) != nil else { return }
            updateState(of: .emulator(avdID: avdID))
        }
    }
}

private func zip<A, B>(_ first: A?, _ second: B?) -> (A, B)? {
    guard let first, let second else { return nil }
    return (first, second)
}
