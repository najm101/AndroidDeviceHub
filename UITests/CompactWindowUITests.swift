import AppKit
import XCTest

/// The compact window: no sidebar or inspector, the device fills the window with an even
/// margin, and Expand restores the previous window.
///
/// Resizing isn't covered here: XCUITest drags don't reach AppKit's window resize handling. The size
/// math is unit-tested (`CompactWindowLayoutTests`); check live resizing by dragging an edge.
///
/// Opt-in, because it needs a device (it may be stopped):
///
///     TEST_RUNNER_ADH_UI_AVD="Smoke Test API 36" xcodebuild test ... -only-testing:AndroidDeviceHubUITests/CompactWindowUITests
final class CompactWindowUITests: XCTestCase {
    /// `CompactWindowLayout.margin`, with room for antialiasing and the frame's side buttons.
    private let margin: CGFloat = 12
    private let tolerance: CGFloat = 6

    private var deviceName: String? { ProcessInfo.processInfo.environment["ADH_UI_AVD"] }
    private var app: XCUIApplication!
    private var window: XCUIElement!
    private var snapshots: URL!

    @MainActor
    override func setUp() async throws {
        try XCTSkipIf(deviceName == nil, "Set TEST_RUNNER_ADH_UI_AVD to run compact window tests")
        continueAfterFailure = false
        snapshots = FileManager.default.temporaryDirectory.appending(path: "adh-compact-\(UUID().uuidString)")
        app = XCUIApplication()
        // The saved frame (not restored window state) decides where the window opens.
        app.launchArguments += ["-onboarding.completedVersion", "1", "-ApplePersistenceIgnoreState", "YES"]
        app.launch()
        window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 20))
        // Wide enough that no toolbar item moves into the overflow menu.
        snapshot(resizingTo: "1300x1000")
        let row = window.outlines.firstMatch.staticTexts[try XCTUnwrap(deviceName)]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.click()
        // Compact mode needs a running device; the emulator keeps running between tests.
        let compact = window.buttons["Compact Window"]
        XCTAssertTrue(compact.waitForExistence(timeout: 10))
        if !compact.isEnabled, window.buttons["Start"].waitForExistence(timeout: 5) {
            window.buttons["Start"].click()
        }
        XCTAssertTrue(waitFor(timeout: 180) { compact.isEnabled }, "The device should start")
        sleep(2)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: snapshots)
    }

    @MainActor
    func testCompactWindowShowsOnlyTheDeviceControls() throws {
        let normal = window.frame
        enterCompact()

        XCTAssertFalse(window.outlines.firstMatch.exists, "The sidebar should be gone")
        XCTAssertFalse(window.buttons["Inspector"].exists, "The inspector toggle should be gone")
        XCTAssertFalse(window.buttons["Zoom In"].exists)
        XCTAssertTrue(window.menuButtons["Device"].exists || window.buttons["Device"].exists)
        for button in ["Rotate", "Back", "Home", "Recents", "Record", "Screenshot"] {
            XCTAssertTrue(window.buttons[button].exists, "\(button) should be in the compact footer")
        }
        try assertDeviceFills(label: "entered")

        window.buttons["Exit Compact Window"].click()
        XCTAssertTrue(waitFor { self.window.frame == normal }, "Expected \(normal), got \(window.frame)")
        XCTAssertTrue(window.outlines.firstMatch.exists)
    }

    @MainActor
    func testFooterPutsNavigationInTheCenter() {
        let footer = ["Rotate", "Back", "Home", "Recents", "Record", "Screenshot"].map { window.buttons[$0].frame }
        XCTAssertEqual(footer.map(\.minX), footer.map(\.minX).sorted(), "Footer order")
        let home = window.buttons["Home"].frame
        let canvasCenter = (window.buttons["Rotate"].frame.minX + window.buttons["Screenshot"].frame.maxX) / 2
        XCTAssertEqual(home.midX, canvasCenter, accuracy: 2, "Home should be centered under the canvas")
    }

    @MainActor
    func testEnteringFromAnyWindowFitsTheDevice() throws {
        window.buttons["Zoom In"].click()
        window.buttons["Zoom In"].click()
        window.typeKey("i", modifierFlags: [.command, .option])
        snapshot(resizingTo: "1300x1000")
        enterCompact()
        try assertDeviceFills(label: "from-zoomed-tall")
        window.buttons["Exit Compact Window"].click()

        snapshot(resizingTo: "900x600")
        enterCompact()
        try assertDeviceFills(label: "from-small")
    }

    // MARK: - Helpers

    @MainActor
    private func enterCompact() {
        window.buttons["Compact Window"].click()
        let entered = window.buttons["Exit Compact Window"].waitForExistence(timeout: 5)
        if !entered {
            let tree = XCTAttachment(string: app.debugDescription)
            tree.name = "Accessibility tree"
            tree.lifetime = .keepAlways
            add(tree)
        }
        XCTAssertTrue(entered, "The compact window should open")
        sleep(1)
    }

    /// The device should span the canvas with only the margin beside it (or above and below it).
    @MainActor
    private func assertDeviceFills(label: String) throws {
        let file = try XCTUnwrap(snapshot(label: label), "No snapshot for \(label)")
        let image = try XCTUnwrap(NSImage(contentsOf: file)?.representations.first as? NSBitmapImageRep)
        let scale = CGFloat(image.pixelsWide) / window.frame.width
        let gaps = Self.sideGaps(in: image, scale: scale)
        let attachment = XCTAttachment(contentsOfFile: file)
        attachment.name = "\(label) \(Int(window.frame.width))x\(Int(window.frame.height)) gaps \(gaps)"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertEqual(gaps.left, margin, accuracy: tolerance, "\(label): left gap")
        XCTAssertEqual(gaps.right, margin, accuracy: tolerance, "\(label): right gap")
    }

    /// Asks the Debug build to write PNGs of its windows (optionally resizing the main window first)
    /// and returns the main window's.
    @discardableResult
    private func snapshot(label: String = UUID().uuidString, resizingTo size: String? = nil) -> URL? {
        let folder = snapshots.appending(path: label)
        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name("io.github.najm101.AndroidDeviceHub.debugSnapshot"),
            object: folder.path + (size.map { "|\($0)" } ?? ""),
            userInfo: nil,
            deliverImmediately: true
        )
        _ = waitFor { (try? FileManager.default.contentsOfDirectory(atPath: folder.path))?.isEmpty == false }
        sleep(1)
        let name = deviceName.map { "\($0).png" }
        return (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil))?
            .first { $0.lastPathComponent == name }
    }

    /// Empty space left and right of the device on the middle row of the canvas, in points.
    private static func sideGaps(in image: NSBitmapImageRep, scale: CGFloat) -> (left: CGFloat, right: CGFloat) {
        func luminance(_ x: Int, _ y: Int) -> CGFloat {
            guard let color = image.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { return 0 }
            return color.redComponent * 0.3 + color.greenComponent * 0.59 + color.blueComponent * 0.11
        }
        let width = image.pixelsWide
        let row = image.pixelsHigh / 2
        let edge = Int(2 * scale)
        let background = luminance(edge, row)
        let isDevice = { (x: Int) in abs(luminance(x, row) - background) > 0.02 }
        let left = (edge..<width).first(where: isDevice) ?? width
        let right = (0..<(width - edge)).reversed().first(where: isDevice).map { width - 1 - $0 } ?? width
        return (CGFloat(left) / scale, CGFloat(right) / scale)
    }

    private func waitFor(timeout: TimeInterval = 5, _ condition: @escaping () -> Bool) -> Bool {
        let deadline = Date.now.addingTimeInterval(timeout)
        while Date.now < deadline {
            if condition() { return true }
            RunLoop.current.run(until: .now.addingTimeInterval(0.2))
        }
        return false
    }
}
