import AppKit
public import DeviceDomain
public import SwiftUI

/// Shows a live device screen and turns mouse, trackpad and keyboard input into device input.
///
/// Frames go straight to a CALayer, so SwiftUI isn't re-rendered for every frame.
public struct DeviceScreenView: NSViewRepresentable {
    private let session: any DeviceSession
    private let capturesKeyboard: Bool

    public init(session: any DeviceSession, capturesKeyboard: Bool) {
        self.session = session
        self.capturesKeyboard = capturesKeyboard
    }

    public func makeNSView(context: Context) -> ScreenLayerView {
        let view = ScreenLayerView()
        view.session = session
        view.capturesKeyboard = capturesKeyboard
        return view
    }

    public func updateNSView(_ view: ScreenLayerView, context: Context) {
        if view.session !== session {
            view.session = session
        }
        view.capturesKeyboard = capturesKeyboard
    }

    public static func dismantleNSView(_ view: ScreenLayerView, coordinator: ()) {
        view.stopStreaming()
    }
}

public final class ScreenLayerView: NSView {
    var session: (any DeviceSession)? {
        didSet { restartStreaming() }
    }

    var capturesKeyboard = true {
        didSet {
            if capturesKeyboard, window?.firstResponder !== self {
                window?.makeFirstResponder(self)
            }
        }
    }

    private var streamTask: Task<Void, Never>?
    private var requestedPixels = PixelSize(width: 0, height: 0)
    private var resizeTask: Task<Void, Never>?
    private var screenRotation: DisplayRotation = .portrait
    private var magnification: CGFloat = 0
    private var pressedModifiers: NSEvent.ModifierFlags = []

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.contentsGravity = .resizeAspect
        layer?.backgroundColor = NSColor.black.cgColor
        setAccessibilityRole(.image)
        setAccessibilityLabel("Device screen")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override public var isFlipped: Bool { true }
    override public var acceptsFirstResponder: Bool { capturesKeyboard }

