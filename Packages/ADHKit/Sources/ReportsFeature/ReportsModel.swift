public import DeviceDomain
public import Foundation
public import Observation

/// Dependencies of Inspector ▸ Reports and the Logcat window, wired by the app.
@MainActor
public struct ReportsDependencies {
    public var repository: any DeviceRepository
    /// Where bug reports and exported crash logs go.
    public var outputFolder: @MainActor () -> URL
    public var reveal: @MainActor (URL) -> Void
    public var openLogcat: @MainActor (DeviceID) -> Void

    public init(
        repository: any DeviceRepository,
        outputFolder: @escaping @MainActor () -> URL,
        reveal: @escaping @MainActor (URL) -> Void,
        openLogcat: @escaping @MainActor (DeviceID) -> Void
    ) {
        self.repository = repository
        self.outputFolder = outputFolder
        self.reveal = reveal
        self.openLogcat = openLogcat
    }
}

/// Inspector ▸ Reports for one device.
@MainActor
@Observable
public final class ReportsModel {
    enum BugReportState: Equatable {
        case idle
        case running(progress: Double?)
        case finished(URL)
    }

    private(set) var reports: [CrashReport] = []
    private(set) var isLoading = false
    private(set) var hasLoaded = false
    var errorMessage: String?
    var selectedReport: CrashReport?
    private(set) var bugReport: BugReportState = .idle
    /// Reports up to this date are hidden ("Clear"). The device keeps them.
    private(set) var clearedUpTo: Date?

    let deviceID: DeviceID
    private let dependencies: ReportsDependencies
    @ObservationIgnored private var bugReportTask: Task<Void, Never>?

    public init(deviceID: DeviceID, dependencies: ReportsDependencies) {
        self.deviceID = deviceID
        self.dependencies = dependencies
    }

    var availability: Availability {
        dependencies.repository.device(withID: deviceID)?.availability(of: .reports) ?? .hidden
    }

    var visibleReports: [CrashReport] {
        guard let clearedUpTo else { return reports }
        return reports.filter { $0.date > clearedUpTo }
    }

    // MARK: - Crashes

    func load() async {
        guard let inspector = inspector() else { return }
        isLoading = !hasLoaded
        defer {
            isLoading = false
            hasLoaded = true
        }
        do {
            reports = try await inspector.crashReports()
        } catch {
            show(error)
        }
    }

    func clear() {
        clearedUpTo = reports.map(\.date).max() ?? Date()
        selectedReport = nil
    }

    func showAll() {
        clearedUpTo = nil
    }

    var hiddenCount: Int { reports.count - visibleReports.count }

    /// One text file with every visible report.
    func exportText(for reports: [CrashReport]) -> String {
        reports.map { report in
            "\(report.date.formatted(.iso8601)) \(report.tag) \(report.process ?? "")\n\n\(report.text)"
        }
        .joined(separator: "\n\n" + String(repeating: "=", count: 60) + "\n\n")
    }

    static func exportFileName(for report: CrashReport?) -> String {
        guard let report else { return "crash-reports.txt" }
        let stamp = report.date.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false))
            .replacingOccurrences(of: ":", with: "-")
        return "\(report.process ?? report.tag)-\(stamp).txt"
    }

    // MARK: - Diagnostics

    func openLogcat() {
        dependencies.openLogcat(deviceID)
    }

    func startBugReport() {
        guard let inspector = inspector(), bugReportTask == nil else { return }
        let folder = dependencies.outputFolder()
        bugReport = .running(progress: nil)
        bugReportTask = Task {
            defer { bugReportTask = nil }
            let updates = AsyncStream<Double?>.makeStream(bufferingPolicy: .bufferingNewest(1))
            let watcher = Task {
                for await progress in updates.stream where self.bugReport != .idle {
                    self.bugReport = .running(progress: progress)
                }
            }
            let result = await Result { try await inspector.bugReport(into: folder) { updates.continuation.yield($0) } }
            // Let pending progress updates land before showing the outcome.
            updates.continuation.finish()
            await watcher.value
            switch result {
            case let .success(url):
                bugReport = .finished(url)
            case let .failure(error):
                bugReport = .idle
                show(error)
            }
        }
    }

    func cancelBugReport() {
        bugReportTask?.cancel()
        bugReport = .idle
    }

    func revealBugReport() {
        if case let .finished(url) = bugReport { dependencies.reveal(url) }
    }

    func dismissBugReport() {
        bugReport = .idle
    }

    // MARK: - Helpers

    private func show(_ error: any Error) {
        guard !(error is CancellationError) else { return }
        errorMessage = error.localizedDescription
    }

    private func inspector() -> (any DeviceInspecting)? {
        guard let inspector = dependencies.repository.inspector(for: deviceID) else {
            errorMessage = availability.reason ?? "The device isn't connected."
            return nil
        }
        return inspector
    }
}
