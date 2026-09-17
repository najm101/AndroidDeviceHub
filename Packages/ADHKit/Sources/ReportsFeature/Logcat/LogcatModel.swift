public import DeviceDomain
import Foundation
public import Observation

/// The Logcat window for one device: a live, filterable log.
@MainActor
@Observable
public final class LogcatModel {
    static let maximumEntries = 50_000
    static let recentOnOpen = 2_000

    enum State: Equatable {
        case idle
        /// Waiting for the device to become reachable, with the reason.
        case waiting(String)
        case streaming
        /// The stream failed; it's retried shortly.
        case failed(String)
    }

    var minimumLevel: LogLevel = .verbose {
        didSet { refilter() }
    }
    var searchText = "" {
        didSet { refilter() }
    }
    /// Show only entries logged by this app (matched by uid).
    var packageFilter: String? {
        didSet { refilter() }
    }
    var isPaused = false
    var followsTail = true

    private(set) var visibleEntries: [LogEntry] = []
    private(set) var state: State = .idle
    private(set) var packages: [InstalledApp] = []
    private(set) var totalCount = 0

    let deviceID: DeviceID
    private let repository: any DeviceRepository
    @ObservationIgnored private var entries: [LogEntry] = []
    @ObservationIgnored private var pausedEntries: [LogEntry] = []

    public init(deviceID: DeviceID, repository: any DeviceRepository) {
        self.deviceID = deviceID
        self.repository = repository
    }

    var deviceName: String {
        repository.device(withID: deviceID)?.name ?? "Device"
    }

    /// Streams the log until the task is cancelled (when the window closes), reconnecting when the device
    /// restarts or ADB drops the connection.
    func run() async {
        while !Task.isCancelled {
            guard let inspector = repository.inspector(for: deviceID) else {
                let device = repository.device(withID: deviceID)
                state = .waiting(
                    device?.availability(of: .reports).reason ?? InspectorHint.startFirst)
                try? await Task.sleep(for: .seconds(1))
                continue
            }
            state = .streaming
            if packages.isEmpty {
                await loadPackages()
            }
            // After a reconnect, skip what's already shown.
            let lastDate = entries.last?.date
            do {
                for try await batch in inspector.logEntries(recent: lastDate == nil ? Self.recentOnOpen : 50) {
                    let fresh = lastDate.map { date in batch.filter { $0.date > date } } ?? batch
                    if isPaused {
                        pausedEntries.append(contentsOf: fresh)
                    } else {
                        append(fresh)
                    }
                }
            } catch is CancellationError {
                break
            } catch {
                state = .failed(error.localizedDescription)
            }
            try? await Task.sleep(for: .seconds(2))
        }
        state = .idle
    }

    func loadPackages() async {
        guard packages.isEmpty, let inspector = repository.inspector(for: deviceID) else { return }
        packages = (try? await inspector.apps(user: 0))?.filter { !$0.isSystem } ?? []
    }

    func togglePause() {
        isPaused.toggle()
        if !isPaused {
            append(pausedEntries)
            pausedEntries = []
        }
    }

    func clear() {
        entries = []
        pausedEntries = []
        visibleEntries = []
        totalCount = 0
    }

    func text(for ids: Set<LogEntry.ID>) -> String {
        visibleEntries.filter { ids.isEmpty || ids.contains($0.id) }.map(Self.line).joined(separator: "\n")
    }

    static func line(_ entry: LogEntry) -> String {
        let time = entry.date.formatted(
            .dateTime.hour(.twoDigits(amPM: .omitted)).minute().second().secondFraction(.fractional(3)))
        return "\(time) \(entry.pid) \(entry.tid) \(entry.level.letter) \(entry.tag): \(entry.message)"
    }

    // MARK: - Filtering

    private func append(_ batch: [LogEntry]) {
        guard !batch.isEmpty else { return }
        entries.append(contentsOf: batch)
        totalCount += batch.count
        var overflow = entries.count - Self.maximumEntries
        if overflow > 0 {
            // Trim in chunks so the array isn't shifted for every batch.
            overflow = max(overflow, Self.maximumEntries / 10)
            entries.removeFirst(overflow)
            let firstID = entries.first?.id ?? 0
            visibleEntries.removeAll { $0.id < firstID }
        }
        visibleEntries.append(contentsOf: batch.filter(matches))
    }

    private func refilter() {
        visibleEntries = entries.filter(matches)
    }

    private var packageUID: Int? {
        packageFilter.flatMap { name in packages.first { $0.packageName == name }?.uid }
    }

    private func matches(_ entry: LogEntry) -> Bool {
        guard entry.level >= minimumLevel else { return false }
        if packageFilter != nil {
            // Secondary users and profiles use uid + 100000 × user id.
            guard let uid = packageUID, let entryUID = entry.uid, entryUID % 100_000 == uid % 100_000 else {
                return false
            }
        }
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return true }
        return entry.message.localizedCaseInsensitiveContains(query)
            || entry.tag.localizedCaseInsensitiveContains(query)
            || String(entry.pid) == query
    }
}
