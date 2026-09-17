import DesignSystem
import DeviceDomain
import Foundation
import SDKDomain

/// Turns a `Device` into the strings and icons a sidebar row shows.
struct DeviceRowPresentation: Equatable {
    let device: Device

    var title: String { device.name }

    /// "Android 16 · Google Play"
    var subtitle: String {
        var parts: [String] = []
        if let apiLevel = device.apiLevel {
            parts.append(apiLevel.androidVersionTitle)
        }
        switch device.state {
        case .needsAttention(let problem):
            parts.append(problem.message)
        case .starting:
            parts.append("Starting…")
        default:
            if device.hasPlayStore { parts.append("Google Play") }
        }
        return parts.joined(separator: " · ")
    }

    var symbolName: String {
        if case .physical = device.kind { return Symbol.physicalDevice }
        return device.formFactor.symbolName
    }

    var status: StatusIndicator.Style {
        switch device.state {
        case .running: .active
        case .starting: .busy
        case .needsAttention: .attention
        case .stopped: .inactive
        }
    }

    func matches(_ query: String) -> Bool {
        let haystack = [
            device.name,
            device.apiLevel.map { "API \($0)" },
            device.apiLevel?.androidVersionTitle,
            device.formFactor.title,
            device.hasPlayStore ? "Google Play" : nil,
        ]
        return haystack.compactMap { $0 }.contains { $0.localizedStandardContains(query) }
    }
}
