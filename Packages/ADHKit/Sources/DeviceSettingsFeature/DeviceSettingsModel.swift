public import DeviceDomain
import Foundation
public import Foundations
public import Observation

/// Dependencies of the settings inspector, wired by the app.
@MainActor
public struct DeviceSettingsDependencies {
    public var repository: any DeviceRepository
    /// Keeps the user's screen size presets.
    public var preferences: any KeyValueStore

    public init(repository: any DeviceRepository, preferences: any KeyValueStore = InMemoryKeyValueStore()) {
        self.repository = repository
        self.preferences = preferences
    }
}

/// Inspector ▸ Settings for one device.
///
/// Values are read from the device each time a section opens and applied as soon as they change.
@MainActor
@Observable
public final class DeviceSettingsModel {
    var expandedSections: Set<SettingsSection> = [.location, .battery]
    private(set) var errors: [SettingsSection: String] = [:]
    /// Sections with an action in progress (a snapshot save, a call…).
    private(set) var busySections: Set<SettingsSection> = []

    // Live values
    private(set) var battery: LiveSetting<BatteryState>!
    private(set) var location: LiveSetting<GeoLocation>!
    private(set) var network: LiveSetting<NetworkConditions>!
    private(set) var sensors: LiveSetting<[AmbientSensor: Double]>!
    private(set) var brightness: LiveSetting<Int>!
    private(set) var hostMicrophone: LiveSetting<Bool>!
    private(set) var clipboard: LiveSetting<String>!
    private(set) var snapshots: LiveSetting<[DeviceSnapshot]>!
    private(set) var display: LiveSetting<DisplayMetrics>!
    private(set) var customScreenPresets: [ScreenPreset] = []

    // Actions without a readable value
    var phoneNumber = "5551234567"
    var smsText = ""
    var fingerprintID = 1
    private(set) var posture: FoldPosture?
    private(set) var lastSnapshotAction: String?

    let deviceID: DeviceID
    private let dependencies: DeviceSettingsDependencies

    public init(deviceID: DeviceID, dependencies: DeviceSettingsDependencies) {
        self.deviceID = deviceID
        self.dependencies = dependencies
        battery = setting(.battery, read: { try await $0.battery() }, write: { try await $0.setBattery($1) })
        location = setting(.location, read: { try await $0.location() }, write: { try await $0.setLocation($1) })
        network = setting(
            .network,
            read: { try await $0.networkConditions() },
            write: { try await $0.setNetworkConditions($1) }
        )
        sensors = setting(
            .sensors,
            read: { try await $0.ambientSensors() },
            write: { controller, values in
                for (sensor, value) in values {
                    try await controller.setAmbientSensor(sensor, to: value)
                }
            }
        )
        brightness = setting(.display, read: { try await $0.brightness() }, write: { try await $0.setBrightness($1) })
        hostMicrophone = setting(
            .microphone,
            read: { try await $0.usesHostMicrophone() },
            write: { try await $0.setUsesHostMicrophone($1) }
        )
        clipboard = setting(.clipboard, read: { try await $0.clipboard() }, write: { try await $0.setClipboard($1) })
        display = LiveSetting(
            read: { [weak self] in
                guard let self else { throw CancellationError() }
                let metrics = try await displayController().displayMetrics()
                errors[.screenSize] = nil
                return metrics
            },
            write: { [weak self] metrics in
                guard let self else { return }
                try await displayController().setDisplayOverride(metrics.isOverridden ? metrics.current : nil)
                errors[.screenSize] = nil
            },
            report: { [weak self] in self?.show($0, in: .screenSize) }
        )
        customScreenPresets = Self.loadPresets(from: dependencies.preferences)
        snapshots = LiveSetting(
            read: { [weak self] in try await self?.snapshotManager().snapshots() ?? [] },
            write: { _ in },
            report: { [weak self] in self?.show($0, in: .snapshots) }
        )
    }

