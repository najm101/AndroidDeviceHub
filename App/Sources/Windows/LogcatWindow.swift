import DeviceDomain
import ReportsFeature
import SwiftUI

/// One Logcat window per device. The model lives as long as the window.
struct LogcatWindow: View {
    static let id = "logcat"

    @State private var model: LogcatModel

    init(app: AppModel, deviceID: DeviceID) {
        _model = State(initialValue: app.composition.makeLogcatModel(for: deviceID))
    }

    var body: some View {
        LogcatView(model: model)
    }
}
