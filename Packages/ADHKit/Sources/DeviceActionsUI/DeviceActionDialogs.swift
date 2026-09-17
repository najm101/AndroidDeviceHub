public import DeviceDomain
public import SwiftUI

public extension View {
    /// Presents the rename, duplicate, reset and remove dialogs for `request`.
    func deviceActionDialogs(
        request: Binding<DeviceActionRequest?>,
        repository: any DeviceRepository,
        onError: @escaping (any Error) -> Void
    ) -> some View {
        modifier(DeviceActionDialogs(request: request, repository: repository, onError: onError))
    }
}

private struct DeviceActionDialogs: ViewModifier {
    @Binding var request: DeviceActionRequest?
    let repository: any DeviceRepository
    let onError: (any Error) -> Void

    func body(content: Content) -> some View {
        content
            .sheet(item: nameRequest) { request in
                switch request {
                case let .duplicate(device):
                    NameDeviceSheet(
                        title: "Duplicate Device", actionTitle: "Duplicate", initialName: "\(device.name) Copy"
                    ) { name in
                        _ = try await repository.duplicate(device.id, as: name)
                    }
                default:
                    NameDeviceSheet(title: "Rename Device", actionTitle: "Rename", initialName: request.device.name) {
                        name in
                        try await repository.rename(request.device.id, to: name)
                    }
                }
            }
            .confirmationDialog(
                confirmationTitle,
                isPresented: isConfirming,
                titleVisibility: .visible,
                presenting: request
            ) { request in
                switch request {
                case let .wipeData(device):
                    Button("Reset", role: .destructive) { perform { try await repository.wipeData(device.id) } }
                case let .remove(device):
                    Button("Remove", role: .destructive) { perform { try await repository.remove(device.id) } }
                default:
                    EmptyView()
                }
            } message: { request in
                switch request {
                case .wipeData:
                    Text("All apps, data and snapshots on this device will be deleted. Its settings stay.")
                case .remove:
                    Text("The device and all of its data will be deleted. This can't be undone.")
                default:
                    EmptyView()
                }
            }
    }

    private var nameRequest: Binding<DeviceActionRequest?> {
        Binding {
            switch request {
            case .rename, .duplicate: request
            default: nil
            }
        } set: {
            request = $0
        }
    }

    private var isConfirming: Binding<Bool> {
        Binding {
            switch request {
            case .wipeData, .remove: true
            default: false
            }
        } set: {
            if !$0 { request = nil }
        }
    }

    private var confirmationTitle: String {
        switch request {
        case let .wipeData(device): "Reset “\(device.name)”?"
        case let .remove(device): "Remove “\(device.name)”?"
        default: ""
        }
    }

    private func perform(_ operation: @escaping () async throws -> Void) {
        Task {
            do {
                try await operation()
            } catch {
                onError(error)
            }
        }
    }
}