    var device: Device? { dependencies.repository.device(withID: deviceID) }

    var visibleSections: [SettingsSection] {
        guard let device else { return [] }
        return SettingsSection.allCases.filter { device.availability(of: $0.capability).isVisible }
    }

    func isExpanded(_ section: SettingsSection) -> Bool {
        expandedSections.contains(section)
    }

    func setExpanded(_ section: SettingsSection, _ expanded: Bool) {
        if expanded {
            expandedSections.insert(section)
        } else {
            expandedSections.remove(section)
        }
    }

    // MARK: - Partial updates

    func updateBattery(_ change: (inout BatteryState) -> Void) {
        guard var value = battery.value else { return }
        change(&value)
        Task { await battery.apply(value) }
    }

    func updateNetwork(_ change: (inout NetworkConditions) -> Void) {
        guard var value = network.value else { return }
        change(&value)
        Task { await network.apply(value) }
    }

    func setSensor(_ sensor: AmbientSensor, to value: Double) {
        guard var values = sensors.value else { return }
        values[sensor] = value
        Task { await sensors.apply(values) }
    }

    func setLocation(latitude: Double, longitude: Double, altitude: Double? = nil) {
        let current = location.value
        let target = GeoLocation(
            latitude: latitude,
            longitude: longitude,
            altitude: altitude ?? current?.altitude ?? 0
        )
        Task { await location.apply(target) }
    }

    // MARK: - Actions

    func phoneCall(_ action: PhoneCallAction) {
        let number = phoneNumber.trimmingCharacters(in: .whitespaces)
        Task { await perform(.telephony) { try await $0.phoneCall(action, number: number) } }
    }

    var canSendSMS: Bool {
        !smsText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !phoneNumber.trimmingCharacters(in: .whitespaces).isEmpty
    }

    func sendSMS() {
        guard canSendSMS else { return }
        let number = phoneNumber.trimmingCharacters(in: .whitespaces)
        let text = smsText
        Task {
            if await perform(.telephony, { try await $0.receiveSMS(from: number, text: text) }) {
                smsText = ""
            }
        }
    }

    func touchFingerprint() {
        let id = fingerprintID
        Task { await perform(.fingerprint) { try await $0.touchFingerprint(id: id) } }
    }

    func setPosture(_ newValue: FoldPosture) {
        let previous = posture
        posture = newValue
        Task {
            if await !perform(.posture, { try await $0.setPosture(newValue) }) {
                posture = previous
            }
        }
    }

    func sendClipboard(_ text: String) {
        Task { await clipboard.apply(text) }
    }

    // MARK: - Screen size

    /// Overrides the screen, or restores the physical one when `configuration` equals it or is `nil`.
    func applyDisplay(_ configuration: DisplayConfiguration?) {
        guard var metrics = display.value else { return }
        if let configuration, configuration != metrics.physical {
            if let problem = configuration.validationError {
                errors[.screenSize] = problem
                return
            }
            metrics.overrideSize = configuration.size
            metrics.overrideDensity = configuration.density
        } else {
            metrics.overrideSize = nil
            metrics.overrideDensity = nil
        }
        let target = metrics
        Task {
            busySections.insert(.screenSize)
            defer { busySections.remove(.screenSize) }
            await display.apply(target)
            // Pick up what the device settled on (it can round values).
            await display.load()
        }
    }

    func applyPreset(_ preset: ScreenPreset) {
        guard let physical = display.value?.physicalSize else { return }
        applyDisplay(preset.configuration(fitting: physical))
    }

