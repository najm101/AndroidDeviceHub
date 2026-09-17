import AppKit
import DeviceDomain
import SwiftUI

struct AppCommands: Commands {
    let app: AppModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Emulator…", action: app.presentNewEmulator)
                .keyboardShortcut("n")
                .disabled(!app.isReady)
        }
        CommandGroup(after: .sidebar) {
            Button(app.isInspectorVisible ? "Hide Inspector" : "Show Inspector") {
                app.isInspectorVisible.toggle()
            }
            .keyboardShortcut("i", modifiers: [.command, .option])
            .disabled(!app.canShowInspector || app.isCompact)
            Button("Reload Devices") {
                Task { await app.reloadDevices() }
            }
            .keyboardShortcut("r")
            .disabled(!app.isReady)
        }
        CommandGroup(after: .help) {
            Button("Third-Party Notices") {
                if let url = Bundle.main.url(forResource: "ThirdPartyNotices", withExtension: "md") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
        CommandGroup(after: .windowList) {
            Button("Logcat") {
                if let id = app.selection { app.openLogcat(id) }
            }
            .keyboardShortcut("l", modifiers: [.command, .shift])
            .disabled(app.selectedDevice?.availability(of: .reports).isAvailable != true)
        }
    }
}
