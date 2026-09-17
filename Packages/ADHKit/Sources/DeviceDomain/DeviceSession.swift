public import CoreGraphics
public import Foundation
public import IOSurface

/// The device's coarse orientation, as reported with each frame.
public enum DisplayRotation: Int, Hashable, Sendable {
    case portrait = 0
    case landscape = 1
    case reversePortrait = 2
    case reverseLandscape = 3

    public var isLandscape: Bool { self == .landscape || self == .reverseLandscape }
}

/// One rendered screen image (BGRA, top-down) backed by an IOSurface.
public struct ScreenFrame: @unchecked Sendable {
    public let surface: IOSurfaceRef
    public let width: Int
    public let height: Int
    public let rotation: DisplayRotation
    public let sequence: UInt32
    /// When the device produced the frame, if it says.
    public let producedAt: Date?

    public init(
        surface: IOSurfaceRef, width: Int, height: Int, rotation: DisplayRotation, sequence: UInt32,
        producedAt: Date? = nil
    ) {
        self.producedAt = producedAt
        self.surface = surface
        self.width = width
        self.height = height
        self.rotation = rotation
        self.sequence = sequence
    }
}

public enum PointerPhase: Hashable, Sendable {
    case began
    case moved
    case ended
}

public enum NavigationKey: String, CaseIterable, Hashable, Sendable {
    case back
    case home
    case recents
    case power
    case volumeUp
    case volumeDown
}

/// A key press from the Mac keyboard.
public struct KeyInput: Hashable, Sendable {
    /// `NSEvent.keyCode`
    public var macKeyCode: UInt16
    public var isDown: Bool

    public init(macKeyCode: UInt16, isDown: Bool) {
        self.macKeyCode = macKeyCode
        self.isDown = isDown
    }
}

public enum RotationDirection: Hashable, Sendable {
    case left
    case right
}

/// A live connection to a running device: screen, input and power control.
///
/// Emulators implement it over gRPC; physical devices will implement it over scrcpy (M7).
@MainActor
public protocol DeviceSession: AnyObject {
    var deviceID: DeviceID { get }
    /// The screen size in device pixels at portrait orientation.
    var displaySize: PixelSize { get }
    /// The latest known orientation.
    var rotation: DisplayRotation { get }
    /// A human-readable problem with the connection, if any.
    var connectionError: String? { get }

    /// Frames sized to fit `maxPixels`. The stream ends when the device stops or the caller cancels.
    func frames(maxPixels: PixelSize) -> AsyncStream<ScreenFrame>

    /// `point` is in device pixels of the *current* frame orientation (origin top-left).
    func touch(_ phase: PointerPhase, at point: CGPoint, pointerID: Int)
    func scroll(deltaX: Double, deltaY: Double, at point: CGPoint)
    func key(_ input: KeyInput)
    func type(_ text: String)
    func press(_ key: NavigationKey)

    func rotate(_ direction: RotationDirection) async throws
    /// A PNG of the current screen.
    func screenshot() async throws -> Data
    func shutDown() async throws
    func restart() async throws
}

/// Screen recording presets (Settings → General).
public enum RecordingQuality: String, CaseIterable, Hashable, Sendable, Identifiable {
    case standard
    case high

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .standard: "Standard (up to 1280 px, 30 fps)"
        case .high: "High (up to 1920 px, 60 fps)"
        }
    }

    /// Longest side of the video in pixels.
    public var maximumSide: Int { self == .standard ? 1280 : 1920 }
    public var framesPerSecond: Int32 { self == .standard ? 30 : 60 }
    public var bitsPerSecond: Int { self == .standard ? 6_000_000 : 16_000_000 }
}
