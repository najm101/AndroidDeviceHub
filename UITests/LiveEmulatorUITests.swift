import XCTest

/// Drives a running emulator through the app. Opt-in, because it needs an emulator that the app can control:
///
///     emulator -avd <id> -grpc <port> -grpc-use-token &
///     TEST_RUNNER_ADH_LIVE_AVD="Smoke Test API 36" xcodebuild test ... -only-testing:AndroidDeviceHubUITests/LiveEmulatorUITests
final class LiveEmulatorUITests: XCTestCase {
    private var deviceName: String? { ProcessInfo.processInfo.environment["ADH_LIVE_AVD"] }
    private var captureFolder: URL!
    private var app: XCUIApplication!

    @MainActor
    override func setUp() async throws {
        try XCTSkipIf(deviceName == nil, "Set TEST_RUNNER_ADH_LIVE_AVD to run live emulator tests")
        continueAfterFailure = false
        captureFolder = FileManager.default.temporaryDirectory.appending(path: "adh-ui-captures-\(UUID().uuidString)")
        app = XCUIApplication()
        app.launchArguments += [
            "-onboarding.completedVersion", "1",
            "-preferences.captureFolder", captureFolder.path,
        ]
        app.launch()
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: captureFolder)
    }

    @MainActor
    func testInteractsWithRunningEmulator() throws {
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 20))
        let row = window.outlines.firstMatch.staticTexts[try XCTUnwrap(deviceName)]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.click()

        let screen = window.images["Device screen"]
        XCTAssertTrue(screen.waitForExistence(timeout: 15), "The live screen should appear")
        sleep(2)

        // Home, then tap Chrome on the launcher (second row, third icon on a Pixel home screen).
        window.buttons["Home"].click()
        sleep(1)
        screen.coordinate(withNormalizedOffset: CGVector(dx: 0.62, dy: 0.84)).click()
        XCTAssertTrue(waitForResumedActivity(containing: "chrome"), "Tapping the screen should open Chrome")

        window.buttons["Home"].click()
        XCTAssertTrue(waitForResumedActivity(containing: "launcher"), "Home should return to the launcher")

        // Screenshot lands in the capture folder.
        window.buttons["Screenshot"].click()
        XCTAssertTrue(
            waitFor {
                (try? FileManager.default.contentsOfDirectory(atPath: self.captureFolder.path))?.contains {
                    $0.hasSuffix(".png")
                } == true
            })

        // Each Rotate turns the screen a quarter turn; four bring it back to where it started.
        let portrait = screen.frame
        window.buttons["Rotate"].click()
        XCTAssertTrue(
            waitFor { screen.frame.width > screen.frame.height },
            "Rotating should show landscape (was \(portrait))")
        window.buttons["Rotate"].click()
        XCTAssertTrue(waitFor { screen.frame.height > screen.frame.width })
        window.buttons["Rotate"].click()
        XCTAssertTrue(waitFor { screen.frame.width > screen.frame.height })
        window.buttons["Rotate"].click()
        XCTAssertTrue(waitFor { screen.frame.height > screen.frame.width })
    }

    // MARK: - Helpers

    private func waitFor(timeout: TimeInterval = 10, _ condition: @escaping () -> Bool) -> Bool {
        let deadline = Date.now.addingTimeInterval(timeout)
        while Date.now < deadline {
            if condition() { return true }
            RunLoop.current.run(until: .now.addingTimeInterval(0.25))
        }
        return false
    }

    private func waitForResumedActivity(containing text: String) -> Bool {
        waitFor(timeout: 15) {
            self.adb(["shell", "dumpsys", "activity", "activities"])
                .split(separator: "\n")
                .first { $0.contains("ResumedActivity") }?
                .lowercased()
                .contains(text) == true
        }
    }

    private func adb(_ arguments: [String]) -> String {
        let home = ProcessInfo.processInfo.environment["ANDROID_HOME"] ?? "\(NSHomeDirectory())/Library/Android/sdk"
        let process = Process()
        process.executableURL = URL(filePath: "\(home)/platform-tools/adb")
        process.arguments =
            ["-s", ProcessInfo.processInfo.environment["ADH_LIVE_SERIAL"] ?? "emulator-5554"] + arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        do {
            try process.run()
        } catch {
            return ""
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }
}
