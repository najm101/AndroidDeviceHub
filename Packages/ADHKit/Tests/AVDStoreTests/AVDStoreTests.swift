import ADHTestSupport
import Foundation
import Foundations
import SDKDomain
import Testing

@testable import AVDStore

struct IniDocumentTests {
    @Test func roundTripsRealConfigWithoutChanges() throws {
        let text = try String(contentsOf: Fixtures.url("avd/Pixel_9_Pro_XL.config.ini"), encoding: .utf8)
        let document = IniDocument(text: text)
        #expect(document.text == text)
        #expect(document.style == .spaced)
        #expect(document["hw.lcd.density"] == "480")
        #expect(document["fastboot.chosenSnapshotFile"] == "")
    }

    @Test func keepsOrderAndUnknownKeysWhenEditing() {
        var document = IniDocument(text: "# comment\nb=2\ncustom.key=kept\na=1\n")
        document["b"] = "3"
        document["new"] = "x"
        document["a"] = nil
        #expect(document.text == "# comment\nb=3\ncustom.key=kept\nnew=x\n")
        #expect(document.style == .compact)
    }

    @Test func parsesBooleansAndSizes() {
        let document = IniDocument(text: "a = yes\nb = false\n")
        #expect(document.bool("a") == true)
        #expect(document.bool("b") == false)
        #expect(SizeValue.bytes("512M") == Int64(536_870_912))
        #expect(SizeValue.bytes("6442450944") == Int64(6_442_450_944))
        #expect(SizeValue.bytes("2G") == Int64(2_147_483_648))
        #expect(SizeValue.bytes("abc") == nil)
    }
}

struct VirtualDeviceMapperTests {
    @Test func mapsStudioCreatedDevice() throws {
        let config = IniDocument(
            text: try String(contentsOf: Fixtures.url("avd/Pixel_9_Pro_XL.config.ini"), encoding: .utf8))
        let pointer = IniDocument(text: try String(contentsOf: Fixtures.url("avd/Pixel_9_Pro_XL.ini"), encoding: .utf8))
        let device = VirtualDeviceMapper.device(
            id: "Pixel_9_Pro_XL", config: config, pointer: pointer,
            directory: URL(filePath: "/avd/Pixel_9_Pro_XL.avd"), iniFile: URL(filePath: "/avd/Pixel_9_Pro_XL.ini"),
            sysdirExists: { _ in false }
        )
        #expect(device.displayName == "Pixel 9 Pro XL")
        #expect(device.apiLevel == APILevel(major: 36))
        #expect(device.hasPlayStore)
        #expect(device.services == .googlePlay)
        #expect(device.screenWidth == 1344)
        #expect(device.ramMiB == 2048)
        #expect(device.dataPartitionBytes == 6_442_450_944)
        #expect(
            device.issues == [.missingSystemImage(sysdir: "system-images/android-36/google_apis_playstore/arm64-v8a/")])
    }

    @Test func readsMinorAndExtensionPlatforms() {
        #expect(
            VirtualDeviceMapper.apiLevel(sysdir: "system-images/android-36.1/google_apis/arm64-v8a/", target: nil)
                == APILevel(major: 36, minor: 1))
        #expect(
            VirtualDeviceMapper.apiLevel(sysdir: "system-images/android-36-ext19/google_apis/arm64-v8a/", target: nil)
                == APILevel(major: 36))
        #expect(VirtualDeviceMapper.apiLevel(sysdir: nil, target: "android-34") == APILevel(major: 34))
        #expect(VirtualDeviceMapper.apiLevel(sysdir: "system-images/android-CANARY/x/y/", target: nil) == nil)
    }
}

struct AVDFileStoreTests {
    let store = AVDFileStore()

    func makeLocation(_ temp: TemporaryDirectory, withImage: Bool = true) throws -> SDKLocation {
        let location = SDKLocation(
            sdkRoot: temp.appending("sdk", isDirectory: true), sdkSource: .defaultLocation,
            avdHome: temp.appending("avd", isDirectory: true), avdSource: .defaultLocation
        )
        if withImage {
            try temp.write("", to: "sdk/system-images/android-36/google_apis_playstore/arm64-v8a/system.img")
        }
        return location
    }

    @Test func createsDeviceThatReadsBackCorrectly() async throws {
        let temp = try TemporaryDirectory()
        let location = try makeLocation(temp)

        let device = try await store.create(TestData.specification(), in: location)

        #expect(device.id == "Pixel_8_API_36")
        #expect(device.displayName == "Pixel 8 API 36")
        #expect(device.issues.isEmpty)
        #expect(device.apiLevel == APILevel(major: 36))
        #expect(device.hardwareProfileID == "pixel_8")
        #expect(device.hasPlayStore)

        let pointer = try String(contentsOf: location.avdHome.appending(path: "Pixel_8_API_36.ini"), encoding: .utf8)
        #expect(pointer.contains("path.rel=avd/Pixel_8_API_36.avd"))
        #expect(pointer.contains("target=android-36"))

        let config = IniDocument(
            text: try String(contentsOf: device.directory.appending(path: "config.ini"), encoding: .utf8))
        #expect(config["image.sysdir.1"] == "system-images/android-36/google_apis_playstore/arm64-v8a/")
        #expect(config["hw.cpu.arch"] == "arm64")
        #expect(config["tag.id"] == "google_apis_playstore")
        #expect(config["disk.dataPartition.size"] == "6442450944")
        #expect(config["hw.sdCard"] == "no")

        let listed = try await store.devices(in: location)
        #expect(listed.map(\.id) == ["Pixel_8_API_36"])
    }

