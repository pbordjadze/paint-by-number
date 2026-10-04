import XCTest

/// A painting whose template file is damaged explains itself and can be regenerated from its
/// photo, after which it opens for painting.
final class RecoveryTests: XCTestCase {
    @MainActor
    func testDamagedPaintingRegenerates() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "gallery-damaged"]
        app.launch()
        let regenerate = app.buttons["Regenerate"]
        XCTAssertTrue(regenerate.waitForExistence(timeout: 90), "The recovery screen didn't appear")
        XCTAssertTrue(app.buttons["Delete Painting"].exists)
        attachScreenshot(of: app, named: "recovery")

        regenerate.tap()
        XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: 120), "The regenerated painting didn't open")
        sleep(1)
        attachScreenshot(of: app, named: "regenerated")
    }
}
