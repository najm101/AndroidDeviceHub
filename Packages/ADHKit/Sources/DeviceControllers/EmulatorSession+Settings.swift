public import DeviceDomain
import EmulatorGRPC
import Foundation
import SDKDomain
import SwiftProtobuf

// Inspector ▸ Settings over gRPC, plus the console for network conditions.
extension EmulatorSession: DeviceSettingsControlling {
    // MARK: - Battery

    public func battery() async throws -> BatteryState {
        let state = try await client.controller.getBattery(Google_Protobuf_Empty())
        return BatteryState(
            level: Int(state.chargeLevel),
            charger: SettingsMapping.charger(state.charger),
            health: SettingsMapping.health(state.health),
            status: SettingsMapping.status(state.status),
            isPresent: state.isPresent
        )
    }

    public func setBattery(_ state: BatteryState) async throws {
        var request = Android_Emulation_Control_BatteryState()
        request.hasBattery_p = true
        request.isPresent = state.isPresent
        request.chargeLevel = Int32(min(max(state.level, 0), 100))
        request.charger = SettingsMapping.charger(state.charger)
        request.health = SettingsMapping.health(state.health)
        request.status = SettingsMapping.status(state.status)
        _ = try await client.controller.setBattery(request)
    }

    // MARK: - Location

    public func location() async throws -> GeoLocation {
        let gps = try await client.controller.getGps(Google_Protobuf_Empty())
        return GeoLocation(
            latitude: gps.latitude,
            longitude: gps.longitude,
            altitude: gps.altitude,
            speed: gps.speed,
            bearing: gps.bearing
        )
    }

    public func setLocation(_ location: GeoLocation) async throws {
        guard location.isValid else {
            throw DeviceSettingsError.invalidValue("Latitude must be within ±90° and longitude within ±180°.")
        }
        var gps = Android_Emulation_Control_GpsState()
        gps.passiveUpdate = false
        gps.latitude = location.latitude
        gps.longitude = location.longitude
        gps.altitude = location.altitude
        gps.speed = location.speed
        gps.bearing = location.bearing
        gps.satellites = 12
        _ = try await client.controller.setGps(gps)
    }

    // MARK: - Network (console)

    public func networkConditions() async throws -> NetworkConditions {
        network
    }

    public func setNetworkConditions(_ conditions: NetworkConditions) async throws {
        guard let console else { throw DeviceActionError.notSupported }
        let old = network
        var commands: [String] = []
        if conditions.speed != old.speed { commands.append("network speed \(conditions.speed.rawValue)") }
        if conditions.latency != old.latency { commands.append("network delay \(conditions.latency.rawValue)") }
        if conditions.signal != old.signal { commands.append("gsm signal-profile \(conditions.signal.rawValue)") }
        if conditions.voice != old.voice { commands.append("gsm voice \(conditions.voice.rawValue)") }
        if conditions.data != old.data { commands.append("gsm data \(conditions.data.rawValue)") }
        guard !commands.isEmpty else { return }
        try await console.run(commands)
        network = conditions
    }

    // MARK: - Telephony

    public func phoneCall(_ action: PhoneCallAction, number: String) async throws {
        var call = Android_Emulation_Control_PhoneCall()
        call.operation = SettingsMapping.operation(action)
        call.number = number
        let response = try await client.controller.sendPhone(call)
        try SettingsMapping.check(response)
    }

    public func receiveSMS(from number: String, text: String) async throws {
        var message = Android_Emulation_Control_SmsMessage()
        message.srcAddress = number
        message.text = text
        let response = try await client.controller.sendSms(message)
        try SettingsMapping.check(response)
    }

    // MARK: - Sensors

    public func ambientSensors() async throws -> [AmbientSensor: Double] {
        var values: [AmbientSensor: Double] = [:]
        for sensor in AmbientSensor.allCases {
            var request = Android_Emulation_Control_PhysicalModelValue()
            request.target = SettingsMapping.physicalType(sensor)
            let reply = try await client.controller.getPhysicalModel(request)
            if reply.status == .ok, let value = reply.value.data.first {
                values[sensor] = Double(value)
            }
        }
        return values
    }

    public func setAmbientSensor(_ sensor: AmbientSensor, to value: Double) async throws {
        var request = Android_Emulation_Control_PhysicalModelValue()
        request.target = SettingsMapping.physicalType(sensor)
        request.value.data = [Float(value.clamped(to: sensor.range))]
        _ = try await client.controller.setPhysicalModel(request)
    }

    public func setPosture(_ posture: FoldPosture) async throws {
        var request = Android_Emulation_Control_Posture()
        request.value = SettingsMapping.posture(posture)
        _ = try await client.controller.setPosture(request)
    }

    public func touchFingerprint(id: Int) async throws {
        var touch = Android_Emulation_Control_Fingerprint()
        touch.isTouching = true
        touch.touchID = Int32(id)
        _ = try await client.controller.sendFingerprint(touch)
        try await Task.sleep(for: .milliseconds(250))
        touch.isTouching = false
        _ = try await client.controller.sendFingerprint(touch)
    }

    // MARK: - Display, microphone, clipboard

    public func brightness() async throws -> Int {
        var request = Android_Emulation_Control_BrightnessValue()
        request.target = .lcd
        return Int(try await client.controller.getBrightness(request).value)
    }

    public func setBrightness(_ value: Int) async throws {
        var request = Android_Emulation_Control_BrightnessValue()
        request.target = .lcd
        request.value = UInt32(min(max(value, 0), 255))
        _ = try await client.controller.setBrightness(request)
    }

