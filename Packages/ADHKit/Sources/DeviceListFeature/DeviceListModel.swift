public import DeviceActionsUI
public import DeviceDomain
import Foundation
public import Observation

/// Sidebar state: search, filtering and device actions.
@MainActor
@Observable
public final class DeviceListModel {
    public var searchText = ""
    public var actionRequest: DeviceActionRequest?
    public var errorMessage: String?

    let repository: any DeviceRepository

    public init(repository: any DeviceRepository) {
        self.repository = repository
    }

    var isLoading: Bool { repository.isLoading }
    var loadError: String? { repository.lastError }

    /// Devices matching the search, running ones first.
    var visibleDevices: [Device] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return repository.devices
            .filter { query.isEmpty || DeviceRowPresentation(device: $0).matches(query) }
            .sorted(by: Self.areInIncreasingOrder)
    }

    var hasDevices: Bool { !repository.devices.isEmpty }

    func load() async {
        await repository.reload()
    }

    func primaryAction(for id: DeviceID) {
        guard let device = repository.device(withID: id), device.availability(of: .start).isAvailable else { return }
        Task {
            do {
                try await repository.start(id, option: .normal)
            } catch {
                show(error)
            }
        }
    }

    func requestRemoval(of id: DeviceID) {
        guard let device = repository.device(withID: id), device.availability(of: .remove).isAvailable else { return }
        actionRequest = .remove(device)
    }

    func show(_ error: any Error) {
        errorMessage = [
            error.localizedDescription,
            (error as? any LocalizedError)?.recoverySuggestion,
        ]
        .compactMap { $0 }
        .joined(separator: " ")
    }

    static func areInIncreasingOrder(_ lhs: Device, _ rhs: Device) -> Bool {
        if lhs.state.isRunning != rhs.state.isRunning { return lhs.state.isRunning }
        return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }
}
