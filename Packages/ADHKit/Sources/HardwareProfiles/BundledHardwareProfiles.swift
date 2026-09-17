import Foundation
public import SDKDomain

/// Device definitions generated from the Android SDK by `Scripts/generate-hardware-profiles.py`.
public struct BundledHardwareProfiles: HardwareProfileProviding {
    private let loaded: [HardwareProfile]

    public init() {
        loaded = Self.load()
    }

    public func profiles() -> [HardwareProfile] {
        loaded
    }

    static func load() -> [HardwareProfile] {
        guard
            let url = Bundle.module.url(forResource: "hardware-profiles", withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let profiles = try? JSONDecoder().decode([HardwareProfile].self, from: data)
        else {
            assertionFailure("hardware-profiles.json is missing or invalid")
            return []
        }
        return profiles.sorted(by: HardwareProfileOrdering.areInIncreasingOrder)
    }
}

/// Current Google reference devices first, then generic sizes, then legacy devices.
enum HardwareProfileOrdering {
    static func areInIncreasingOrder(_ lhs: HardwareProfile, _ rhs: HardwareProfile) -> Bool {
        let left = rank(lhs)
        let right = rank(rhs)
        if left != right { return left < right }
        if left == 0 {
            // Newer Pixels first: "pixel_9_pro_xl" before "pixel_8".
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedDescending
        }
        return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }

    static func rank(_ profile: HardwareProfile) -> Int {
        let id = profile.id.lowercased()
        if id.hasPrefix("pixel") && !id.hasPrefix("pixel_c") && profile.manufacturer == "Google" { return 0 }
        if id.hasPrefix("medium") || id.hasPrefix("small") || id == "resizable"
            || profile.source != "devices" && profile.source != "nexus"
        {
            return 1
        }
        return 2
    }
}
