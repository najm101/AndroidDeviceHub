import CoreGraphics
public import DesignSystem
public import DeviceActionsUI
public import DeviceDomain
public import Foundation
public import Observation
public import SDKDomain
import VideoCanvas

/// Dependencies of the workspace, wired by the app.
@MainActor
public struct DeviceWorkspaceDependencies {
    public var repository: any DeviceRepository
    public var installs: any InstallCoordinating
    /// Finds the catalog package for a missing system image folder.
    public var packageForSysdir: @Sendable (String) async -> RemotePackage?
    /// Where screenshots and recordings are saved.
    public var captureFolder: () -> URL
    public var reveal: (URL) -> Void
    /// Tells the app to enter or leave the compact window.
    public var setCompact: (Bool) -> Void
    public var recordingQuality: () -> RecordingQuality

    public init(
        repository: any DeviceRepository,
        installs: any InstallCoordinating,
        packageForSysdir: @escaping @Sendable (String) async -> RemotePackage?,
        captureFolder: @escaping () -> URL,
        reveal: @escaping (URL) -> Void,
        setCompact: @escaping (Bool) -> Void,
        recordingQuality: @escaping () -> RecordingQuality = { .standard }
    ) {
        self.recordingQuality = recordingQuality
        self.repository = repository
        self.installs = installs
        self.packageForSysdir = packageForSysdir
        self.captureFolder = captureFolder
        self.reveal = reveal
        self.setCompact = setCompact
    }
}

/// The selected device's header, canvas and footer.
@MainActor
@Observable
public final class DeviceWorkspaceModel {
    public enum Zoom: Hashable, Sendable {
        case fit
        case scale(Double)

        static let steps: [Double] = [0.25, 0.5, 0.75, 1, 1.25, 1.5, 2]

        var percentage: String {
            switch self {
            case .fit: "Fit"
            case let .scale(value): value.formatted(.percent.precision(.fractionLength(0)))
            }
        }
    }

    public var actionRequest: DeviceActionRequest?
    public var errorMessage: String?
    public private(set) var isCompact = false
    public private(set) var zoom: Zoom = .fit
    public var capturesKeyboard = true
    /// The last saved screenshot or recording, shown in a short confirmation.
    private(set) var lastCapture: URL?
    private(set) var missingImagePackage: RemotePackage?
    private(set) var isLookingUpImage = false

    let deviceID: DeviceID
    let dependencies: DeviceWorkspaceDependencies
    let recorder = ScreenRecorder()

    public init(deviceID: DeviceID, dependencies: DeviceWorkspaceDependencies) {
        self.deviceID = deviceID
        self.dependencies = dependencies
    }

    var device: Device? { dependencies.repository.device(withID: deviceID) }
    var session: (any DeviceSession)? { dependencies.repository.session(for: deviceID) }
    var repository: any DeviceRepository { dependencies.repository }
    var installs: any InstallCoordinating { dependencies.installs }
    var isRecording: Bool { recorder.isRecording }
    var recordingStart: Date? { recorder.startDate }

    func availability(_ capability: Capability) -> Availability {
        // The compact window always fits the device to the window.
        if capability == .zoom, isCompact { return .hidden }
        return device?.availability(of: capability) ?? .hidden
    }

    /// The screen size override, once read from the device. Ignored while it describes another screen
    /// (a resizable emulator that just switched presets).
    var displayMetrics: DisplayMetrics? {
        guard let metrics = (repository.inspector(for: deviceID) as? any DisplayOverriding)?.knownDisplayMetrics
        else { return nil }
        if let size = session?.displaySize, size != metrics.physicalSize { return nil }
        return metrics
    }

    var resizable: (any ResizableDisplayControlling)? {
        guard availability(.resizableMode).isVisible else { return nil }
        return session as? any ResizableDisplayControlling
    }

    func setResizableMode(_ mode: ResizableMode) {
        guard let resizable, resizable.resizableMode != mode else { return }
        perform {
            try await resizable.setResizableMode(mode)
            await self.loadDisplayMetrics(force: true)
        }
    }

    /// The screen size to draw, in device pixels for the current orientation. It follows a size or
    /// density override, so the frame takes the shape and real-world size Android shows.
    public var orientedScreenSize: PixelSize? {
        guard let size = displayMetrics?.apparentSize ?? session?.displaySize ?? device?.screenSize else { return nil }
        guard session?.rotation.isLandscape == true else { return size }
        return PixelSize(width: size.height, height: size.width)
    }

    /// The part of the panel to show: all of it, or where Android draws an override size.
    var visibleScreenArea: CGRect {
        displayMetrics?.contentArea ?? CGRect(x: 0, y: 0, width: 1, height: 1)
    }

    /// Scales the frame's screen corners so they don't cut into an override's content.
    var screenCornerScale: CGFloat {
        CGFloat(displayMetrics?.cornerScale(panelCorner: Double(frameStyle.screenCornerFraction)) ?? 1)
    }

