import XCTest

/// Onboarding and New Emulator against a real SDK and a throwaway devices folder. Opt-in:
///
///     TEST_RUNNER_ADH_UI_SDK=/path/to/sdk xcodebuild test -project AndroidDeviceHub.xcodeproj \
///       -scheme AndroidDeviceHub -destination 'platform=macOS' -only-testing:AndroidDeviceHubUITests/SetupFlowUITests
///
/// The SDK needs the emulator package and at least one installed system image for API 36.
final class SetupFlowUITests: XCTestCase {
    private var sdk: String? { ProcessInfo.processInfo.environment["ADH_UI_SDK"] }
    private var avdHome: URL!
    private var app: XCUIApplication!

    @MainActor
    override func setUp() async throws {
        try XCTSkipIf(sdk == nil, "Set TEST_RUNNER_ADH_UI_SDK to run setup flow tests")
        let sdk = try XCTUnwrap(sdk)
        continueAfterFailure = false
        avdHome = FileManager.default.temporaryDirectory.appending(path: "adh-ui-avd-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: avdHome, withIntermediateDirectories: true)
        app = XCUIApplication()
        app.launchEnvironment["ANDROID_AVD_HOME"] = avdHome.path
        app.launchArguments += ["-sdk.rootOverride", sdk]
    }

    @MainActor
    override func tearDown() async throws {
        app?.terminate()
        try? FileManager.default.removeItem(at: avdHome)
    }

    @MainActor
    func testOnboardingReachesTheMainWindow() throws {
        app.launchArguments += ["-onboarding.completedVersion", "0"]
        app.launch()
        let window = app.windows.firstMatch
        XCTAssertTrue(window.staticTexts["Welcome to Android Device Hub"].waitForExistence(timeout: 20))

        // Step 1 passes with a working SDK; step 2 only appears without Platform Tools.
        let continueButton = window.buttons["Continue"]
        XCTAssertTrue(continueButton.waitForEnabled(timeout: 20))
        continueButton.click()
        if window.buttons["Skip"].waitForExistence(timeout: 3) {
            window.buttons["Skip"].click()
        }
        let open = window.buttons["Open Android Device Hub"]
        XCTAssertTrue(open.waitForExistence(timeout: 10))
        open.click()
        XCTAssertTrue(window.buttons["New Emulator…"].waitForExistence(timeout: 10), "Empty devices folder")
    }

    @MainActor
    func testNewEmulatorCreatesAnAVD() throws {
        app.launchArguments += ["-onboarding.completedVersion", "1"]
        app.launch()
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 20))
        app.menuBars.menuItems["New Emulator…"].click()

        let sheet = window.sheets.firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 10))
        // Every column of the hardware table fits inside the sheet.
        let table = sheet.tables.firstMatch
        XCTAssertTrue(table.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(table.frame.minX, sheet.frame.minX)
        XCTAssertLessThanOrEqual(table.frame.maxX, sheet.frame.maxX)

        let search = sheet.textFields["Search devices"]
        search.click()
        search.typeText("Pixel 8 Pro")
        let row = table.staticTexts["Pixel 8 Pro"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.click()
        sheet.buttons["Next"].click()

        let name = sheet.textFields["Name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.doubleClick()
        name.typeKey("a", modifierFlags: .command)
        name.typeText("UI Test Device")
        let finish = sheet.buttons["Finish"]
        XCTAssertTrue(finish.waitForEnabled(timeout: 60), "An installed system image should be selected")
        finish.click()

        XCTAssertTrue(window.outlines.firstMatch.staticTexts["UI Test Device"].waitForExistence(timeout: 10))
        let files = try FileManager.default.contentsOfDirectory(atPath: avdHome.path)
        XCTAssertTrue(files.contains { $0.hasSuffix(".ini") })
        XCTAssertTrue(files.contains { $0.hasSuffix(".avd") })
    }
}

extension XCUIElement {
    func waitForEnabled(timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if exists && isEnabled { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        return false
    }
}
