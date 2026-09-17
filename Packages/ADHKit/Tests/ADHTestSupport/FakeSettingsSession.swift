public import CoreGraphics
public import DeviceDomain
public import Foundation
import SDKDomain

/// A running device whose simulated hardware lives in memory.
@MainActor
public final class FakeSettingsSession: DeviceSession, DeviceSettingsControlling, SnapshotManaging {
    public let deviceID: DeviceID
    public let displaySize = PixelSize(width: 1080, height: 2400)
    public let rotation: DisplayRotation = .portrait
    public let connectionError: String? = nil

    public var batteryState = BatteryState(level: 80, charger: .ac, health: .good, status: .charging)
    public var geoLocation = GeoLocation(latitude: 37.422, longitude: -122.084, altitude: 5)
    public var network = NetworkConditions()
    public var sensors: [AmbientSensor: Double] = [.temperature: 20, .light: 100]
    public var brightnessValue = 128
    public var hostMicrophone = false
    public var clipboardText = ""
    public var storedSnapshots: [DeviceSnapshot] = []
    public private(set) var calls: [(PhoneCallAction, String)] = []
    public private(set) var messages: [(String, String)] = []
    public private(set) var fingerprints: [Int] = []
    public private(set) var postures: [FoldPosture] = []
    public private(set) var loadedSnapshots: [String] = []
    /// Thrown by every call while set.
    public var error: (any Error)?

    public init(deviceID: DeviceID) {
        self.deviceID = deviceID
    }

    private func check() throws {
        if let error { throw error }
    }

    // MARK: DeviceSession

    public func frames(maxPixels: PixelSize) -> AsyncStream<ScreenFrame> { AsyncStream { $0.finish() } }
    public func touch(_ phase: PointerPhase, at point: CGPoint, pointerID: Int) {}
    public func scroll(deltaX: Double, deltaY: Double, at point: CGPoint) {}
    public func key(_ input: KeyInput) {}
    public func type(_ text: String) {}
    public func press(_ key: NavigationKey) {}
    public func rotate(_ direction: RotationDirection) async throws {}
    public func screenshot() async throws -> Data { Data() }
    public func shutDown() async throws {}
    public func restart() async throws {}

    // MARK: DeviceSettingsControlling

    public func battery() async throws -> BatteryState {
        try check()
        return batteryState
    }

    public func setBattery(_ state: BatteryState) async throws {
        try check()
        batteryState = state
    }

    public func location() async throws -> GeoLocation {
        try check()
        return geoLocation
    }

    public func setLocation(_ location: GeoLocation) async throws {
        try check()
        geoLocation = location
    }

    public func networkConditions() async throws -> NetworkConditions {
        try check()
        return network
    }

    public func setNetworkConditions(_ conditions: NetworkConditions) async throws {
        try check()
        network = conditions
    }

    public func phoneCall(_ action: PhoneCallAction, number: String) async throws {
        try check()
        calls.append((action, number))
    }

    public func receiveSMS(from number: String, text: String) async throws {
        try check()
        messages.append((number, text))
    }

    public func ambientSensors() async throws -> [AmbientSensor: Double] {
        try check()
        return sensors
    }

    public func setAmbientSensor(_ sensor: AmbientSensor, to value: Double) async throws {
        try check()
        sensors[sensor] = value
    }

    public func setPosture(_ posture: FoldPosture) async throws {
        try check()
        postures.append(posture)
    }

    public func touchFingerprint(id: Int) async throws {
        try check()
        fingerprints.append(id)
    }

    public func brightness() async throws -> Int {
        try check()
        return brightnessValue
    }

    public func setBrightness(_ value: Int) async throws {
        try check()
        brightnessValue = value
    }

    public func usesHostMicrophone() async throws -> Bool {
        try check()
        return hostMicrophone
    }

    public func setUsesHostMicrophone(_ enabled: Bool) async throws {
        try check()
        hostMicrophone = enabled
    }

    public func clipboard() async throws -> String {
        try check()
        return clipboardText
    }

    public func setClipboard(_ text: String) async throws {
        try check()
        clipboardText = text
    }

    // MARK: SnapshotManaging

    public func snapshots() async throws -> [DeviceSnapshot] {
        try check()
        return storedSnapshots
    }

    public func saveSnapshot(named name: String) async throws {
        try check()
        storedSnapshots.append(
            DeviceSnapshot(id: name, name: name, createdAt: .now, sizeBytes: 1_000, isLoaded: false, isCompatible: true)
        )
    }

    public func loadSnapshot(id: String) async throws {
        try check()
        loadedSnapshots.append(id)
    }

    public func deleteSnapshot(id: String) async throws {
        try check()
        storedSnapshots.removeAll { $0.id == id }
    }
}
