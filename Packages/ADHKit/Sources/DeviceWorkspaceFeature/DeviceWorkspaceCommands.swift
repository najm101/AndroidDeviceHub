import DeviceDomain
public import SwiftUI

extension FocusedValues {
    /// The workspace of the device shown in the key window.
    @Entry var deviceWorkspace: DeviceWorkspaceModel?
}

/// Menu bar commands for the selected device: Device menu plus zoom and compact window in View.
public struct DeviceWorkspaceCommands: Commands {
    @FocusedValue(\.deviceWorkspace) private var model

    public init() {}

    public var body: some Commands {
        CommandMenu("Device") {
            item("Start", .start, .return) { $0.start(.normal) }
            item("Cold Boot", .coldBoot, .return, [.command, .option]) { $0.start(.coldBoot) }
            item("Shut Down", .shutDown) { $0.shutDown() }
            item("Restart", .restart) { $0.restart() }
            Divider()
            item("Back", .navigationKeys, "[") { $0.press(.back) }
            item("Home", .navigationKeys, "h", [.command, .shift]) { $0.press(.home) }
            item("Recent Apps", .navigationKeys, "o", [.command, .shift]) { $0.press(.recents) }
            item("Rotate Left", .rotate, .leftArrow) { $0.rotate(.left) }
            item("Rotate Right", .rotate, .rightArrow) { $0.rotate(.right) }
            Divider()
            item("Take Screenshot", .screenshot, "s") { $0.takeScreenshot() }
            item(model?.isRecording == true ? "Stop Recording" : "Start Recording", .record, "r", [.command, .shift]) {
                $0.toggleRecording()
            }
            Divider()
            item(
                model?.capturesKeyboard == true ? "Type on the Mac" : "Send Keyboard to Device",
                .keyboardMode, "k"
            ) { $0.capturesKeyboard.toggle() }
        }

        CommandGroup(after: .toolbar) {
            Section {
                item("Zoom In", .zoom, "+") { $0.zoomIn() }
                item("Zoom Out", .zoom, "-") { $0.zoomOut() }
                item("Fit to Window", .zoom, "0") { $0.zoomToFit() }
                item(
                    model?.isCompact == true ? "Exit Compact Window" : "Compact Window",
                    .compactWindow, "c", [.command, .option]
                ) { $0.toggleCompact() }
            }
        }
    }

    private func item(
        _ title: String,
        _ capability: Capability,
        _ key: KeyEquivalent? = nil,
        _ modifiers: EventModifiers = .command,
        action: @escaping (DeviceWorkspaceModel) -> Void
    ) -> some View {
        Button(title) {
            if let model { action(model) }
        }
        .modifier(OptionalShortcut(key: key, modifiers: modifiers))
        .disabled(model?.availability(capability).isAvailable != true)
    }
}

private struct OptionalShortcut: ViewModifier {
    let key: KeyEquivalent?
    let modifiers: EventModifiers

    func body(content: Content) -> some View {
        if let key {
            content.keyboardShortcut(key, modifiers: modifiers)
        } else {
            content
        }
    }
}
