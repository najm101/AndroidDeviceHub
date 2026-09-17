import DeviceDomain
import DeviceWorkspaceFeature
import SwiftUI

@main
struct AndroidDeviceHubApp: App {
    @State private var app = AppModel(composition: AppComposition())

    init() {
        #if DEBUG
            DebugSnapshotter.install()
        #endif
    }

    var body: some Scene {
        Window("Android Device Hub", id: "main") {
            RootView(app: app)
        }
        .defaultSize(width: 1200, height: 780)
        .commands {
            AppCommands(app: app)
            DeviceWorkspaceCommands()
        }

        WindowGroup("Logcat", id: LogcatWindow.id, for: DeviceID.self) { $id in
            if let id {
                LogcatWindow(app: app, deviceID: id)
            }
        }
        .defaultSize(width: 1000, height: 640)

        Settings {
            SettingsView(app: app)
        }
    }
}
