import AddEmulatorFeature
import DesignSystem
import DeviceListFeature
import DeviceWorkspaceFeature
import SwiftUI

/// Sidebar, workspace and inspector; in the compact window, only the device workspace.
struct MainSplitView: View {
    @Bindable var app: AppModel
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        // A real container (not `Group`), so the modifiers below attach once and survive the switch.
        ZStack {
            if app.isCompact, let id = app.selection, app.selectedDevice != nil {
                DeviceWorkspaceView(model: app.workspace(for: id))
                    .id(id)
            } else {
                splitView
            }
        }
        .sheet(item: $app.newEmulator) { model in
            AddEmulatorView(model: model)
        }
        .background(
            CompactWindowController(
                layout: app.compactLayout,
                normalMinimumSize: CGSize(width: Layout.mainWindowMinWidth, height: Layout.mainWindowMinHeight)
            )
        )
        .onAppear {
            app.openLogcat = { [openWindow] id in openWindow(id: LogcatWindow.id, value: id) }
        }
    }

    private var splitView: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            DeviceListView(model: app.deviceList, selection: $app.selection, onNewEmulator: app.presentNewEmulator)
                .navigationSplitViewColumnWidth(min: Layout.sidebarMinWidth, ideal: Layout.sidebarIdealWidth)
        } detail: {
            detail
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        }
        .inspector(isPresented: inspectorPresented) {
            InspectorContainer(app: app)
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                .inspectorColumnWidth(min: Layout.inspectorMinWidth, ideal: Layout.inspectorWidth, max: 420)
                // Declaring the toggle here gives the inspector its own toolbar section (it stays visible
                // while the inspector is collapsed), so the workspace controls stay above the canvas.
                .toolbar {
                    ToolbarSpacer(.flexible)
                    ToolbarItem {
                        InspectorToggle(isVisible: $app.isInspectorVisible)
                            .disabled(!app.canShowInspector)
                    }
                }
        }
    }

    @ViewBuilder private var detail: some View {
        if let id = app.selection, app.selectedDevice != nil {
            DeviceWorkspaceView(model: app.workspace(for: id))
                .id(id)
        } else {
            ContentUnavailableView {
                Label("No Device Selected", systemImage: "iphone")
            } description: {
                Text("Select a device in the sidebar, or create a new emulator.")
            } actions: {
                Button("New Emulator…", action: app.presentNewEmulator)
            }
        }
    }

    private var inspectorPresented: Binding<Bool> {
        Binding {
            app.canShowInspector && app.isInspectorVisible
        } set: {
            app.isInspectorVisible = $0
        }
    }
}
