import DeviceDomain
import EmulatorGRPC
import Foundation
import SDKDomain
import Testing

@testable import DeviceControllers

struct EmulatorSettingsCapabilityTests {
    @Test func offersSettingsOnlyWhileControlledByTheApp() {
        let running = EmulatorCapabilities.capabilities(for: .running(inAppControl: true), formFactor: .phone)
        #expect(running[.settings] == .available)
        #expect(running[.battery] == .available)
        #expect(running[.telephony] == .available)
        #expect(running[.posture] == nil)

        for state in [DeviceState.stopped, .starting, .running(inAppControl: false)] {
            let capabilities = EmulatorCapabilities.capabilities(for: state, formFactor: .phone)
            #expect(capabilities[.settings] == nil)
            #expect(capabilities[.snapshots] == nil)
        }
    }

    @Test func tailorsSectionsToTheFormFactor() {
        let foldable = EmulatorCapabilities.settingsSections(for: .foldable)
        #expect(foldable.contains(.posture))

        let tv = EmulatorCapabilities.settingsSections(for: .tv)
        #expect(!tv.contains(.battery))
        #expect(!tv.contains(.telephony))
        #expect(tv.contains(.network))
    }
}

struct SettingsMappingTests {
    @Test func roundTripsBatteryEnums() {
        for charger in BatteryState.Charger.allCases {
            #expect(SettingsMapping.charger(SettingsMapping.charger(charger)) == charger)
        }
        for health in BatteryState.Health.allCases {
            #expect(SettingsMapping.health(SettingsMapping.health(health)) == health)
        }
        for status in BatteryState.Status.allCases {
            #expect(SettingsMapping.status(SettingsMapping.status(status)) == status)
        }
    }

    @Test func mapsSnapshotDetails() {
        var details = Android_Emulation_Control_SnapshotDetails()
        details.snapshotID = "snap_1"
        details.size = 2_000
        details.status = .loaded
        details.details.creationTime = 1_789_000_000
        details.details.logicalName = "Before login"

        let snapshot = SettingsMapping.snapshot(details)
        #expect(snapshot.id == "snap_1")
        #expect(snapshot.name == "Before login")
        #expect(snapshot.createdAt == Date(timeIntervalSince1970: 1_789_000_000))
        #expect(snapshot.isLoaded)
        #expect(snapshot.isCompatible)

        details.status = .incompatible
        details.details.clearLogicalName()
        details.details.clearCreationTime()
        let old = SettingsMapping.snapshot(details)
        #expect(old.name == "snap_1")
        #expect(old.createdAt == nil)
        #expect(!old.isCompatible)
    }

    @Test func reportsFailedSnapshotOperations() {
        var package = Android_Emulation_Control_SnapshotPackage()
        package.success = false
        package.err = Data("Snapshot is incompatible".utf8)
        #expect(throws: DeviceSettingsError.rejected("Snapshot is incompatible")) {
            try SettingsMapping.check(package)
        }
        package.success = true
        #expect(throws: Never.self) { try SettingsMapping.check(package) }
    }

    @Test func explainsPhoneFailures() {
        var response = Android_Emulation_Control_PhoneResponse()
        response.response = .invalidAction
        #expect(throws: DeviceSettingsError.rejected("There's no call to do that with.")) {
            try SettingsMapping.check(response)
        }
    }
}