    /// Saves a configuration as a named preset, measured in dp so it fits other screens too.
    func savePreset(named name: String, from configuration: DisplayConfiguration) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let dp = configuration.sizeDP
        customScreenPresets.removeAll { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }
        customScreenPresets.append(ScreenPreset(name: trimmed, widthDP: dp.width, heightDP: dp.height))
        storePresets()
    }

    func deletePreset(_ preset: ScreenPreset) {
        customScreenPresets.removeAll { $0 == preset }
        storePresets()
    }

    static let presetsKey = "settings.screenPresets"

    private static func loadPresets(from store: any KeyValueStore) -> [ScreenPreset] {
        guard let data = store.string(forKey: presetsKey)?.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([ScreenPreset].self, from: data)) ?? []
    }

    private func storePresets() {
        let data = try? JSONEncoder().encode(customScreenPresets)
        dependencies.preferences.set(data.map { String(decoding: $0, as: UTF8.self) }, forKey: Self.presetsKey)
    }

    // MARK: - Snapshots

    func snapshotNameError(_ name: String) -> String? {
        SnapshotName.validationError(for: name, existing: snapshots.value ?? [])
    }

    func saveSnapshot(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        runSnapshotAction("Saved “\(trimmed)”") { try await $0.saveSnapshot(named: trimmed) }
    }

    func loadSnapshot(_ snapshot: DeviceSnapshot) {
        runSnapshotAction("Loaded “\(snapshot.name)”") { try await $0.loadSnapshot(id: snapshot.id) }
    }

    func deleteSnapshot(_ snapshot: DeviceSnapshot) {
        runSnapshotAction("Deleted “\(snapshot.name)”") { try await $0.deleteSnapshot(id: snapshot.id) }
    }

    private func runSnapshotAction(
        _ message: String, _ operation: @escaping @MainActor (any SnapshotManaging) async throws -> Void
    ) {
        guard !busySections.contains(.snapshots) else { return }
        lastSnapshotAction = nil
        busySections.insert(.snapshots)
        Task {
            defer { busySections.remove(.snapshots) }
            do {
                try await operation(try snapshotManager())
                errors[.snapshots] = nil
                lastSnapshotAction = message
            } catch {
                show(error, in: .snapshots)
            }
            await snapshots.load()
        }
    }

    // MARK: - Errors

    func dismissError(in section: SettingsSection) {
        errors[section] = nil
    }

    private func show(_ error: any Error, in section: SettingsSection) {
        errors[section] = error.localizedDescription
    }

    // MARK: - Helpers

    private func controller() throws -> any DeviceSettingsControlling {
        guard let controller = dependencies.repository.session(for: deviceID) as? any DeviceSettingsControlling else {
            throw DeviceActionError.notSupported
        }
        return controller
    }

    private func displayController() throws -> any DisplayOverriding {
        guard let controller = dependencies.repository.inspector(for: deviceID) as? any DisplayOverriding else {
            throw DeviceActionError.notSupported
        }
        return controller
    }

    private func snapshotManager() throws -> any SnapshotManaging {
        guard let manager = dependencies.repository.session(for: deviceID) as? any SnapshotManaging else {
            throw DeviceActionError.notSupported
        }
        return manager
    }

    private func setting<Value: Equatable & Sendable>(
        _ section: SettingsSection,
        read: @escaping @MainActor (any DeviceSettingsControlling) async throws -> Value,
        write: @escaping @MainActor (any DeviceSettingsControlling, Value) async throws -> Void
    ) -> LiveSetting<Value> {
        LiveSetting(
            read: { [weak self] in
                guard let self else { throw CancellationError() }
                let value = try await read(try controller())
                errors[section] = nil
                return value
            },
            write: { [weak self] value in
                guard let self else { return }
                try await write(try controller(), value)
                errors[section] = nil
            },
            report: { [weak self] in self?.show($0, in: section) }
        )
    }

    /// Runs a device action and reports failures in the section. Returns whether it succeeded.
    @discardableResult
    private func perform(
        _ section: SettingsSection,
        _ operation: @MainActor (any DeviceSettingsControlling) async throws -> Void
    ) async -> Bool {
        busySections.insert(section)
        defer { busySections.remove(section) }
        do {
            try await operation(try controller())
            errors[section] = nil
            return true
        } catch {
            show(error, in: section)
            return false
        }
    }
}
