import ADHTestSupport
import AVDStore
import DeviceDomain
import EmulatorRuntime
import Foundation
import HardwareProfiles
import SDKDomain
import Testing

@testable import DeviceControllers

@MainActor
struct LiveDeviceRepositoryTests {
    struct Profiles: HardwareProfileProviding {
        func profiles() -> [HardwareProfile] { [SampleData.pixel8] }
    }

    @MainActor
    final class Environment {
        let temp: TemporaryDirectory
        let context = SDKContext()
        let location: SDKLocation
        let running: URL

        init() throws {
            temp = try TemporaryDirectory()
            location = SDKLocation(
                sdkRoot: temp.appending("sdk", isDirectory: true), sdkSource: .defaultLocation,
                avdHome: temp.appending("avd", isDirectory: true), avdSource: .defaultLocation
            )
            running = temp.appending("running", isDirectory: true)
            try temp.write("", to: "sdk/system-images/android-36/google_apis_playstore/arm64-v8a/system.img")
            context.report = SetupReport(resolution: .found(location), checks: [])
        }

        func repository(alive: @escaping @Sendable (Int32) -> Bool = { _ in true }) -> LiveDeviceRepository {
            LiveDeviceRepository(
                context: context,
                avdStore: AVDFileStore(),
                profiles: Profiles(),
                discovery: EmulatorDiscovery(directory: running, isAlive: alive),
                launcher: EmulatorLauncher(logDirectory: temp.appending("logs", isDirectory: true)),
                frameDirectory: temp.appending("frames", isDirectory: true),
                reveal: { _ in }
            )
        }

        func specification(named name: String, api: Int = 36) -> VirtualDeviceSpecification {
            VirtualDeviceSpecification(
                id: VirtualDeviceName.id(fromDisplayName: name), displayName: name, profile: SampleData.pixel8,
                image: SampleData.image(api: api), cpuCores: 2, ramMiB: 2048, vmHeapMiB: 256,
                internalStorageMiB: 2048, sdCardMiB: nil, orientation: .portrait, bootMode: .quick,
                graphics: .auto, useHostKeyboard: true, frontCamera: .emulated, backCamera: .emulated,
                networkSpeed: .full, networkLatency: .none, skinPath: nil
            )
        }
    }

    @Test func createsAndListsDevices() async throws {
        let env = try Environment()
        let repository = env.repository()

        let id = try await repository.create(env.specification(named: "Pixel 8 API 36"))
        let device = try #require(repository.device(withID: id))

        #expect(device.state == .stopped)
        #expect(device.formFactor == .phone)
        #expect(device.versionSummary == "Android 16 · API 36")
        #expect(device.availability(of: .start) == .available)
        #expect(device.availability(of: .settings) == .hidden)
        #expect(device.availability(of: .zoom) == .disabled(reason: EmulatorCapabilities.startFirst))
    }

    @Test func marksMissingImages() async throws {
        let env = try Environment()
        let repository = env.repository()
        let id = try await repository.create(env.specification(named: "Old", api: 30))

        let device = try #require(repository.device(withID: id))
        #expect(
            device.state
                == .needsAttention(
                    .missingSystemImage(sysdir: "system-images/android-30/google_apis_playstore/arm64-v8a/")))
        #expect(device.availability(of: .start).isAvailable == false)
        #expect(device.availability(of: .remove) == .available)
    }

    @Test func detectsRunningEmulatorsAndLocksEditing() async throws {
        let env = try Environment()
        let repository = env.repository()
        let id = try await repository.create(env.specification(named: "Runner"))
        try env.temp.write("avd.id=Runner\nport.serial=5554\n", to: "running/pid_4242.ini")

        await repository.reload()
        let device = try #require(repository.device(withID: id))

        #expect(device.state == .running(inAppControl: false))
        #expect(device.availability(of: .rename) == .disabled(reason: EmulatorCapabilities.stopFirst))
        await #expect(throws: DeviceActionError.deviceIsRunning) {
            try await repository.remove(id)
        }
    }

    @Test func renameWipeAndRemove() async throws {
        let env = try Environment()
        let repository = env.repository()
        let id = try await repository.create(env.specification(named: "Phone"))

        try await repository.rename(id, to: "Work Phone")
        #expect(repository.devices.map(\.name) == ["Work Phone"])

        let renamed = DeviceID.emulator(avdID: "Work_Phone")
        try await repository.wipeData(renamed)
        let copy = try await repository.duplicate(renamed, as: "Work Phone Copy")
        #expect(repository.devices.count == 2)

        try await repository.remove(copy)
        try await repository.remove(renamed)
        #expect(repository.devices.isEmpty)
    }

    @Test func failedLaunchReturnsToStopped() async throws {
        let env = try Environment()
        let repository = env.repository()
        let id = try await repository.create(env.specification(named: "Phone"))

        await #expect(throws: EmulatorLaunchError.emulatorNotInstalled) {
            try await repository.start(id, option: .normal)
        }
        #expect(repository.device(withID: id)?.state == .stopped)
    }

    @Test func emptyWithoutSDK() async {
        let context = SDKContext()
        let repository = LiveDeviceRepository(
            context: context, avdStore: AVDFileStore(), profiles: Profiles(),
            discovery: EmulatorDiscovery(directory: URL(filePath: "/nonexistent")),
            launcher: EmulatorLauncher(logDirectory: URL(filePath: "/tmp")),
            frameDirectory: URL(filePath: "/tmp"), reveal: { _ in }
        )
        await repository.reload()
        #expect(repository.devices.isEmpty)
    }
}
