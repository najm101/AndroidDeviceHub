import XCTest

final class LaunchTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testMainWindowAppears() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-onboarding.completedVersion", "1"]
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 20))
    }
}
