import DesignSystem
import DeviceActionsUI
import DeviceDomain
import SDKDomain
public import SwiftUI
import VideoCanvas

/// The center of the window: header toolbar, device canvas and footer controls.
public struct DeviceWorkspaceView: View {
    @Bindable private var model: DeviceWorkspaceModel
    @State private var width: CGFloat = 0

    public init(model: DeviceWorkspaceModel) {
        self.model = model
    }

    public var body: some View {
        if let device = model.device {
            content(for: device)
                .navigationTitle(device.name)
                .navigationSubtitle(device.versionSummary)
                .toolbar { headerControls(for: device) }
                // Like Device Hub: a narrow compact window drops the title so its buttons stay visible.
                .toolbar(removing: model.isCompact && width < CompactWindowLayout.titleMinimumWidth ? .title : nil)
                .onGeometryChange(for: CGFloat.self, of: \.size.width) { width = $0 }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    WorkspaceFooter(model: model)
                }
                .overlay(alignment: .top) {
                    CaptureBanner(model: model)
                }
                .deviceActionDialogs(request: $model.actionRequest, repository: model.repository, onError: model.show)
                .alert("Something went wrong", isPresented: isShowingError) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text(model.errorMessage ?? "")
                }
                .task(id: device.state) { await model.lookUpMissingImage() }
                .focusedSceneValue(\.deviceWorkspace, model)
                .onChange(of: model.installs.inventoryRevision) {
                    Task { await model.inventoryChanged() }
                }
        } else {
            ContentUnavailableView("Device Not Found", systemImage: "questionmark.app")
        }
    }

    @ViewBuilder
    private func content(for device: Device) -> some View {
        ZStack {
            Rectangle().fill(.background)
            DeviceCanvas(
                aspectSize: model.orientedScreenSize,
                style: model.frameStyle,
                zoom: model.isCompact ? .fit : model.zoom
            ) {
                if case .running(inAppControl: true) = device.state, let session = model.session {
                    DeviceScreenView(session: session, capturesKeyboard: model.capturesKeyboard)
                } else {
                    CanvasOverlay(model: model, device: device)
                }
            }
            .padding(model.isCompact ? CompactWindowLayout.margin : Spacing.xxLarge)
        }
    }

    /// Normal window: one group with the keyboard and zoom, then one with compact and the device menu.
    /// The compact window keeps only the second group, like Xcode's Device Hub.
    @ToolbarContentBuilder
    private func headerControls(for device: Device) -> some ToolbarContent {
        if !model.isCompact {
            ToolbarItemGroup {
                keyboardToggle
                capabilityButton("Zoom Out", symbol: Symbol.zoomOut, capability: .zoom, action: model.zoomOut)
                capabilityButton(
                    "Fit to Window (\(model.zoom.percentage))", symbol: Symbol.zoomFit, capability: .zoom,
                    action: model.zoomToFit
                )
                capabilityButton("Zoom In", symbol: Symbol.zoomIn, capability: .zoom, action: model.zoomIn)
            }
            ToolbarSpacer(.fixed)
        } else {
            // Keeps the buttons on the trailing edge when the title is hidden.
            ToolbarSpacer(.flexible)
        }
        ToolbarItemGroup {
            if model.isCompact {
                capabilityButton(
                    "Exit Compact Window", symbol: Symbol.expand, capability: .compactWindow,
                    help: "Expand to view all controls", action: model.toggleCompact
                )
            } else {
                capabilityButton(
                    "Compact Window", symbol: Symbol.compact, capability: .compactWindow,
                    action: model.toggleCompact
                )
            }
            Menu {
                DeviceActionMenuItems(
                    device: device,
                    repository: model.repository,
                    request: $model.actionRequest,
                    onError: model.show
                )
            } label: {
                Label("Device", systemImage: Symbol.more)
            }
            .menuIndicator(.hidden)
            .help("Device actions")
        }
    }

    @ViewBuilder private var keyboardToggle: some View {
        let availability = model.availability(.keyboardMode)
        Toggle(isOn: $model.capturesKeyboard) {
            Label("Mac Keyboard", systemImage: Symbol.keyboard)
        }
        .toggleStyle(.button)
        .availability(
            isVisible: availability.isVisible,
            isEnabled: availability.isAvailable,
            reason: availability.reason
                ?? (model.capturesKeyboard
                    ? "Typing goes to the device. Click to type in the Mac instead."
                    : "Click to send your Mac keyboard to the device.")
        )
    }

    @ViewBuilder
    private func capabilityButton(
        _ title: String,
        symbol: String,
        capability: Capability,
        help: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        let availability = model.availability(capability)
        Button(title, systemImage: symbol, action: action)
            .availability(
                isVisible: availability.isVisible,
                isEnabled: availability.isAvailable,
                reason: availability.reason ?? help ?? title
            )
    }

    private var isShowingError: Binding<Bool> {
        Binding {
            model.errorMessage != nil
        } set: {
            if !$0 { model.errorMessage = nil }
        }
    }
}
