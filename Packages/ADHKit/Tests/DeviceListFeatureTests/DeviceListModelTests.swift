import ADHTestSupport
import DeviceDomain
import Foundation
import Testing

@testable import DeviceListFeature

@MainActor
struct DeviceListModelTests {
    @Test func sortsRunningFirstThenByName() {
        let repository = FakeDeviceRepository(devices: [
            .emulator(id: "b", name: "Beta"),
            .emulator(id: "z", name: "Zulu", state: .running(inAppControl: false)),
            .emulator(id: "a", name: "Alpha"),
        ])
        let model = DeviceListModel(repository: repository)
        #expect(model.visibleDevices.map(\.name) == ["Zulu", "Alpha", "Beta"])
    }

    @Test func searchesNameAndVersion() {
        let repository = FakeDeviceRepository(devices: [
            .emulator(id: "a", name: "Pixel 8", api: 36),
            .emulator(id: "b", name: "Tablet", api: 34),
        ])
        let model = DeviceListModel(repository: repository)

        model.searchText = "pixel"
        #expect(model.visibleDevices.map(\.name) == ["Pixel 8"])
        model.searchText = "Android 14"
        #expect(model.visibleDevices.map(\.name) == ["Tablet"])
        model.searchText = "API 36"
        #expect(model.visibleDevices.map(\.name) == ["Pixel 8"])
    }

    @Test func removalOnlyForAvailableDevices() {
        let running = Device.emulator(
            id: "r", state: .running(inAppControl: false),
            capabilities: [
                .remove: .disabled(reason: "Stop the device first.")
            ])
        let stopped = Device.emulator(id: "s")
        let model = DeviceListModel(repository: FakeDeviceRepository(devices: [running, stopped]))

        model.requestRemoval(of: running.id)
        #expect(model.actionRequest == nil)
        model.requestRemoval(of: stopped.id)
        #expect(model.actionRequest == .remove(stopped))
    }

    @Test func primaryActionStartsStoppedDevices() async throws {
        let repository = FakeDeviceRepository(devices: [.emulator(id: "s")])
        let model = DeviceListModel(repository: repository)
        model.primaryAction(for: .emulator(avdID: "s"))
        try await Task.sleep(for: .milliseconds(50))
        #expect(repository.started.map(\.0) == [.emulator(avdID: "s")])
    }

    @Test func presentsErrorsWithRecoverySuggestion() {
        struct Failure: LocalizedError {
            var errorDescription: String? { "It broke." }
            var recoverySuggestion: String? { "Try again." }
        }
        let model = DeviceListModel(repository: FakeDeviceRepository())
        model.show(Failure())
        #expect(model.errorMessage == "It broke. Try again.")
    }

    @Test func rowPresentationDescribesState() {
        let missing = Device.emulator(id: "m", state: .needsAttention(.missingSystemImage(sysdir: "x")))
        let presentation = DeviceRowPresentation(device: missing)
        #expect(presentation.status == .attention)
        #expect(presentation.subtitle == "Android 16 · System image not installed")
        #expect(DeviceRowPresentation(device: .emulator(id: "p")).subtitle == "Android 16 · Google Play")
    }
}
