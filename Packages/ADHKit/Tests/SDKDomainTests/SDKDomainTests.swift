import ADHTestSupport
import Foundation
import SDKDomain
import Testing

struct APILevelTests {
    @Test(arguments: [
        ("36", APILevel(major: 36)),
        ("36.1", APILevel(major: 36, minor: 1)),
        ("36x", APILevel(major: 36)),
        (" 34 ", APILevel(major: 34)),
    ])
    func parsesCatalogValues(text: String, expected: APILevel) {
        #expect(APILevel(catalogValue: text) == expected)
    }

    @Test func rejectsGarbage() {
        #expect(APILevel(catalogValue: "CANARY") == nil)
        #expect(APILevel(catalogValue: "36.1.2") == nil)
    }

    @Test func namesAndroidVersions() {
        #expect(APILevel(major: 36).androidVersionTitle == "Android 16")
        #expect(APILevel(major: 32).androidVersionTitle == "Android 12L")
        #expect(APILevel(major: 99).androidVersionTitle == "API 99")
        #expect(APILevel(major: 36, minor: 1).description == "36.1")
        #expect(APILevel(major: 36, minor: 1) > APILevel(major: 36))
    }
}

struct PackageRevisionTests {
    @Test func comparesNumerically() {
        #expect(PackageRevision(string: "36.5.11")! < PackageRevision(string: "37.1")!)
        #expect(PackageRevision(major: 35, minor: 4, micro: 9) < PackageRevision(major: 35, minor: 4, micro: 10))
        #expect(PackageRevision(major: 37, preview: 1) < PackageRevision(major: 37))
        #expect(PackageRevision(string: "x") == nil)
    }
}

struct ImageServicesTests {
    @Test(arguments: [
        ("google_apis_playstore", ImageServices.googlePlay),
        ("google_apis_playstore_ps16k", .googlePlay),
        ("google_apis", .googleAPIs),
        ("google_atd", .googleAPIs),
        ("default", .plainAndroid),
        ("android-wear", .plainAndroid),
    ])
    func derivesFromTag(tag: String, expected: ImageServices) {
        #expect(ImageServices(tagID: tag) == expected)
    }
}

struct VirtualDeviceNameTests {
    @Test func buildsIDsFromDisplayNames() {
        #expect(VirtualDeviceName.id(fromDisplayName: "Pixel 8 API 36") == "Pixel_8_API_36")
        #expect(VirtualDeviceName.id(fromDisplayName: "  My  phone (2) ") == "My_phone_2")
        #expect(VirtualDeviceName.id(fromDisplayName: "Téléphone") == "T_l_phone")
        #expect(VirtualDeviceName.isValidID("Pixel_8.a-b"))
        #expect(!VirtualDeviceName.isValidID("with space"))
        #expect(!VirtualDeviceName.isValidID(""))
    }
}

struct HardwareCompatibilityTests {
    @Test func phoneRunsMobileImagesOnly() {
        #expect(SampleData.pixel8.supports(SampleData.image(api: 36)))
        #expect(!SampleData.pixel8.supports(SampleData.image(api: 36, tag: "android-wear", display: "Wear OS")))
    }

    @Test func profilesWithoutPlayStoreRejectPlayImages() {
        #expect(!SampleData.smallPhone.supports(SampleData.image(api: 36)))
        #expect(SampleData.smallPhone.supports(SampleData.image(api: 36, tag: "google_apis", display: "Google APIs")))
    }

    @Test func wearRunsWearImagesOnly() {
        #expect(SampleData.wearRound.supports(SampleData.image(api: 36, tag: "android-wear", display: "Wear OS")))
        #expect(!SampleData.wearRound.supports(SampleData.image(api: 36)))
    }
}

struct SystemImageEntryTests {
    @Test func mergesRemoteAndInstalledNewestFirst() {
        let old = SampleData.remotePackage(for: SampleData.image(api: 34))
        let new = SampleData.remotePackage(for: SampleData.image(api: 36))
        let preview = SampleData.remotePackage(
            for: SampleData.image(api: 36, stage: .beta(number: 1, targetLevel: nil)))
        let installedOnly = LocalPackage(
            path: "system-images;android-30;default;arm64-v8a", displayName: "Old", revision: .init(major: 1),
            kind: .systemImage(SampleData.image(api: 30, tag: "default", display: "Default")),
            directory: URL(filePath: "/sdk/x")
        )
        let installedNew = LocalPackage(
            path: new.path, displayName: new.displayName, revision: new.revision, kind: new.kind,
            directory: URL(filePath: "/sdk/y")
        )

        let merged = SystemImageEntry.merge(remote: [old, preview, new], installed: [installedOnly, installedNew])

        #expect(merged.map(\.details.apiLevel.major) == [36, 36, 34, 30])
        #expect(merged.first?.isInstalled == true)
        #expect(merged.first?.details.stage == .stable)
        #expect(merged.last?.remote == nil)
    }

    @Test func picksNewestRevisionPerPath() {
        var first = SampleData.remotePackage(for: SampleData.image(api: 36))
        var second = first
        first.revision = PackageRevision(major: 5)
        second.revision = PackageRevision(major: 7)
        let merged = SystemImageEntry.merge(remote: [first, second], installed: [])
        #expect(merged.count == 1)
        #expect(merged.first?.remote?.revision.major == 7)
    }

    @Test func selectsLatestStablePackage() {
        var stable = SampleData.remotePackage(for: SampleData.image(api: 36))
        stable.revision = PackageRevision(major: 36)
        var canary = stable
        canary.revision = PackageRevision(major: 37)
        canary.channel = .canary
        #expect([stable, canary].latest(path: stable.path)?.revision.major == 36)
        #expect([stable, canary].latest(path: stable.path, upTo: .canary)?.revision.major == 37)
    }
}