    public func usesHostMicrophone() async throws -> Bool {
        try await client.controller.getMicrophoneState(Google_Protobuf_Empty()).realAudioEnabled
    }

    public func setUsesHostMicrophone(_ enabled: Bool) async throws {
        var state = Android_Emulation_Control_MicrophoneState()
        state.realAudioEnabled = enabled
        _ = try await client.controller.setMicrophoneState(state)
    }

    public func clipboard() async throws -> String {
        try await client.controller.getClipboard(Google_Protobuf_Empty()).text
    }

    public func setClipboard(_ text: String) async throws {
        var clip = Android_Emulation_Control_ClipData()
        clip.text = text
        _ = try await client.controller.setClipboard(clip)
    }
}

// MARK: - Snapshots

extension EmulatorSession: SnapshotManaging {
    public func snapshots() async throws -> [DeviceSnapshot] {
        var filter = Android_Emulation_Control_SnapshotFilter()
        filter.statusFilter = .all
        let list = try await client.snapshots.listSnapshots(filter)
        return list.snapshots.map(SettingsMapping.snapshot).sorted {
            ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast)
        }
    }

    public func saveSnapshot(named name: String) async throws {
        try SettingsMapping.check(try await client.snapshots.saveSnapshot(package(for: name)))
    }

    public func loadSnapshot(id: String) async throws {
        try SettingsMapping.check(try await client.snapshots.loadSnapshot(package(for: id)))
    }

    public func deleteSnapshot(id: String) async throws {
        try SettingsMapping.check(try await client.snapshots.deleteSnapshot(package(for: id)))
    }

    private func package(for id: String) -> Android_Emulation_Control_SnapshotPackage {
        var package = Android_Emulation_Control_SnapshotPackage()
        package.snapshotID = id
        return package
    }
}

/// Conversions between domain values and the emulator's protobuf messages.
enum SettingsMapping {
    typealias Battery = Android_Emulation_Control_BatteryState

    static func charger(_ value: Battery.BatteryCharger) -> BatteryState.Charger {
        switch value {
        case .ac: .ac
        case .usb: .usb
        case .wireless: .wireless
        default: .none
        }
    }

    static func charger(_ value: BatteryState.Charger) -> Battery.BatteryCharger {
        switch value {
        case .none: .none
        case .ac: .ac
        case .usb: .usb
        case .wireless: .wireless
        }
    }

    static func health(_ value: Battery.BatteryHealth) -> BatteryState.Health {
        switch value {
        case .failed: .failed
        case .dead: .dead
        case .overvoltage: .overvoltage
        case .overheated: .overheated
        default: .good
        }
    }

    static func health(_ value: BatteryState.Health) -> Battery.BatteryHealth {
        switch value {
        case .good: .good
        case .failed: .failed
        case .dead: .dead
        case .overvoltage: .overvoltage
        case .overheated: .overheated
        }
    }

    static func status(_ value: Battery.BatteryStatus) -> BatteryState.Status {
        switch value {
        case .charging: .charging
        case .discharging: .discharging
        case .notCharging: .notCharging
        case .full: .full
        default: .unknown
        }
    }

    static func status(_ value: BatteryState.Status) -> Battery.BatteryStatus {
        switch value {
        case .unknown: .unknown
        case .charging: .charging
        case .discharging: .discharging
        case .notCharging: .notCharging
        case .full: .full
        }
    }

    static func physicalType(_ sensor: AmbientSensor) -> Android_Emulation_Control_PhysicalModelValue.PhysicalType {
        switch sensor {
        case .temperature: .temperature
        case .light: .light
        case .pressure: .pressure
        case .humidity: .humidity
        case .proximity: .proximity
        }
    }

    static func posture(_ posture: FoldPosture) -> Android_Emulation_Control_Posture.PostureValue {
        switch posture {
        case .closed: .postureClosed
        case .halfOpened: .postureHalfOpened
        case .opened: .postureOpened
        case .flipped: .postureFlipped
        case .tent: .postureTent
        }
    }

    static func operation(_ action: PhoneCallAction) -> Android_Emulation_Control_PhoneCall.Operation {
        switch action {
        case .call: .initCall
        case .accept: .acceptCall
        case .reject: .rejectCallExplicit
        case .hold: .placeCallOnHold
        case .resume: .takeCallOffHold
        case .hangUp: .disconnectCall
        }
    }

    static func check(_ response: Android_Emulation_Control_PhoneResponse) throws {
        let reason: String
        switch response.response {
        case .ok: return
        case .badNumber: reason = "The phone number isn't valid."
        case .invalidAction: reason = "There's no call to do that with."
        case .radioOff: reason = "The device's radio is off."
        case .badOperation, .actionFailed, .UNRECOGNIZED: reason = "The call action failed."
        }
        throw DeviceSettingsError.rejected(reason)
    }

    static func check(_ package: Android_Emulation_Control_SnapshotPackage) throws {
        guard !package.success else { return }
        let message = String(decoding: package.err, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        throw DeviceSettingsError.rejected(message.isEmpty ? "The snapshot operation failed." : message)
    }

    static func snapshot(_ details: Android_Emulation_Control_SnapshotDetails) -> DeviceSnapshot {
        let info = details.details
        let name = info.hasLogicalName && !info.logicalName.isEmpty ? info.logicalName : details.snapshotID
        return DeviceSnapshot(
            id: details.snapshotID,
            name: name,
            createdAt: info.hasCreationTime ? Date(timeIntervalSince1970: TimeInterval(info.creationTime)) : nil,
            sizeBytes: Int64(clamping: details.size),
            isLoaded: details.status == .loaded,
            isCompatible: details.status != .incompatible
        )
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
