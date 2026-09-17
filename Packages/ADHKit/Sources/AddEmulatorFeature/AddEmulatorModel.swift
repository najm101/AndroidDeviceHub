public import DeviceDomain
public import Foundation
public import Observation
public import SDKDomain

/// Dependencies of the New Emulator dialog, wired by the app.
@MainActor
public struct AddEmulatorDependencies {
    public var profiles: [HardwareProfile]
    public var systemImages: @Sendable (_ forceRefresh: Bool) async throws -> [SystemImageEntry]
    /// The installed skin folder for a profile, if any.
    public var skinFolder: @Sendable (_ skinName: String) -> URL?
    public var repository: any DeviceRepository
    public var installs: any InstallCoordinating
    public var hostCPUCount: Int
    public var defaultBootMode: BootMode

    public init(
        profiles: [HardwareProfile],
        systemImages: @escaping @Sendable (Bool) async throws -> [SystemImageEntry],
        skinFolder: @escaping @Sendable (String) -> URL?,
        repository: any DeviceRepository,
        installs: any InstallCoordinating,
        hostCPUCount: Int = ProcessInfo.processInfo.activeProcessorCount,
        defaultBootMode: BootMode = .quick
    ) {
        self.profiles = profiles
        self.systemImages = systemImages
        self.skinFolder = skinFolder
        self.repository = repository
        self.installs = installs
        self.hostCPUCount = hostCPUCount
        self.defaultBootMode = defaultBootMode
    }
}

/// State of the two-step New Emulator dialog.
@MainActor
@Observable
public final class AddEmulatorModel: Identifiable {
    public enum Step: Int, CaseIterable, Sendable {
        case hardware
        case configure
    }

    public enum ConfigureTab: Hashable, Sendable {
        case device
        case additionalSettings
    }

    enum ImagesState: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    // Navigation
    var step: Step = .hardware
    var configureTab: ConfigureTab = .device

    // Step 1
    var formFactor: FormFactor = .phone
    var hardwareSearch = ""
    var selectedProfileID: HardwareProfile.ID? {
        didSet { if selectedProfileID != oldValue { profileChanged() } }
    }

    // Step 2 – device
    var name = "" {
        didSet { if !isApplyingDefaults { nameWasEdited = true } }
    }
    var services: ImageServices = .googlePlay {
        didSet { if services != oldValue { selectDefaultAPILevel() } }
    }
    var showSixteenKBImages = false {
        didSet { if showSixteenKBImages != oldValue { selectDefaultAPILevel() } }
    }
    var showPreviewImages = false {
        didSet { if showPreviewImages != oldValue { selectDefaultAPILevel() } }
    }
    var selectedAPI: APIChoice? {
        didSet { if selectedAPI != oldValue { selectDefaultImage() } }
    }
    var selectedImagePath: SystemImageEntry.ID? {
        didSet { if selectedImagePath != oldValue { applyDefaultName() } }
    }
    private(set) var images: [SystemImageEntry] = []
    private(set) var imagesState: ImagesState = .loading

    // Step 2 – additional settings
    var cpuCores = 4
    var ramMiB = 2048
    var vmHeapMiB = 256
    var internalStorageGiB = 6
    var hasSDCard = false
    var sdCardMiB = 512
    var orientation: Orientation = .portrait
    var bootMode: BootMode = .quick
    var graphics: GraphicsMode = .auto
    var useHostKeyboard = true
    var frontCamera: CameraMode = .emulated
    var backCamera: CameraMode = .virtualScene
    var networkSpeed: NetworkSpeed = .full
    var networkLatency: NetworkLatency = .none
    var startAfterCreating = false

    // Finish
    private(set) var isCreating = false
    var errorMessage: String?

    let dependencies: AddEmulatorDependencies
    private let onFinished: (DeviceID) -> Void
    @ObservationIgnored private(set) var nameWasEdited = false
    @ObservationIgnored private var isApplyingDefaults = false

    public init(dependencies: AddEmulatorDependencies, onFinished: @escaping (DeviceID) -> Void) {
        self.dependencies = dependencies
        self.onFinished = onFinished
        cpuCores = min(4, max(1, dependencies.hostCPUCount / 2))
        bootMode = dependencies.defaultBootMode
        selectedProfileID = visibleProfiles.first?.id
        profileChanged()
    }

    var installs: any InstallCoordinating { dependencies.installs }

    // MARK: - Step 1

    var visibleProfiles: [HardwareProfile] {
        let query = hardwareSearch.trimmingCharacters(in: .whitespaces)
        return dependencies.profiles.filter { profile in
            profile.formFactor == formFactor
                && (query.isEmpty
                    || profile.name.localizedStandardContains(query)
                    || profile.manufacturer.localizedStandardContains(query))
        }
    }

    var availableFormFactors: [FormFactor] {
        FormFactor.allCases.filter { factor in dependencies.profiles.contains { $0.formFactor == factor } }
    }

    var selectedProfile: HardwareProfile? {
        selectedProfileID.flatMap { id in dependencies.profiles.first { $0.id == id } }
    }

    func selectFormFactor(_ factor: FormFactor) {
        formFactor = factor
        if selectedProfile?.formFactor != factor {
            selectedProfileID = visibleProfiles.first?.id
        }
    }

    // MARK: - Step 2: images

    func loadImages(forceRefresh: Bool = false) async {
        imagesState = .loading
        do {
            images = try await dependencies.systemImages(forceRefresh)
            imagesState = .loaded
            if !apiChoices.contains(where: { $0 == selectedAPI }) {
                selectDefaultAPILevel()
            }
        } catch {
            imagesState = .failed(error.localizedDescription)
        }
    }

    /// Called when an install finishes, so the "Installed" state refreshes.
    func inventoryChanged() async {
        let selection = selectedImagePath
        await loadImages()
        selectedImagePath = selection
    }

    // MARK: - Navigation

    func goForward() {
        guard canContinue else { return }
        step = .configure
        if case .loading = imagesState, images.isEmpty {
            Task { await loadImages() }
        }
    }

    func goBack() {
        step = .hardware
    }

    func finish() async {
        guard canFinish, let profile = selectedProfile, let image = selectedImage else { return }
        isCreating = true
        defer { isCreating = false }
        let displayName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let specification = VirtualDeviceSpecification(
            id: VirtualDeviceName.id(fromDisplayName: displayName),
            displayName: displayName,
            profile: profile,
            image: image.details,
            cpuCores: cpuCores,
            ramMiB: ramMiB,
            vmHeapMiB: vmHeapMiB,
            internalStorageMiB: internalStorageGiB * 1024,
            sdCardMiB: hasSDCard ? sdCardMiB : nil,
            orientation: orientation,
            bootMode: bootMode,
            graphics: graphics,
            useHostKeyboard: useHostKeyboard,
            frontCamera: frontCamera,
            backCamera: backCamera,
            networkSpeed: networkSpeed,
            networkLatency: networkLatency,
            skinPath: profile.skin.flatMap(dependencies.skinFolder)
        )
        do {
            let id = try await dependencies.repository.create(specification)
            if startAfterCreating, imageStatus == .installed {
                try await dependencies.repository.start(id, option: bootMode == .cold ? .coldBoot : .normal)
            }
            onFinished(id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Defaults

    /// Runs `apply` without marking the name as edited by the user.
    func withDefaults(_ apply: () -> Void) {
        isApplyingDefaults = true
        apply()
        isApplyingDefaults = false
    }
}
