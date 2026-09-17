import ADHTestSupport
import DeviceDomain
import Foundation
import Foundations
import Testing

@testable import DeviceSettingsFeature

@MainActor
struct DeviceSettingsModelTests {
    struct Failure: LocalizedError {
        var errorDescription: String? { "Radio off" }
    }

    let id = DeviceID.emulator(avdID: "Pixel")
    let session: FakeSettingsSession
    let repository: FakeDeviceRepository
    let model: DeviceSettingsModel

    init() {
        session = FakeSettingsSession(deviceID: id)
        let running: [Capability: Availability] = [
            .settings: .available, .location: .available, .battery: .available, .network: .available,
            .telephony: .available, .snapshots: .available,
        ]
        repository = FakeDeviceRepository(devices: [
            .emulator(id: "Pixel", state: .running(inAppControl: true), capabilities: running)
        ])
        repository.sessions[id] = session
        model = DeviceSettingsModel(deviceID: id, dependencies: DeviceSettingsDependencies(repository: repository))
    }

    /// Lets the tasks the model starts run to completion.
    func settle() async {
        for _ in 0..<50 { await Task.yield() }
    }

    @Test func appliesPresetsAndResetsTheScreen() async throws {
        let inspector = FakeInspector()
        repository.inspectors[id] = inspector
        await model.display.load()

        model.applyPreset(ScreenPreset(name: "Tablet", widthDP: 800, heightDP: 1280))
        await settle()
        #expect(inspector.log.suffix(2) == ["wm 1080x1728@216", "wm"])
        #expect(model.display.value?.current.sizeDP == PixelSize(width: 800, height: 1280))

        model.applyDisplay(try #require(model.display.value).physical)
        await settle()
        #expect(inspector.log.suffix(2) == ["wm reset", "wm"])
        #expect(model.display.value?.isOverridden == false)

        model.applyDisplay(DisplayConfiguration(size: PixelSize(width: 10, height: 10), density: 420))
        #expect(model.errors[.screenSize] != nil)
    }

    @Test func savesPresetsInDP() {
        let preferences = InMemoryKeyValueStore()
        let model = DeviceSettingsModel(
            deviceID: id, dependencies: DeviceSettingsDependencies(repository: repository, preferences: preferences)
        )
        let configuration = DisplayConfiguration(size: PixelSize(width: 1600, height: 2560), density: 320)
        model.savePreset(named: " Kiosk ", from: configuration)
        model.savePreset(named: "kiosk", from: configuration)
        #expect(model.customScreenPresets == [ScreenPreset(name: "kiosk", widthDP: 800, heightDP: 1280)])

        let reloaded = DeviceSettingsModel(
            deviceID: id, dependencies: DeviceSettingsDependencies(repository: repository, preferences: preferences)
        )
        #expect(reloaded.customScreenPresets == model.customScreenPresets)
        reloaded.deletePreset(reloaded.customScreenPresets[0])
        #expect(reloaded.customScreenPresets.isEmpty)
    }

    @Test func showsOnlySectionsTheDeviceSupports() {
        #expect(model.visibleSections == [.location, .battery, .network, .telephony, .snapshots])
    }

    @Test func hidesEverythingWhenTheDeviceStops() {
        repository.devices = [.emulator(id: "Pixel")]
        #expect(model.visibleSections.isEmpty)
    }

    @Test func loadsAndAppliesBattery() async {
        await model.battery.load()
        #expect(model.battery.value?.level == 80)

        model.updateBattery { $0.level = 15 }
        await settle()
        #expect(session.batteryState.level == 15)
        #expect(model.battery.value?.level == 15)
    }

    @Test func restoresTheOldValueWhenTheDeviceRejectsIt() async {
        await model.battery.load()
        session.error = Failure()
        model.updateBattery { $0.charger = .usb }
        await settle()
        #expect(model.battery.value?.charger == .ac)
        #expect(model.errors[.battery] == "Radio off")

        session.error = nil
        await model.battery.load()
        #expect(model.errors[.battery] == nil)
    }

    @Test func reportsMissingSessions() async {
        repository.sessions[id] = nil
        await model.location.load()
        #expect(model.location.value == nil)
        #expect(model.errors[.location] == DeviceActionError.notSupported.errorDescription)
    }

    @Test func movesTheDeviceAndKeepsAltitude() async {
        await model.location.load()
        model.setLocation(latitude: 30.04, longitude: 31.24)
        await settle()
        #expect(session.geoLocation == GeoLocation(latitude: 30.04, longitude: 31.24, altitude: 5))
    }

    @Test func changesNetworkConditions() async {
        await model.network.load()
        model.updateNetwork { $0.speed = .edge }
        await settle()
        #expect(session.network.speed == .edge)
        #expect(session.network.latency == .none)
    }

    @Test func updatesOneSensor() async {
        await model.sensors.load()
        model.setSensor(.temperature, to: 31)
        await settle()
        #expect(session.sensors == [.temperature: 31, .light: 100])
    }

    @Test func sendsSMSAndClearsTheText() async {
        model.phoneNumber = "5551234"
        model.smsText = "Hello"
        #expect(model.canSendSMS)
        model.sendSMS()
        await settle()
        #expect(session.messages.map(\.1) == ["Hello"])
        #expect(model.smsText.isEmpty)
    }

    @Test func keepsTheSMSTextWhenSendingFails() async {
        session.error = Failure()
        model.smsText = "Hello"
        model.sendSMS()
        await settle()
        #expect(model.smsText == "Hello")
        #expect(model.errors[.telephony] == "Radio off")
    }

    @Test func placesCalls() async {
        model.phoneNumber = " 5551234 "
        model.phoneCall(.call)
        await settle()
        #expect(session.calls.map(\.1) == ["5551234"])
        #expect(!model.busySections.contains(.telephony))
    }

    @Test func revertsPostureOnFailure() async {
        model.setPosture(.halfOpened)
        await settle()
        #expect(model.posture == .halfOpened)

        session.error = Failure()
        model.setPosture(.closed)
        await settle()
        #expect(model.posture == .halfOpened)
        #expect(session.postures == [.halfOpened])
    }

    @Test func savesAndDeletesSnapshots() async throws {
        await model.snapshots.load()
        #expect(model.snapshots.value == [])

        model.saveSnapshot(named: " before-login ")
        await settle()
        let saved = try #require(model.snapshots.value?.first)
        #expect(saved.id == "before-login")
        #expect(model.lastSnapshotAction == "Saved “before-login”")
        #expect(model.snapshotNameError("Before-Login") != nil)

        model.deleteSnapshot(saved)
        await settle()
        #expect(model.snapshots.value == [])
        #expect(!model.busySections.contains(.snapshots))
    }

    @Test func validatesSnapshotNames() {
        #expect(model.snapshotNameError("") == "Enter a name.")
        #expect(model.snapshotNameError("a/b") != nil)
        #expect(model.snapshotNameError("snap_2026-09-17 10.00") == nil)
    }
}