    @Test func rejectsDuplicateNamesIgnoringCase() async throws {
        let temp = try TemporaryDirectory()
        let location = try makeLocation(temp)
        _ = try await store.create(TestData.specification(), in: location)

        var other = TestData.specification()
        other.id = "pixel_8_api_36"
        await #expect(throws: AVDStoreError.nameInUse("pixel_8_api_36")) {
            try await store.create(other, in: location)
        }
    }

    @Test func renameMovesFilesAndUpdatesPaths() async throws {
        let temp = try TemporaryDirectory()
        let location = try makeLocation(temp)
        let device = try await store.create(TestData.specification(), in: location)

        let renamed = try await store.rename(device, toDisplayName: "My Phone", in: location)

        #expect(renamed.id == "My_Phone")
        #expect(renamed.displayName == "My Phone")
        #expect(!FileManager.default.fileExists(atPath: device.directory.path(percentEncoded: false)))
        let pointer = try String(contentsOf: renamed.iniFile, encoding: .utf8)
        #expect(pointer.contains("path.rel=avd/My_Phone.avd"))
        #expect(try await store.devices(in: location).map(\.id) == ["My_Phone"])
    }

    @Test func renameKeepsIDWhenOnlyDisplayNameChanges() async throws {
        let temp = try TemporaryDirectory()
        let location = try makeLocation(temp)
        let device = try await store.create(TestData.specification(), in: location)

        let renamed = try await store.rename(device, toDisplayName: "Pixel 8 API 36 ", in: location)
        #expect(renamed.id == device.id)
    }

    @Test func duplicateCopiesConfigurationOnly() async throws {
        let temp = try TemporaryDirectory()
        let location = try makeLocation(temp)
        let device = try await store.create(TestData.specification(), in: location)
        try temp.write("data", to: "avd/Pixel_8_API_36.avd/userdata-qemu.img")

        let copy = try await store.duplicate(device, as: "Pixel 8 Copy", in: location)

        #expect(copy.id == "Pixel_8_Copy")
        #expect(copy.sysdir == device.sysdir)
        #expect(
            !FileManager.default.fileExists(
                atPath: copy.directory.appending(path: "userdata-qemu.img").path(percentEncoded: false)))
        #expect(try await store.devices(in: location).count == 2)
    }

    @Test func wipeRemovesUserDataButKeepsConfiguration() async throws {
        let temp = try TemporaryDirectory()
        let location = try makeLocation(temp)
        let device = try await store.create(TestData.specification(), in: location)
        for file in [
            "userdata-qemu.img.qcow2", "cache.img", "encryptionkey.img", "snapshots/default_boot/ram.bin",
            "multiinstance.lock",
        ] {
            try temp.write("x", to: "avd/Pixel_8_API_36.avd/\(file)")
        }

        try await store.wipeData(of: device)

        let remaining = try FileManager.default.contentsOfDirectory(
            atPath: device.directory.path(percentEncoded: false))
        #expect(remaining == ["config.ini"])
    }

    @Test func deleteRemovesFolderAndPointer() async throws {
        let temp = try TemporaryDirectory()
        let location = try makeLocation(temp)
        let device = try await store.create(TestData.specification(), in: location)

        try await store.delete(device, in: location)

        #expect(try await store.devices(in: location).isEmpty)
        #expect(!FileManager.default.fileExists(atPath: device.directory.path(percentEncoded: false)))
    }

    @Test func reportsMissingSystemImage() async throws {
        let temp = try TemporaryDirectory()
        let location = try makeLocation(temp, withImage: false)
        let device = try await store.create(TestData.specification(), in: location)
        #expect(
            device.issues == [.missingSystemImage(sysdir: "system-images/android-36/google_apis_playstore/arm64-v8a/")])
    }
}

enum TestData {
    static let pixel8 = HardwareProfile(
        id: "pixel_8", name: "Pixel 8", manufacturer: "Google", formFactor: .phone, playStore: true,
        diagonalInches: 6.17, widthPixels: 1080, heightPixels: 2400, density: 420, ramMiB: 7562, skin: "pixel_8"
    )

    static let android16PlayStore = SystemImageDetails(
        apiLevel: APILevel(major: 36), extensionLevel: 17, isBaseExtension: true, stage: .stable,
        tags: [ImageTag(id: "google_apis_playstore", display: "Google Play")],
        vendor: ImageTag(id: "google", display: "Google Inc."), abi: .arm64,
        platformFolder: "android-36", tagFolder: "google_apis_playstore"
    )

    static func specification() -> VirtualDeviceSpecification {
        VirtualDeviceSpecification(
            id: "Pixel_8_API_36", displayName: "Pixel 8 API 36", profile: pixel8, image: android16PlayStore,
            cpuCores: 4, ramMiB: 2048, vmHeapMiB: 256, internalStorageMiB: 6144, sdCardMiB: nil,
            orientation: .portrait, bootMode: .quick, graphics: .auto, useHostKeyboard: true,
            frontCamera: .emulated, backCamera: .virtualScene, networkSpeed: .full, networkLatency: .none,
            skinPath: nil
        )
    }
}
