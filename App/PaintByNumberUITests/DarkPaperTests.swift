import XCTest

/// The painting canvas follows the Paper preference and the system appearance. A debug launch
/// argument (`-tracePaper YES`) makes the canvas name the paper it resolved in its
/// accessibility identifier, and the preference is given as a launch argument too (Settings
/// writes the same key: `SettingsTests.testPaperPickerChangesTheValue`).
final class DarkPaperTests: XCTestCase {
    @MainActor
    func testLightPaperIsTheDefault() throws {
        let app = launchPainting([])
        XCTAssertTrue(app.descendants(matching: .any)["canvas-paper-light"].waitForExistence(timeout: 30), "The canvas isn't on light paper by default")
        XCTAssertFalse(app.descendants(matching: .any)["canvas-paper-dark"].exists)
    }

    @MainActor
    func testDarkPaperPreferenceReachesTheCanvas() throws {
        let app = launchPainting(["-paperAppearance", "dark"])
        XCTAssertTrue(app.descendants(matching: .any)["canvas-paper-dark"].waitForExistence(timeout: 30), "The canvas isn't on dark paper")
        attachScreenshot(of: app, named: "dark-paper-light-appearance")
    }

    /// Automatic follows the system appearance, live.
    @MainActor
    func testAutomaticPaperFollowsTheSystemAppearance() throws {
        let app = launchPainting(["-paperAppearance", "automatic"])
        defer { XCUIDevice.shared.appearance = .light }
        XCTAssertTrue(app.descendants(matching: .any)["canvas-paper-light"].waitForExistence(timeout: 30), "Automatic isn't light paper in light appearance")
        XCUIDevice.shared.appearance = .dark
        XCTAssertTrue(app.descendants(matching: .any)["canvas-paper-dark"].waitForExistence(timeout: 10), "Automatic didn't turn to dark paper in dark appearance")
        attachScreenshot(of: app, named: "dark-paper-automatic")
        XCUIDevice.shared.appearance = .light
        XCTAssertTrue(app.descendants(matching: .any)["canvas-paper-light"].waitForExistence(timeout: 10), "Automatic didn't return to light paper")
    }

    @MainActor
    private func launchPainting(_ arguments: [String]) -> XCUIApplication {
        XCUIDevice.shared.appearance = .light
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "paint", "-tracePaper", "YES"] + arguments
        app.launch()
        return app
    }
}
