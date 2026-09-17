public import Foundation
public import SDKDomain

public enum StartOption: Hashable, Sendable {
    case normal
    case coldBoot
}

/// The list of all devices plus the actions on them.
///
/// Implemented by `DeviceControllers.LiveDeviceRepository`; features only see this protocol.
@MainActor
public protocol DeviceRepository: AnyObject {
    var devices: [Device] { get }
    var isLoading: Bool { get }
    var lastError: String? { get }

    func device(withID id: DeviceID) -> Device?
    /// The live connection for a running device that the app can control.
    func session(for id: DeviceID) -> (any DeviceSession)?
    /// ADB-backed inspection of a running device (apps, files, profiles, reports).
    func inspector(for id: DeviceID) -> (any DeviceInspecting)?
    func reload() async

    func start(_ id: DeviceID, option: StartOption) async throws
    func shutDown(_ id: DeviceID) async throws
    func restart(_ id: DeviceID) async throws
    func create(_ specification: VirtualDeviceSpecification) async throws -> DeviceID
    func rename(_ id: DeviceID, to name: String) async throws
    func duplicate(_ id: DeviceID, as name: String) async throws -> DeviceID
    func wipeData(_ id: DeviceID) async throws
    func remove(_ id: DeviceID) async throws
    func revealInFinder(_ id: DeviceID)
}

public enum DeviceActionError: LocalizedError, Equatable {
    case notFound
    case notSupported
    case deviceIsRunning
    case invalidName(String)
    case missingSDK

    public var errorDescription: String? {
        switch self {
        case .notFound: "The device no longer exists."
        case .notSupported: "This action isn't available for this device."
        case .deviceIsRunning: "Stop the device first."
        case let .invalidName(reason): reason
        case .missingSDK: "The Android SDK folder isn't set up."
        }
    }
}
