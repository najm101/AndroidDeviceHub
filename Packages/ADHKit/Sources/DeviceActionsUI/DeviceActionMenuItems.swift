import DesignSystem
public import DeviceDomain
public import SwiftUI

/// The device menu shared by the sidebar context menu and the workspace `⋯` menu.
///
/// Items are shown, disabled or hidden according to the device's capabilities.
public struct DeviceActionMenuItems: View {
    private let device: Device
    private let repository: any DeviceRepository
    @Binding private var request: DeviceActionRequest?
    private let onError: (any Error) -> Void

    public init(
        device: Device,
        repository: any DeviceRepository,
        request: Binding<DeviceActionRequest?>,
        onError: @escaping (any Error) -> Void
    ) {
        self.device = device
        self.repository = repository
        _request = request
        self.onError = onError
    }

    public var body: some View {
        Group {
            item("Start", Symbol.start, .start) { run { try await repository.start(device.id, option: .normal) } }
            item("Cold Boot", Symbol.restart, .coldBoot) {
                run { try await repository.start(device.id, option: .coldBoot) }
            }
            item("Shut Down", Symbol.stop, .shutDown) { run { try await repository.shutDown(device.id) } }
            item("Restart", Symbol.restart, .restart) { run { try await repository.restart(device.id) } }
        }
        Divider()
        Group {
            item("Show in Finder", Symbol.finder, .revealInFinder) { repository.revealInFinder(device.id) }
            item("Rename…", Symbol.rename, .rename) { request = .rename(device) }
            item("Duplicate…", Symbol.duplicate, .duplicate) { request = .duplicate(device) }
        }
        Divider()
        Group {
            item("Reset Device…", Symbol.wipe, .wipeData) { request = .wipeData(device) }
            item("Remove…", Symbol.remove, .remove, role: .destructive) { request = .remove(device) }
        }
    }

    @ViewBuilder
    private func item(
        _ title: String,
        _ symbol: String,
        _ capability: Capability,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) -> some View {
        let availability = device.availability(of: capability)
        if availability.isVisible {
            Button(role: role, action: action) {
                Label(title, systemImage: symbol)
            }
            .disabled(!availability.isAvailable)
            .help(availability.reason ?? "")
        }
    }

    private func run(_ operation: @escaping () async throws -> Void) {
        Task {
            do {
                try await operation()
            } catch {
                onError(error)
            }
        }
    }
}
