public import CoreGraphics
public import DeviceDomain
import EmulatorGRPC
public import EmulatorRuntime
public import Foundation
import Foundations
import GRPCCore
public import Observation
import SwiftProtobuf
import VideoCanvas
import os

/// A live gRPC connection to an emulator this app started.
@MainActor
@Observable
public final class EmulatorSession: DeviceSession {
    public let deviceID: DeviceID
    public let displaySize: PixelSize
    public private(set) var rotation: DisplayRotation = .portrait
    public private(set) var connectionError: String?

    let client: EmulatorClient
    /// For settings gRPC doesn't offer. Nil when the discovery file has no console port.
    @ObservationIgnored let console: EmulatorConsole?
    /// The console can't report network conditions, so the session remembers what it set.
    @ObservationIgnored var network: NetworkConditions
    @ObservationIgnored private let frameDirectory: URL
    @ObservationIgnored private let input: InputChannel
    @ObservationIgnored private var modelRotationDegrees: Float = 0
    @ObservationIgnored private let log = ADHLog.logger("EmulatorSession")

    public init(
        emulator: RunningEmulator,
        displaySize: PixelSize,
        frameDirectory: URL,
        network: NetworkConditions = NetworkConditions()
    ) throws {
        guard let port = emulator.grpcPort else { throw EmulatorSessionError.noEndpoint }
        deviceID = .emulator(avdID: emulator.avdID)
        self.displaySize = displaySize
        self.frameDirectory = frameDirectory
        self.network = network
        console = emulator.serialPort.map { EmulatorConsole(port: $0) }
        client = try EmulatorClient(port: port, token: emulator.grpcToken)
        input = InputChannel(client: client)
    }

    public func close() {
        input.finish()
        client.close()
    }

    // MARK: - Screen

