import DeviceDomain

/// The sections of Inspector ▸ Settings, in display order.
enum SettingsSection: String, CaseIterable, Hashable, Identifiable {
    case location, battery, network, telephony, sensors, posture, fingerprint, display, microphone, clipboard
    case snapshots

    var id: String { rawValue }

    /// The capability that decides whether the section is shown.
    var capability: Capability {
        switch self {
        case .location: .location
        case .battery: .battery
        case .network: .network
        case .telephony: .telephony
        case .sensors: .sensors
        case .posture: .posture
        case .fingerprint: .fingerprint
        case .display: .display
        case .microphone: .microphone
        case .clipboard: .clipboard
        case .snapshots: .snapshots
        }
    }

    var title: String {
        switch self {
        case .location: "Location"
        case .battery: "Battery"
        case .network: "Network"
        case .telephony: "Phone"
        case .sensors: "Sensors"
        case .posture: "Fold Posture"
        case .fingerprint: "Fingerprint"
        case .display: "Display"
        case .microphone: "Microphone"
        case .clipboard: "Clipboard"
        case .snapshots: "Snapshots"
        }
    }

    var systemImage: String {
        switch self {
        case .location: "location"
        case .battery: "battery.75percent"
        case .network: "antenna.radiowaves.left.and.right"
        case .telephony: "phone"
        case .sensors: "thermometer.medium"
        case .posture: "rectangle.portrait.split.2x1"
        case .fingerprint: "touchid"
        case .display: "sun.max"
        case .microphone: "mic"
        case .clipboard: "doc.on.clipboard"
        case .snapshots: "camera.on.rectangle"
        }
    }
}