    /// Reads the device's screen override once ADB can reach it, or again when `force` is set.
    func loadDisplayMetrics(force: Bool = false) async {
        guard device?.availability(of: .displaySize).isAvailable == true,
            let controller = repository.inspector(for: deviceID) as? any DisplayOverriding,
            force || controller.knownDisplayMetrics == nil
        else { return }
        _ = try? await controller.displayMetrics()
    }

    /// The drawn frame around the screen.
    public var frameStyle: DeviceFrameStyle {
        guard let device else { return .phone }
        if let mode = resizable?.resizableMode {
            return mode.formFactor.frameStyle(isRound: false)
        }
        let profile = device.virtualDevice?.hardwareProfileID ?? ""
        let isSquare = profile.contains("square") || profile.contains("rect")
        return device.formFactor.frameStyle(isRound: !isSquare)
    }

    /// Width divided by height of the whole frame, for sizing the compact window.
    public var frameAspectRatio: Double? {
        guard let size = orientedScreenSize else { return nil }
        let footprint = frameStyle.footprint(forScreen: CGSize(width: size.width, height: size.height))
        return footprint.height > 0 ? footprint.width / footprint.height : nil
    }

    /// Sizes for the compact window, while it's on.
    public var compactLayout: CompactWindowLayout? {
        guard isCompact, let aspect = frameAspectRatio else { return nil }
        return CompactWindowLayout(deviceAspectRatio: aspect)
    }

    // MARK: - Lifecycle

    func start(_ option: StartOption) {
        perform { try await self.repository.start(self.deviceID, option: option) }
    }

    // MARK: - Missing image

    func shutDown() {
        perform { try await self.repository.shutDown(self.deviceID) }
    }

    func restart() {
        perform { try await self.repository.restart(self.deviceID) }
    }

    func lookUpMissingImage() async {
        guard case let .needsAttention(.missingSystemImage(sysdir)) = device?.state else {
            missingImagePackage = nil
            return
        }
        isLookingUpImage = true
        defer { isLookingUpImage = false }
        missingImagePackage = await dependencies.packageForSysdir(sysdir)
    }

    func inventoryChanged() async {
        await repository.reload()
        await lookUpMissingImage()
    }

    // MARK: - Canvas

    func zoomIn() { stepZoom(by: 1) }
    func zoomOut() { stepZoom(by: -1) }
    func zoomToFit() { zoom = .fit }

    func toggleCompact() {
        isCompact.toggle()
        dependencies.setCompact(isCompact)
    }

    /// Called by the app when compact mode ends for another reason (e.g. a new selection).
    public func exitCompact() {
        isCompact = false
    }

    func toggleKeyboardCapture() {
        capturesKeyboard.toggle()
    }

    private func stepZoom(by direction: Int) {
        let current: Double = if case let .scale(value) = zoom { value } else { 1 }
        let steps = Zoom.steps
        let index = steps.firstIndex { $0 >= current } ?? steps.count - 1
        let next = min(max(index + direction, 0), steps.count - 1)
        zoom = .scale(steps[next])
    }

    // MARK: - Device controls

    /// The footer's single rotate button turns the device a quarter turn to the left.
    func rotate() {
        rotate(.left)
    }

    func rotate(_ direction: RotationDirection) {
        guard let session else { return }
        perform { try await session.rotate(direction) }
    }

    func press(_ key: NavigationKey) {
        session?.press(key)
    }

    func takeScreenshot() {
        guard let session, let device else { return }
        perform {
            let data = try await session.screenshot()
            let url = self.captureURL(for: device, kind: "Screenshot", extension: "png")
            try data.write(to: url, options: .atomic)
            self.lastCapture = url
        }
    }

    func toggleRecording() {
        guard let session, let device else { return }
        if recorder.isRecording {
            perform {
                self.lastCapture = try await self.recorder.stop()
            }
        } else {
            recorder.start(
                session: session,
                to: captureURL(for: device, kind: "Recording", extension: "mp4"),
                quality: dependencies.recordingQuality()
            )
        }
    }

    func revealLastCapture() {
        lastCapture.map(dependencies.reveal)
    }

    func dismissCapture() {
        lastCapture = nil
    }

    private func captureURL(for device: Device, kind: String, extension fileExtension: String) -> URL {
        let folder = dependencies.captureFolder()
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let stamp = Date.now.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false))
            .replacingOccurrences(of: ":", with: ".")
        return folder.appending(path: "\(device.name) \(kind) \(stamp).\(fileExtension)", directoryHint: .notDirectory)
    }

    // MARK: - Errors

    private func perform(_ operation: @escaping () async throws -> Void) {
        Task {
            do {
                try await operation()
            } catch {
                show(error)
            }
        }
    }

    func show(_ error: any Error) {
        errorMessage = [
            error.localizedDescription,
            (error as? any LocalizedError)?.recoverySuggestion,
        ]
        .compactMap { $0 }
        .joined(separator: " ")
    }
}
