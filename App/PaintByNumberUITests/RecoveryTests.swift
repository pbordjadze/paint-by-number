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
        attach(app, named: "recovery")

        regenerate.tap()
        XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: 120), "The regenerated painting didn't open")
        sleep(1)
        attach(app, named: "regenerated")
    }

    @MainActor
    private func attach(_ app: XCUIApplication, named name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
