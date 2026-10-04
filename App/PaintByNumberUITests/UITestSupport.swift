import XCTest

/// What every UI test shares: attachments the CI report keys on by name, a polling wait and the
/// way into Settings.
extension XCTestCase {
    @MainActor
    func attach(_ screenshot: XCUIScreenshot, named name: String) {
        let shot = XCTAttachment(screenshot: screenshot)
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    @MainActor
    func attachScreenshot(of app: XCUIApplication, named name: String) {
        attach(app.screenshot(), named: name)
    }

    /// The app's accessibility tree, for a failure's diagnosis.
    @MainActor
    func attachTree(of app: XCUIApplication, named name: String) {
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = name
        tree.lifetime = .keepAlways
        add(tree)
    }

    /// Polls `condition` four times a second until it holds or `timeout` passes.
    @MainActor
    func waitUntil(timeout: TimeInterval = 5, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            Thread.sleep(forTimeInterval: 0.25)
        }
        return condition()
    }

    /// Opens Settings the way a person does: from the gallery's toolbar.
    @MainActor
    func openSettings() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "gallery-empty"]
        app.launch()
        let button = app.buttons["Settings"]
        XCTAssertTrue(button.waitForExistence(timeout: 30), "The gallery has no Settings button")
        button.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 10), "The settings sheet didn't open")
        return app
    }
}
