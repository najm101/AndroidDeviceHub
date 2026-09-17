import ADHTestSupport
import DeviceDomain
import DeviceInfoFeature
import FilesFeature
import Foundation
import ReportsFeature
import Testing

@testable import DeviceInfoFeature
@testable import FilesFeature
@testable import ReportsFeature

@MainActor
struct InspectorFeaturesTests {
    let id = DeviceID.emulator(avdID: "Pixel")
    let inspector = FakeInspector()
    let repository: FakeDeviceRepository

    init() {
        let tabs: [Capability: Availability] = [
            .info: .available, .apps: .available, .profiles: .available, .files: .available, .reports: .available,
        ]
        repository = FakeDeviceRepository(devices: [
            .emulator(id: "Pixel", state: .running(inAppControl: true), capabilities: tabs)
        ])
        repository.inspectors[id] = inspector
    }

    func settle() async {
        for _ in 0..<100 { await Task.yield() }
    }

    // MARK: - Info

    @Test func infoLoadsPropertiesAndFiltersApps() async {
        let model = DeviceInfoModel(deviceID: id, dependencies: DeviceInfoDependencies(repository: repository))
        await model.loadInfo()
        #expect(model.properties.first?.properties.first?.value == "Pixel")

        await model.loadApps()
        #expect(model.visibleApps.map(\.packageName) == ["com.example.app"])
        model.appFilter = .all
        model.appSearch = "SETTINGS"
        #expect(model.visibleApps.map(\.packageName) == ["com.android.settings"])

        await model.loadLabel(for: model.apps[1])
        await model.loadLabel(for: model.apps[1])
        #expect(model.labels == ["com.example.app": "Example"])
        #expect(inspector.log.filter { $0.hasPrefix("label") }.count == 1)
        model.appSearch = "exam"
        #expect(model.visibleApps.map(\.packageName) == ["com.example.app"])
    }

    @Test func installReportsProgressAndReloads() async {
        let model = DeviceInfoModel(deviceID: id, dependencies: DeviceInfoDependencies(repository: repository))
        model.install([URL(filePath: "/tmp/notes.txt")])
        #expect(model.errorMessage != nil)

        model.errorMessage = nil
        model.install([URL(filePath: "/tmp/app.apk")])
        await settle()
        #expect(inspector.log.contains("install app.apk 0"))
        #expect(model.installs.isEmpty)
        #expect(model.statusMessage == "Installed app.apk")
        #expect(model.apps.contains { $0.packageName == "com.new.app" })
    }

    @Test func appActionsAndFailures() async {
        let model = DeviceInfoModel(deviceID: id, dependencies: DeviceInfoDependencies(repository: repository))
        await model.loadApps()
        let app = model.apps[1]
        model.uninstall(app)
        await settle()
        #expect(inspector.log.contains("uninstall com.example.app"))
        #expect(!model.apps.contains(app))

        inspector.error = FakeInspector.Failure("No activity")
        model.launch(model.apps[0])
        await settle()
        #expect(model.errorMessage == "No activity")
        #expect(model.busyApps.isEmpty)
    }

    @Test func profiles() async {
        let model = DeviceInfoModel(deviceID: id, dependencies: DeviceInfoDependencies(repository: repository))
        await model.loadUsers()
        #expect(model.users?.users.count == 1)
        #expect(!model.canRemove(model.users!.users[0]))

        model.createUser(named: "  Guest ")
        await settle()
        #expect(inspector.log.contains("create Guest"))
        #expect(model.users?.users.map(\.name) == ["Owner", "Guest"])
        #expect(model.canRemove(model.users!.users[1]))
    }

    @Test func unavailableTabsExplainWhy() async {
        repository.devices[0].capabilities[.apps] = .disabled(reason: InspectorHint.installPlatformTools)
        repository.inspectors[id] = nil
        let model = DeviceInfoModel(deviceID: id, dependencies: DeviceInfoDependencies(repository: repository))
        #expect(model.availability(of: .apps).reason == InspectorHint.installPlatformTools)
        model.page = .apps
        await model.loadApps()
        #expect(model.errorMessage == InspectorHint.installPlatformTools)
    }

    // MARK: - Files

    func filesModel() -> FilesModel {
        FilesModel(deviceID: id, dependencies: FilesDependencies(repository: repository, reveal: { _ in }))
    }

