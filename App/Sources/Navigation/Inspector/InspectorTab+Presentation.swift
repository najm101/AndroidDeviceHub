import DesignSystem

extension AppModel.InspectorTab {
    var title: String {
        switch self {
        case .settings: "Settings"
        case .reports: "Reports"
        case .info: "Info"
        case .files: "Files"
        }
    }

    var symbol: String {
        switch self {
        case .settings: Symbol.settings
        case .reports: Symbol.reports
        case .info: Symbol.info
        case .files: Symbol.files
        }
    }
}
