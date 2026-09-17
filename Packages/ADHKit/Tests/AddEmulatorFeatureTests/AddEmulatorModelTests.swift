import ADHTestSupport
import DeviceDomain
import Foundation
import SDKDomain
import Testing

@testable import AddEmulatorFeature

@MainActor
struct AddEmulatorModelTests {
    let repository = FakeDeviceRepository()
    let installs = FakeInstallCoordinator()

    func makeModel(
        profiles: [HardwareProfile] = [SampleData.pixel8, SampleData.smallPhone, SampleData.wearRound],
        images: [SystemImageEntry],
        onFinished: @escaping (DeviceID) -> Void = { _ in }
    ) -> AddEmulatorModel {
        AddEmulatorModel(
            dependencies: AddEmulatorDependencies(
                profiles: profiles,
                systemImages: { _ in images },
                skinFolder: { _ in nil },
                repository: repository,
                installs: installs,
                hostCPUCount: 10,
                defaultBootMode: .cold
            ),
            onFinished: onFinished
        )
    }

    static let catalog: [SystemImageEntry] = [
        SampleData.entry(SampleData.image(api: 36), installed: true),
        SampleData.entry(SampleData.image(api: 35), installed: false),
        SampleData.entry(SampleData.image(api: 36, tag: "google_apis", display: "Google APIs"), installed: false),
        SampleData.entry(SampleData.image(api: 36, tag: "google_apis_playstore_ps16k"), installed: false),
        SampleData.entry(SampleData.image(api: 37, stage: .beta(number: 2, targetLevel: nil)), installed: false),
        SampleData.entry(SampleData.image(api: 36, tag: "android-wear", display: "Wear OS"), installed: false),
    ]

    @Test func startsWithFirstPhoneAndDefaults() {
        let model = makeModel(images: Self.catalog)
        #expect(model.step == .hardware)
        #expect(model.selectedProfile?.id == "pixel_8")
        #expect(model.cpuCores == 4)
        #expect(model.bootMode == .cold)
        #expect(model.ramMiB == 2048)
    }

    @Test func choosesNewestInstalledImageAndNamesTheDevice() async {
        let model = makeModel(images: Self.catalog)
        model.goForward()
        await model.loadImages()

        #expect(model.step == .configure)
        #expect(model.selectedAPI?.level == APILevel(major: 36))
        #expect(model.selectedImage?.isInstalled == true)
        #expect(model.name == "Pixel 8 API 36")
        #expect(model.imageStatus == .installed)
        #expect(model.canFinish)
    }

    @Test func filtersBySevicesPageSizeAndPreviews() async {
        let model = makeModel(images: Self.catalog)
        await model.loadImages()

        #expect(model.apiChoices.map(\.level.major) == [36, 35])

        model.showPreviewImages = true
        #expect(model.apiChoices.map(\.level.major) == [37, 36, 35])

        model.showPreviewImages = false
        model.showSixteenKBImages = true
        #expect(model.compatibleImages.allSatisfy { $0.details.usesSixteenKBPages })

        model.showSixteenKBImages = false
        model.services = .googleAPIs
        #expect(model.compatibleImages.map(\.details.tagFolder) == ["google_apis"])
        #expect(model.selectedImage?.details.tagFolder == "google_apis")
    }

    @Test func hidesPlayStoreForProfilesWithoutIt() {
        let model = makeModel(images: Self.catalog)
        model.selectedProfileID = "small_phone"
        #expect(!model.availableServices.contains(.googlePlay))
        #expect(model.services == .googleAPIs)
    }

    @Test func wearProfilesOnlyOfferWearImages() async {
        let model = makeModel(images: Self.catalog)
        model.selectFormFactor(.wear)
        await model.loadImages()
        #expect(model.selectedProfile?.id == "wearos_large_round")
        #expect(model.compatibleImages.map(\.details.tagFolder) == ["android-wear"])
    }

    @Test func requiresAnInstalledOrDownloadingImage() async throws {
        let model = makeModel(images: Self.catalog)
        await model.loadImages()
        model.selectedAPI = model.apiChoices.first { $0.level.major == 35 }

        #expect(model.imageStatus == .notInstalled)
        #expect(!model.canFinish)

        let path = try #require(model.selectedImagePath)
        installs.install(SampleData.remotePackage(for: SampleData.image(api: 35)))
        #expect(installs.activeInstalls[path] != nil)
        #expect(model.imageStatus == .downloading)
        #expect(model.canFinish)
    }

    @Test func keepsEditedNamesAndRejectsDuplicates() async {
        repository.devices = [.emulator(id: "Pixel_8_API_36", name: "Pixel 8 API 36")]
        let model = makeModel(images: Self.catalog)
        await model.loadImages()

        #expect(model.name == "Pixel 8 API 36 (2)")

        model.name = "pixel 8 api 36"
        #expect(model.nameProblem != nil)
        model.name = "Work Phone"
        #expect(model.nameProblem == nil)

        model.selectedAPI = model.apiChoices.first { $0.level.major == 35 }
        #expect(model.name == "Work Phone")
    }

    @Test func finishCreatesTheSpecification() async throws {
        var finished: DeviceID?
        let model = makeModel(images: Self.catalog) { finished = $0 }
        await model.loadImages()
        model.hasSDCard = true
        model.internalStorageGiB = 8
        model.startAfterCreating = true

        await model.finish()

        let spec = try #require(repository.created.first)
        #expect(spec.id == "Pixel_8_API_36")
        #expect(spec.profile.id == "pixel_8")
        #expect(spec.image.apiLevel.major == 36)
        #expect(spec.internalStorageMiB == 8 * 1024)
        #expect(spec.sdCardMiB == 512)
        #expect(spec.bootMode == .cold)
        #expect(finished == .emulator(avdID: "Pixel_8_API_36"))
        #expect(repository.started.first?.1 == .coldBoot)
    }

    @Test func finishShowsErrors() async {
        repository.error = DeviceActionError.invalidName("Bad name")
        let model = makeModel(images: Self.catalog)
        await model.loadImages()
        await model.finish()
        #expect(model.errorMessage == "Bad name")
    }

    @Test func reportsCatalogFailures() async {
        struct Offline: Error {}
        let model = AddEmulatorModel(
            dependencies: AddEmulatorDependencies(
                profiles: [SampleData.pixel8], systemImages: { _ in throw Offline() }, skinFolder: { _ in nil },
                repository: repository, installs: installs
            ),
            onFinished: { _ in }
        )
        await model.loadImages()
        guard case .failed = model.imagesState else {
            Issue.record("Expected failure state")
            return
        }
    }
}