    public func frames(maxPixels: PixelSize) -> AsyncStream<ScreenFrame> {
        let client = client
        let largest = max(displaySize.width, displaySize.height)
        let file = frameDirectory.appending(path: "\(UUID().uuidString).rgba", directoryHint: .notDirectory)
        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let task = Task.detached { [weak self] in
                do {
                    let shared = try? SharedFrameFile(url: file, capacity: largest * largest * 4)
                    try await ScreenStreamer.stream(
                        client: client, maxPixels: maxPixels, shared: shared
                    ) { frame in
                        continuation.yield(frame)
                        // Only publish real changes: every assignment would invalidate the canvas layout.
                        Task { @MainActor in
                            if let self, self.rotation != frame.rotation { self.rotation = frame.rotation }
                        }
                    }
                } catch {
                    if !(error is CancellationError) {
                        await MainActor.run { self?.connectionError = error.localizedDescription }
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func screenshot() async throws -> Data {
        var format = Android_Emulation_Control_ImageFormat()
        format.format = .png
        let image = try await client.controller.getScreenshot(format, options: EmulatorClient.largeMessageOptions)
        return image.image
    }

    // MARK: - Input

    public func touch(_ phase: PointerPhase, at point: CGPoint, pointerID: Int) {
        let device = InputMapping.devicePoint(point, rotation: rotation, displaySize: displaySize)
        var touch = Android_Emulation_Control_Touch()
        touch.x = Int32(device.x.rounded())
        touch.y = Int32(device.y.rounded())
        touch.identifier = Int32(pointerID)
        touch.pressure = phase == .ended ? 0 : 1
        touch.expiration = .neverExpire
        var event = Android_Emulation_Control_TouchEvent()
        event.touches = [touch]
        var inputEvent = Android_Emulation_Control_InputEvent()
        inputEvent.touchEvent = event
        input.send(inputEvent)
    }

    public func scroll(deltaX: Double, deltaY: Double, at point: CGPoint) {
        // The emulator scrolls at the last pointer position; move there first without pressing.
        let device = InputMapping.devicePoint(point, rotation: rotation, displaySize: displaySize)
        var mouse = Android_Emulation_Control_MouseEvent()
        mouse.x = Int32(device.x.rounded())
        mouse.y = Int32(device.y.rounded())
        var move = Android_Emulation_Control_InputEvent()
        move.mouseEvent = mouse
        input.send(move)

        var wheel = Android_Emulation_Control_WheelEvent()
        wheel.dx = Int32((deltaX * 12).rounded())
        wheel.dy = Int32((deltaY * 12).rounded())
        var event = Android_Emulation_Control_InputEvent()
        event.wheelEvent = wheel
        input.send(event)
    }

    public func key(_ key: KeyInput) {
        var keyboard = Android_Emulation_Control_KeyboardEvent()
        keyboard.codeType = .mac
        keyboard.keyCode = Int32(key.macKeyCode)
        keyboard.eventType = key.isDown ? .keydown : .keyup
        var event = Android_Emulation_Control_InputEvent()
        event.keyEvent = keyboard
        input.send(event)
    }

    public func type(_ text: String) {
        var keyboard = Android_Emulation_Control_KeyboardEvent()
        keyboard.text = text
        var event = Android_Emulation_Control_InputEvent()
        event.keyEvent = keyboard
        input.send(event)
    }

    public func press(_ key: NavigationKey) {
        var keyboard = Android_Emulation_Control_KeyboardEvent()
        keyboard.eventType = .keypress
        keyboard.key = InputMapping.keyName(for: key)
        var event = Android_Emulation_Control_InputEvent()
        event.keyEvent = keyboard
        input.send(event)
    }

    // MARK: - Device

    public func rotate(_ direction: RotationDirection) async throws {
        modelRotationDegrees += direction == .left ? 90 : -90
        modelRotationDegrees = modelRotationDegrees.truncatingRemainder(dividingBy: 360)
        var value = Android_Emulation_Control_PhysicalModelValue()
        value.target = .rotation
        value.value.data = [0, 0, modelRotationDegrees]
        _ = try await client.controller.setPhysicalModel(value)
    }

    public func shutDown() async throws {
        try await setVMState(.shutdown)
    }

    public func restart() async throws {
        try await setVMState(.reset)
    }

    private func setVMState(_ state: Android_Emulation_Control_VmRunState.RunState) async throws {
        var request = Android_Emulation_Control_VmRunState()
        request.state = state
        _ = try await client.controller.setVmState(request)
    }
}

public enum EmulatorSessionError: LocalizedError {
    case noEndpoint

    public var errorDescription: String? {
        "This emulator doesn't accept connections from Android Device Hub. Restart it from here."
    }
}

/// Streams screenshots into IOSurfaces.
enum ScreenStreamer {
    static func stream(
        client: EmulatorClient,
        maxPixels: PixelSize,
        shared: SharedFrameFile?,
        yield: @escaping @Sendable (ScreenFrame) -> Void
    ) async throws {
        var format = Android_Emulation_Control_ImageFormat()
        format.format = .rgba8888
        format.width = UInt32(max(1, maxPixels.width))
        format.height = UInt32(max(1, maxPixels.height))
        if let shared {
            format.transport.channel = .mmap
            format.transport.handle = shared.handle
        }
        let pool = SurfacePool()

        try await client.controller.streamScreenshot(format, options: EmulatorClient.largeMessageOptions) { response in
            for try await image in response.messages {
                try Task.checkCancellation()
                let width = Int(image.format.width)
                let height = Int(image.format.height)
                let byteCount = width * height * 4
                guard width > 0, height > 0, let surface = pool.surface(width: width, height: height) else { continue }

                if image.image.count >= byteCount {
                    image.image.withUnsafeBytes { buffer in
                        guard let base = buffer.baseAddress else { return }
                        PixelConversion.copyRGBA(
                            from: base, width: width, height: height, bottomUp: false, into: surface)
                    }
                } else if let shared, byteCount <= shared.capacity {
                    PixelConversion.copyRGBA(
                        from: shared.bytes, width: width, height: height, bottomUp: false, into: surface
                    )
                } else {
                    continue
                }
                yield(
                    ScreenFrame(
                        surface: surface,
                        width: width,
                        height: height,
                        rotation: DisplayRotation(rawValue: image.format.rotation.rotation.rawValue) ?? .portrait,
                        sequence: image.seq,
                        producedAt: image.timestampUs > 0
                            ? Date(timeIntervalSince1970: TimeInterval(image.timestampUs) / 1_000_000) : nil
                    ))
            }
        }
    }
}

/// Sends input over one long-lived `streamInputEvent` call, reconnecting if it drops.
/// Events sent while reconnecting are dropped, which is fine for pointer and key input.
final class InputChannel: @unchecked Sendable {
    private typealias Event = Android_Emulation_Control_InputEvent

    private let lock = NSLock()
    private var current: AsyncStream<Event>.Continuation?
    private var task: Task<Void, Never>?

    init(client: EmulatorClient) {
        let log = ADHLog.logger("EmulatorInput")
        task = Task.detached { [weak self] in
            while !Task.isCancelled {
                let (events, continuation) = AsyncStream<Event>.makeStream(bufferingPolicy: .bufferingNewest(256))
                self?.setCurrent(continuation)
                do {
                    _ = try await client.controller.streamInputEvent { writer in
                        for await event in events {
                            try await writer.write(event)
                        }
                    }
                    return
                } catch {
                    log.error("Input stream ended: \(error.localizedDescription, privacy: .public)")
                    try? await Task.sleep(for: .milliseconds(500))
                }
            }
        }
    }

    private func setCurrent(_ continuation: AsyncStream<Event>.Continuation?) {
        let previous = lock.withLock {
            defer { current = continuation }
            return current
        }
        previous?.finish()
    }

    func send(_ event: Android_Emulation_Control_InputEvent) {
        _ = lock.withLock { current }?.yield(event)
    }

    func finish() {
        task?.cancel()
        setCurrent(nil)
    }
}

/// Maps between the canvas and the emulator's coordinate systems.
enum InputMapping {
    /// Converts a point in the rotated frame to the emulator's touch coordinates (unrotated display pixels).
    static func devicePoint(_ point: CGPoint, rotation: DisplayRotation, displaySize: PixelSize) -> CGPoint {
        let width = CGFloat(displaySize.width)
        let height = CGFloat(displaySize.height)
        switch rotation {
        case .portrait:
            return point
        case .landscape:
            return CGPoint(x: width - point.y, y: point.x)
        case .reversePortrait:
            return CGPoint(x: width - point.x, y: height - point.y)
        case .reverseLandscape:
            return CGPoint(x: point.y, y: height - point.x)
        }
    }

    static func keyName(for key: NavigationKey) -> String {
        switch key {
        case .back: "GoBack"
        case .home: "GoHome"
        case .recents: "AppSwitch"
        case .power: "Power"
        case .volumeUp: "AudioVolumeUp"
        case .volumeDown: "AudioVolumeDown"
        }
    }
}