    @Test func browsesFolders() async {
        let model = filesModel()
        await model.loadInitialFolder()
        #expect(model.currentPath == "/")
        #expect(model.entries.map(\.name) == ["sdcard"])

        model.activate(model.entries[0])
        await settle()
        #expect(model.currentPath == "/sdcard")
        #expect(model.breadcrumbs == ["/", "/sdcard"])
        #expect(model.entries.map(\.name) == ["a.txt"])

        model.open("/data")
        await settle()
        #expect(model.entries.isEmpty)
        #expect(model.folderError == "Requires root.")

        model.openParent()
        await settle()
        #expect(model.currentPath == "/")
        #expect(model.folderError == nil)
    }

    @Test func folderChangesAndTransfers() async {
        let model = filesModel()
        await model.loadInitialFolder()
        #expect(model.nameError("sdcard") != nil)
        #expect(model.nameError("new") == nil)

        model.makeFolder(named: "new")
        await settle()
        #expect(model.entries.map(\.name) == ["sdcard", "new"])

        model.upload([URL(filePath: "/tmp/photo.png")])
        await settle()
        #expect(inspector.log.contains("upload photo.png /"))
        #expect(model.transfers.isEmpty)
        #expect(model.entries.contains { $0.name == "photo.png" })

        model.download([model.entries[0]], into: URL(filePath: "/tmp"))
        await settle()
        #expect(model.lastDownload == URL(filePath: "/tmp/sdcard"))

        model.selection = [model.entries[1].id]
        model.delete(model.selectedFiles)
        await settle()
        #expect(inspector.log.contains("delete /new"))
        #expect(model.selection.isEmpty)
    }

    // MARK: - Reports

    func reportsModel(opened: @escaping @MainActor (DeviceID) -> Void = { _ in }) -> ReportsModel {
        ReportsModel(
            deviceID: id,
            dependencies: ReportsDependencies(
                repository: repository, outputFolder: { URL(filePath: "/tmp") }, reveal: { _ in },
                openLogcat: opened))
    }

    @Test func crashesCanBeClearedAndShownAgain() async {
        inspector.reports = [
            CrashReport(id: "a", kind: .appCrash, tag: "data_app_crash", date: .now, process: "com.a", text: "x"),
            CrashReport(
                id: "b", kind: .appNotResponding, tag: "data_app_anr", date: .now - 60, process: "com.b", text: "y"),
        ]
        let model = reportsModel()
        await model.load()
        #expect(model.visibleReports.count == 2)
        model.clear()
        #expect(model.visibleReports.isEmpty)
        #expect(model.hiddenCount == 2)
        model.showAll()
        #expect(model.visibleReports.count == 2)
        #expect(model.exportText(for: model.visibleReports).contains("data_app_anr com.b"))
        #expect(ReportsModel.exportFileName(for: model.reports[0]).hasPrefix("com.a-"))
    }

    @Test func bugReportAndLogcat() async {
        var opened: [DeviceID] = []
        let model = reportsModel { opened.append($0) }
        model.openLogcat()
        #expect(opened == [id])

        model.startBugReport()
        await settle()
        #expect(model.bugReport == .finished(URL(filePath: "/tmp/bugreport.zip")))
    }

    @Test func logcatFilters() async {
        inspector.installedApps[1].uid = 10190
        inspector.logBatches = [
            [.sample(1, level: .debug, message: "boot"), .sample(2, level: .error, tag: "App", uid: 10190)],
            [.sample(3, level: .warning, message: "Disk low"), .sample(4, level: .info, uid: 1_010_190)],
        ]
        let model = LogcatModel(deviceID: id, repository: repository)
        let run = Task { await model.run() }
        while model.totalCount < 4 { await Task.yield() }
        run.cancel()
        #expect(model.totalCount == 4)
        #expect(model.visibleEntries.count == 4)

        model.minimumLevel = .warning
        #expect(model.visibleEntries.map(\.id) == [2, 3])
        model.minimumLevel = .verbose
        model.searchText = "disk"
        #expect(model.visibleEntries.map(\.id) == [3])
        model.searchText = ""
        model.packageFilter = "com.example.app"
        #expect(model.visibleEntries.map(\.id) == [2, 4])
        #expect(model.text(for: [2]).contains(" E App: hello"))

        model.clear()
        #expect(model.visibleEntries.isEmpty)
    }
}
