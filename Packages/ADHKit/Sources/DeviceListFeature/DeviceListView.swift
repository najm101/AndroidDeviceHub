import DesignSystem
import DeviceActionsUI
public import DeviceDomain
public import SwiftUI

/// The sidebar: a search field and the device list, plus the `+` menu.
public struct DeviceListView: View {
    @Bindable private var model: DeviceListModel
    @Binding private var selection: DeviceID?
    private let onNewEmulator: () -> Void

    public init(model: DeviceListModel, selection: Binding<DeviceID?>, onNewEmulator: @escaping () -> Void) {
        self.model = model
        _selection = selection
        self.onNewEmulator = onNewEmulator
    }

    public var body: some View {
        List(selection: $selection) {
            ForEach(model.visibleDevices) { device in
                DeviceRow(presentation: DeviceRowPresentation(device: device))
                    .tag(device.id)
            }
        }
        .listStyle(.sidebar)
        .searchable(text: $model.searchText, placement: .sidebar, prompt: "Search")
        .overlay { emptyState }
        .contextMenu(forSelectionType: DeviceID.self) { ids in
            if ids.count == 1, let device = ids.first.flatMap(model.repository.device(withID:)) {
                DeviceActionMenuItems(
                    device: device,
                    repository: model.repository,
                    request: $model.actionRequest,
                    onError: model.show
                )
            }
        } primaryAction: { ids in
            ids.first.map(model.primaryAction)
        }
        .onDeleteCommand {
            selection.map(model.requestRemoval)
        }
        .toolbar {
            // Becomes a menu (emulator / real device) once physical devices are supported (M7).
            ToolbarItem {
                Button("New Emulator", systemImage: Symbol.add, action: onNewEmulator)
                    .help("Create a new emulator")
            }
        }
        .deviceActionDialogs(request: $model.actionRequest, repository: model.repository, onError: model.show)
        .alert("Something went wrong", isPresented: isShowingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
        .task { await model.load() }
    }

    @ViewBuilder private var emptyState: some View {
        if model.isLoading {
            ProgressView()
        } else if let error = model.loadError, !model.hasDevices {
            ContentUnavailableView("Can't Load Devices", systemImage: Symbol.warning, description: Text(error))
        } else if !model.hasDevices {
            ContentUnavailableView {
                Label("No Devices", systemImage: "iphone.slash")
            } description: {
                Text("Create an emulator to get started.")
            } actions: {
                Button("New Emulator…", action: onNewEmulator)
            }
        } else if model.visibleDevices.isEmpty {
            ContentUnavailableView.search(text: model.searchText)
        }
    }

    private var isShowingError: Binding<Bool> {
        Binding {
            model.errorMessage != nil
        } set: {
            if !$0 { model.errorMessage = nil }
        }
    }
}

struct DeviceRow: View {
    let presentation: DeviceRowPresentation

    var body: some View {
        HStack(spacing: Spacing.small) {
            Image(systemName: presentation.symbolName)
                .foregroundStyle(.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: Spacing.xxSmall) {
                Text(presentation.title)
                    .lineLimit(1)
                Text(presentation.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: Spacing.xSmall)
            StatusIndicator(presentation.status)
        }
        .padding(.vertical, Spacing.xxSmall)
    }
}
