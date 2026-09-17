import AddEmulatorFeature
import ComponentsFeature
import DeviceDomain
import DeviceInfoFeature
import DeviceListFeature
import DeviceSettingsFeature
import DeviceWorkspaceFeature
import FilesFeature
import Foundation
import Observation
import OnboardingFeature
import ReportsFeature
import SDKDomain

/// App-level state and routing between features.
@MainActor
@Observable
final class AppModel {
    enum Phase {
        case launching
        case onboarding(OnboardingModel)
        case ready
    }

    enum InspectorTab: String, CaseIterable, Identifiable {
        case settings, reports, info, files

        var id: String { rawValue }

        var capability: Capability {
            switch self {
            case .settings: .settings
            case .reports: .reports
            case .info: .info
            case .files: .files
            }
        }
    }

    private(set) var phase: Phase = .launching
    var selection: DeviceID? {
        didSet {
            // Compact mode belongs to one device; leave it when the selection changes.
            if selection != oldValue, isCompact, let oldValue {
                workspaces[oldValue]?.exitCompact()
                isCompact = false
            }
        }
    }
    var newEmulator: AddEmulatorModel?
    var inspectorTab: InspectorTab = .settings
    var isInspectorVisible = true
    /// The window shrinks around the device.
    private(set) var isCompact = false

    let composition: AppComposition
    let deviceList: DeviceListModel
    @ObservationIgnored private var workspaces: [DeviceID: DeviceWorkspaceModel] = [:]
    @ObservationIgnored private var settings: [DeviceID: DeviceSettingsModel] = [:]
    @ObservationIgnored private var infos: [DeviceID: DeviceInfoModel] = [:]
    @ObservationIgnored private var files: [DeviceID: FilesModel] = [:]
    @ObservationIgnored private var reports: [DeviceID: ReportsModel] = [:]
    @ObservationIgnored private var components: ComponentsModel?
    /// Opens the Logcat window; set by the main window, which has the `openWindow` action.
    @ObservationIgnored var openLogcat: (DeviceID) -> Void = { _ in }

    init(composition: AppComposition) {
        self.composition = composition
        deviceList = composition.makeDeviceListModel()
    }

    // MARK: - Launch

    func launch() async {
        guard case .launching = phase else { return }
        let report = await composition.runSetupChecks()
        if !composition.isOnboardingCompleted || !report.isReady {
            showOnboarding()
        } else {
            await enterMainWindow()
        }
    }

    private func showOnboarding() {
        let model = composition.makeOnboardingModel(startAt: .sdk) { [weak self] completion in
            self?.completeOnboarding(completion)
        }
        phase = .onboarding(model)
    }

    private func completeOnboarding(_ completion: OnboardingDependencies.Completion) {
        composition.markOnboardingCompleted(skippedPlatformTools: completion.skippedPlatformTools)
        Task {
            await enterMainWindow()
            if completion.openNewEmulator {
                presentNewEmulator()
            }
        }
    }

    private func enterMainWindow() async {
        phase = .ready
        await composition.repository.reload()
        if selection == nil {
            selection = composition.repository.devices.first?.id
        }
    }

    // MARK: - Routing

    var isReady: Bool {
        if case .ready = phase { return true }
        return false
    }

    func presentNewEmulator() {
        guard isReady else { return }
        newEmulator = composition.makeAddEmulatorModel { [weak self] id in
            self?.newEmulator = nil
            self?.selection = id
        }
    }

    func workspace(for id: DeviceID) -> DeviceWorkspaceModel {
        if let existing = workspaces[id] { return existing }
        let model = composition.makeWorkspaceModel(for: id) { [weak self] compact in
            self?.isCompact = compact
        }
        workspaces[id] = model
        return model
    }

    func settings(for id: DeviceID) -> DeviceSettingsModel {
        if let existing = settings[id] { return existing }
        let model = composition.makeSettingsModel(for: id)
        settings[id] = model
        return model
    }

    func info(for id: DeviceID) -> DeviceInfoModel {
        let composition = composition
        return cached(&infos, id) { composition.makeDeviceInfoModel(for: $0) }
    }

    func files(for id: DeviceID) -> FilesModel {
        let composition = composition
        return cached(&files, id) { composition.makeFilesModel(for: $0) }
    }

    func reports(for id: DeviceID) -> ReportsModel {
        let composition = composition
        return cached(&reports, id) { id in
            composition.makeReportsModel(for: id) { [weak self] in self?.openLogcat($0) }
        }
    }

    private func cached<Model>(_ cache: inout [DeviceID: Model], _ id: DeviceID, make: (DeviceID) -> Model) -> Model {
        if let existing = cache[id] { return existing }
        let model = make(id)
        cache[id] = model
        return model
    }

    var componentsModel: ComponentsModel {
        if let components { return components }
        let model = composition.makeComponentsModel()
        components = model
        return model
    }

    /// Window sizes while the compact window is on.
    var compactLayout: CompactWindowLayout? {
        guard isCompact, let id = selection else { return nil }
        return workspace(for: id).compactLayout
    }

    var selectedDevice: Device? {
        selection.flatMap(composition.repository.device(withID:))
    }

    /// The inspector only exists while a device runs.
    var canShowInspector: Bool {
        !visibleInspectorTabs.isEmpty
    }

    /// Tabs the selected device offers, in display order.
    var visibleInspectorTabs: [InspectorTab] {
        guard let device = selectedDevice else { return [] }
        return InspectorTab.allCases.filter { device.availability(of: $0.capability).isVisible }
    }

    /// The chosen tab, or the first one the device offers.
    var effectiveInspectorTab: InspectorTab? {
        let tabs = visibleInspectorTabs
        return tabs.contains(inspectorTab) ? inspectorTab : tabs.first
    }

    func reloadDevices() async {
        await composition.repository.reload()
    }
}
