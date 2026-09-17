import DeviceDomain
import SDKDomain

/// Decides what an emulator offers right now.
enum EmulatorCapabilities {
    static let stopFirst = "Stop the device first."
    static let startFirst = "Start the device to use this."
    static let ownWindow = "This emulator was started by another app. Restart it here to control it."
    static let needsImage = "Install the system image first."

    /// Inspector tabs that talk to the device over ADB.
    static let adbTabs: [Capability] = [.info, .apps, .profiles, .files, .reports]
    /// Inspector ▸ Settings sections that talk to the device over ADB.
    static let adbSettings: [Capability] = [.displaySize]

    /// Whether the device can be reached over ADB.
    enum ADBStatus: Hashable {
        /// Platform Tools aren't installed.
        case unavailable
        /// The emulator runs but hasn't appeared in ADB yet (still booting).
        case connecting
        case ready
    }

    static let canvasControls: [Capability] = [
        .screen, .input, .zoom, .compactWindow, .keyboardMode, .rotate, .navigationKeys, .screenshot, .record,
    ]

    /// Inspector ▸ Settings sections, offered while the app controls the emulator.
    static func settingsSections(for formFactor: FormFactor) -> [Capability] {
        var sections: [Capability] = [
            .settings, .location, .network, .sensors, .fingerprint, .display, .microphone, .clipboard, .snapshots,
        ]
        if formFactor != .tv {
            sections.append(.battery)
        }
        if ![.tv, .xr, .desktop].contains(formFactor) {
            sections.append(.telephony)
        }
        if formFactor == .foldable {
            sections.append(.posture)
        }
        return sections
    }

    static func capabilities(
        for state: DeviceState, formFactor: FormFactor, adb: ADBStatus = .unavailable
    ) -> [Capability: Availability] {
        var result: [Capability: Availability] = [
            .revealInFinder: .available,
            .duplicate: .available,
        ]

        switch state {
        case .stopped:
            result[.start] = .available
            result[.coldBoot] = .available
            setEditing(in: &result, to: .available)
            set(canvasControls, in: &result, to: .disabled(reason: startFirst))

        case .needsAttention:
            result[.start] = .disabled(reason: needsImage)
            result[.coldBoot] = .disabled(reason: needsImage)
            setEditing(in: &result, to: .available)
            set(canvasControls, in: &result, to: .disabled(reason: startFirst))

        case .starting:
            setEditing(in: &result, to: .disabled(reason: stopFirst))
            set(canvasControls, in: &result, to: .disabled(reason: startFirst))

        case .running(inAppControl: true):
            setEditing(in: &result, to: .disabled(reason: stopFirst))
            set(canvasControls, in: &result, to: .available)
            set(settingsSections(for: formFactor), in: &result, to: .available)
            result[.shutDown] = .available
            result[.restart] = .available
            setADBTabs(in: &result, adb: adb)
            setADB(adbSettings, in: &result, adb: adb)

        case .running(inAppControl: false):
            setEditing(in: &result, to: .disabled(reason: stopFirst))
            set(canvasControls, in: &result, to: .disabled(reason: ownWindow))
            setADBTabs(in: &result, adb: adb)
        }
        return result
    }

    private static func setADBTabs(in result: inout [Capability: Availability], adb: ADBStatus) {
        setADB(adbTabs, in: &result, adb: adb)
    }

    private static func setADB(
        _ capabilities: [Capability],
        in result: inout [Capability: Availability],
        adb: ADBStatus
    ) {
        switch adb {
        case .ready: set(capabilities, in: &result, to: .available)
        case .connecting: set(capabilities, in: &result, to: .disabled(reason: InspectorHint.connecting))
        case .unavailable: set(capabilities, in: &result, to: .disabled(reason: InspectorHint.installPlatformTools))
        }
    }

    private static func setEditing(in result: inout [Capability: Availability], to availability: Availability) {
        set([.rename, .wipeData, .remove], in: &result, to: availability)
    }

    private static func set(
        _ capabilities: [Capability],
        in result: inout [Capability: Availability],
        to availability: Availability
    ) {
        for capability in capabilities {
            result[capability] = availability
        }
    }
}