    override public func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            stopStreaming()
        } else {
            restartStreaming()
            if capturesKeyboard { window?.makeFirstResponder(self) }
        }
    }

    override public func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        scheduleResize()
    }

    override public func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        scheduleResize()
    }

    // MARK: - Streaming

    func stopStreaming() {
        streamTask?.cancel()
        streamTask = nil
        resizeTask?.cancel()
    }

    /// Resizing streams restart the gRPC call, so wait until the size settles.
    private func scheduleResize() {
        resizeTask?.cancel()
        resizeTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled, let self else { return }
            if targetPixels() != requestedPixels { restartStreaming() }
        }
    }

    private func targetPixels() -> PixelSize {
        guard let session else { return PixelSize(width: 0, height: 0) }
        let scale = window?.backingScaleFactor ?? 2
        let display = session.displaySize
        let longest = CGFloat(max(display.width, display.height))
        // Request a square bound so rotation doesn't need a new stream; never exceed the device size.
        let viewLongest = max(bounds.width, bounds.height) * scale
        let side = Int(min(longest, max(viewLongest, 320)).rounded())
        return PixelSize(width: side, height: side)
    }

    private func restartStreaming() {
        stopStreaming()
        guard let session, window != nil else { return }
        let pixels = targetPixels()
        requestedPixels = pixels
        let frames = session.frames(maxPixels: pixels)
        streamTask = Task { @MainActor [weak self] in
            for await frame in frames {
                guard let self else { return }
                self.show(frame)
            }
        }
    }

    private func show(_ frame: ScreenFrame) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // The surface pool rotates surfaces, so a new frame is normally a different object.
        // Reassigning the same surface wouldn't redraw, so clear it first in that case.
        if layer?.contents as AnyObject? === frame.surface {
            layer?.contents = nil
        }
        layer?.contents = frame.surface
        CATransaction.commit()
        screenRotation = frame.rotation
    }

    // MARK: - Coordinates

    /// The screen size in device pixels for the current orientation.
    private var orientedDisplaySize: CGSize {
        guard let size = session?.displaySize else { return .zero }
        return screenRotation.isLandscape
            ? CGSize(width: size.height, height: size.width)
            : CGSize(width: size.width, height: size.height)
    }

    /// The rect the aspect-fit screen image occupies inside the view.
    private var contentRect: CGRect {
        let display = orientedDisplaySize
        guard display.width > 0, display.height > 0 else { return bounds }
        let scale = min(bounds.width / display.width, bounds.height / display.height)
        let size = CGSize(width: display.width * scale, height: display.height * scale)
        return CGRect(
            x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2,
            width: size.width, height: size.height
        )
    }

    private func devicePoint(for event: NSEvent) -> CGPoint {
        let local = convert(event.locationInWindow, from: nil)
        let rect = contentRect
        let display = orientedDisplaySize
        let x = (local.x - rect.minX) / rect.width * display.width
        let y = (local.y - rect.minY) / rect.height * display.height
        return CGPoint(x: min(max(x, 0), display.width - 1), y: min(max(y, 0), display.height - 1))
    }

    // MARK: - Pointer input

    override public func mouseDown(with event: NSEvent) {
        if capturesKeyboard { window?.makeFirstResponder(self) }
        session?.touch(.began, at: devicePoint(for: event), pointerID: 0)
    }

    override public func mouseDragged(with event: NSEvent) {
        session?.touch(.moved, at: devicePoint(for: event), pointerID: 0)
    }

    override public func mouseUp(with event: NSEvent) {
        session?.touch(.ended, at: devicePoint(for: event), pointerID: 0)
    }

    override public func scrollWheel(with event: NSEvent) {
        let factor: Double = event.hasPreciseScrollingDeltas ? 1 : 10
        session?.scroll(
            deltaX: Double(event.scrollingDeltaX) * factor,
            deltaY: Double(event.scrollingDeltaY) * factor,
            at: devicePoint(for: event)
        )
    }

    /// Pinch on the trackpad becomes a two-finger touch around the pointer.
    override public func magnify(with event: NSEvent) {
        guard let session else { return }
        let center = devicePoint(for: event)
        let base = min(orientedDisplaySize.width, orientedDisplaySize.height) * 0.1
        switch event.phase {
        case .began:
            magnification = 0
            send(session, .began, center: center, spread: base)
        case .changed:
            magnification += event.magnification
            send(session, .moved, center: center, spread: base * max(0.2, 1 + magnification * 2))
        case .ended, .cancelled:
            send(session, .ended, center: center, spread: base * max(0.2, 1 + magnification * 2))
        default:
            break
        }
    }

    private func send(_ session: any DeviceSession, _ phase: PointerPhase, center: CGPoint, spread: CGFloat) {
        session.touch(phase, at: CGPoint(x: center.x - spread, y: center.y), pointerID: 1)
        session.touch(phase, at: CGPoint(x: center.x + spread, y: center.y), pointerID: 2)
    }

    // MARK: - Keyboard

    override public func keyDown(with event: NSEvent) {
        guard capturesKeyboard, !event.modifierFlags.contains(.command) else {
            super.keyDown(with: event)
            return
        }
        session?.key(KeyInput(macKeyCode: event.keyCode, isDown: true))
    }

    override public func keyUp(with event: NSEvent) {
        guard capturesKeyboard, !event.modifierFlags.contains(.command) else {
            super.keyUp(with: event)
            return
        }
        session?.key(KeyInput(macKeyCode: event.keyCode, isDown: false))
    }

    /// Shift, Control and Option are forwarded as key presses so shortcuts inside Android work.
    override public func flagsChanged(with event: NSEvent) {
        guard capturesKeyboard else { return super.flagsChanged(with: event) }
        let relevant: NSEvent.ModifierFlags = [.shift, .control, .option]
        let current = event.modifierFlags.intersection(relevant)
        let isDown = current.rawValue > pressedModifiers.rawValue
        pressedModifiers = current
        session?.key(KeyInput(macKeyCode: event.keyCode, isDown: isDown))
    }
}
