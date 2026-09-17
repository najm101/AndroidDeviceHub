public import Foundation
public import SDKDomain

// MARK: - Values

public struct BatteryState: Hashable, Sendable {
    public enum Charger: String, CaseIterable, Hashable, Sendable, Identifiable {
        case none, ac, usb, wireless

        public var id: String { rawValue }
        public var title: String {
            switch self {
            case .none: "None"
            case .ac: "AC charger"
            case .usb: "USB"
            case .wireless: "Wireless"
            }
        }
    }

    public enum Health: String, CaseIterable, Hashable, Sendable, Identifiable {
        case good, failed, dead, overvoltage, overheated

        public var id: String { rawValue }
        public var title: String { rawValue.capitalized }
    }

    public enum Status: String, CaseIterable, Hashable, Sendable, Identifiable {
        case unknown, charging, discharging, notCharging, full

        public var id: String { rawValue }
        public var title: String {
            switch self {
            case .notCharging: "Not charging"
            default: rawValue.capitalized
            }
        }
    }

    /// 0–100
    public var level: Int
    public var charger: Charger
    public var health: Health
    public var status: Status
    public var isPresent: Bool

    public init(level: Int, charger: Charger, health: Health, status: Status, isPresent: Bool = true) {
        self.level = level
        self.charger = charger
        self.health = health
        self.status = status
        self.isPresent = isPresent
    }
}

public struct GeoLocation: Hashable, Sendable {
    public var latitude: Double
    public var longitude: Double
    /// Meters above sea level.
    public var altitude: Double
    /// Meters per second.
    public var speed: Double
    /// Degrees from north.
    public var bearing: Double

    public init(latitude: Double, longitude: Double, altitude: Double = 0, speed: Double = 0, bearing: Double = 0) {
        self.latitude = latitude
        self.longitude = longitude
        self.altitude = altitude
        self.speed = speed
        self.bearing = bearing
    }

    public var isValid: Bool {
        (-90...90).contains(latitude) && (-180...180).contains(longitude)
    }
}

/// Environment sensors the emulator simulates.
public enum AmbientSensor: String, CaseIterable, Hashable, Sendable, Identifiable {
    case temperature, light, pressure, humidity, proximity

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .temperature: "Temperature"
        case .light: "Light"
        case .pressure: "Pressure"
        case .humidity: "Humidity"
        case .proximity: "Proximity"
        }
    }

    public var unit: String {
        switch self {
        case .temperature: "°C"
        case .light: "lux"
        case .pressure: "hPa"
        case .humidity: "%"
        case .proximity: "cm"
        }
    }

    /// The range the Android Studio controls offer.
    public var range: ClosedRange<Double> {
        switch self {
        case .temperature: -273.1...100
        case .light: 0...40_000
        case .pressure: 0...1_100
        case .humidity: 0...100
        case .proximity: 0...10
        }
    }
}

public enum FoldPosture: String, CaseIterable, Hashable, Sendable, Identifiable {
    case closed, halfOpened, opened, flipped, tent

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .closed: "Closed"
        case .halfOpened: "Half open"
        case .opened: "Open"
        case .flipped: "Flipped"
        case .tent: "Tent"
        }
    }
}

public enum PhoneCallAction: Hashable, Sendable {
    /// Simulates an incoming call from the number.
    case call
    case accept
    case reject
    case hold
    case resume
    case hangUp
}

/// Cellular signal strength, from none (0) to great (4).
public enum SignalStrength: Int, CaseIterable, Hashable, Sendable, Identifiable {
    case none, poor, moderate, good, great

    public var id: Int { rawValue }
    public var title: String {
        switch self {
        case .none: "None"
        case .poor: "Poor"
        case .moderate: "Moderate"
        case .good: "Good"
        case .great: "Great"
        }
    }
}

/// The state of the cellular voice or data registration.
public enum CellularRegistration: String, CaseIterable, Hashable, Sendable, Identifiable {
    case home, roaming, searching, denied, unregistered

    public var id: String { rawValue }
    public var title: String { rawValue.capitalized }
}

/// Network conditions that are only tracked while the app controls the device.
public struct NetworkConditions: Hashable, Sendable {
    public var speed: NetworkSpeed
    public var latency: NetworkLatency
    public var signal: SignalStrength
    public var voice: CellularRegistration
    public var data: CellularRegistration

    public init(
        speed: NetworkSpeed = .full,
        latency: NetworkLatency = .none,
        signal: SignalStrength = .great,
        voice: CellularRegistration = .home,
        data: CellularRegistration = .home
    ) {
        self.speed = speed
        self.latency = latency
        self.signal = signal
        self.voice = voice
        self.data = data
    }
}

public struct DeviceSnapshot: Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var createdAt: Date?
    public var sizeBytes: Int64
    public var isLoaded: Bool
    public var isCompatible: Bool

    public init(id: String, name: String, createdAt: Date?, sizeBytes: Int64, isLoaded: Bool, isCompatible: Bool) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.sizeBytes = sizeBytes
        self.isLoaded = isLoaded
        self.isCompatible = isCompatible
    }
}

// MARK: - Protocols

/// Simulated hardware and environment of a running device.
///
/// Every getter reads the live value from the device; every setter applies immediately.
@MainActor
public protocol DeviceSettingsControlling: AnyObject {
    func battery() async throws -> BatteryState
    func setBattery(_ state: BatteryState) async throws

    func location() async throws -> GeoLocation
    func setLocation(_ location: GeoLocation) async throws

    func networkConditions() async throws -> NetworkConditions
    func setNetworkConditions(_ conditions: NetworkConditions) async throws

    func phoneCall(_ action: PhoneCallAction, number: String) async throws
    func receiveSMS(from number: String, text: String) async throws

    /// Sensors the device doesn't have are left out.
    func ambientSensors() async throws -> [AmbientSensor: Double]
    func setAmbientSensor(_ sensor: AmbientSensor, to value: Double) async throws

    func setPosture(_ posture: FoldPosture) async throws

    /// Touches and releases the fingerprint sensor with an enrolled finger id.
    func touchFingerprint(id: Int) async throws

    /// 0–255
    func brightness() async throws -> Int
    func setBrightness(_ value: Int) async throws

    /// Whether the device hears the Mac's microphone.
    func usesHostMicrophone() async throws -> Bool
    func setUsesHostMicrophone(_ enabled: Bool) async throws

    func clipboard() async throws -> String
    func setClipboard(_ text: String) async throws
}

@MainActor
public protocol SnapshotManaging: AnyObject {
    func snapshots() async throws -> [DeviceSnapshot]
    func saveSnapshot(named name: String) async throws
    func loadSnapshot(id: String) async throws
    func deleteSnapshot(id: String) async throws
}

public enum DeviceSettingsError: LocalizedError, Equatable {
    case rejected(String)
    case invalidValue(String)

    public var errorDescription: String? {
        switch self {
        case let .rejected(reason): "The device rejected the change: \(reason)"
        case let .invalidValue(reason): reason
        }
    }
}

/// Snapshot names become folder names, so keep them simple.
public enum SnapshotName {
    public static func validationError(for name: String, existing: [DeviceSnapshot]) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return "Enter a name." }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._- "))
        if trimmed.unicodeScalars.contains(where: { !allowed.contains($0) }) {
            return "Use letters, numbers, spaces, dots, dashes and underscores."
        }
        if existing.contains(where: { $0.id.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            return "A snapshot with this name already exists."
        }
        return nil
    }
}
