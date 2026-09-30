import XCTest

/// Settings › About: the app version and the acknowledgements.
final class SettingsTests: XCTestCase {
    @MainActor
    func testAboutShowsTheVersion() throws {
        let app = openSettings()
        let version = app.descendants(matching: .any)["about-version"]
        scroll(app, to: version)
        attachScreenshot(of: app, named: "settings-about")
        XCTAssertTrue(version.exists, "Settings has no version row")
        let text = "\(version.label) \(version.value as? String ?? "")"
        XCTAssertNotNil(
            text.range(of: #"\d+(\.\d+)* \(\d+\)"#, options: .regularExpression),
            "The version row doesn't read like \"1.0 (1)\": \(text)")
    }

    @MainActor
    func testAcknowledgementsListTheAlgorithmPorts() throws {
        let app = openSettings()
        let row = app.descendants(matching: .any)["about-acknowledgements"]
        scroll(app, to: row)
        XCTAssertTrue(row.exists, "Settings has no Acknowledgements row")
        row.tap()

        XCTAssertTrue(app.navigationBars["Acknowledgements"].waitForExistence(timeout: 10))
        for credit in ["mapbox/earcut", "mapbox/polylabel", "potrace 1.16"] {
            let entry = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", credit)).firstMatch
            scroll(app, to: entry)
            XCTAssertTrue(entry.exists, "Acknowledgements doesn't credit \(credit)")
        }
        attachScreenshot(of: app, named: "acknowledgements")
    }

    /// Opens Settings the way a person does: from the gallery's toolbar.
    @MainActor
    private func openSettings() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "gallery-empty"]
        app.launch()
        let button = app.buttons["Settings"]
        XCTAssertTrue(button.waitForExistence(timeout: 30), "The gallery has no Settings button")
        button.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 10), "The settings sheet didn't open")
        return app
    }

    /// The form is a lazy list: rows below the fold exist once they are scrolled into view.
    @MainActor
    private func scroll(_ app: XCUIApplication, to element: XCUIElement) {
        var swipes = 0
        while !element.waitForExistence(timeout: 1) && swipes < 6 {
            app.swipeUp()
            swipes += 1
        }
    }

    @MainActor
    private func attachScreenshot(of app: XCUIApplication, named name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
