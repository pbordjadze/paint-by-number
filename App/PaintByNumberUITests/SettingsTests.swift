import XCTest

/// Settings › About: the app version and the acknowledgements; Settings › Paper.
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

    /// Settings › Paper offers Light, Dark and Automatic, starts on Light and keeps the choice.
    @MainActor
    func testPaperPickerChangesTheValue() throws {
        let app = openSettings()
        let picker = app.descendants(matching: .any)["paper-appearance"]
        XCTAssertTrue(picker.waitForExistence(timeout: 10), "Settings has no Paper picker")
        XCTAssertTrue(describe(picker).contains("Light"), "Paper doesn't start on Light: \(describe(picker))")
        picker.tap()
        for choice in ["Light", "Dark", "Automatic"] {
            XCTAssertTrue(app.buttons[choice].waitForExistence(timeout: 5), "The Paper picker has no \(choice)")
        }
        app.buttons["Dark"].firstMatch.tap()
        let chosen = NSPredicate(format: "label CONTAINS 'Dark' OR value CONTAINS 'Dark'")
        let result = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: chosen, object: picker)], timeout: 5)
        XCTAssertEqual(result, .completed, "Choosing Dark didn't change the picker: \(describe(picker))")
        attachScreenshot(of: app, named: "settings-paper-dark")
    }

    /// Settings › Painting Length offers Quick, Relaxed and Detailed, starts on Relaxed, keeps
    /// the choice and says what it aims for.
    @MainActor
    func testPaintingLengthPickerChangesTheValue() throws {
        let app = openSettings()
        let picker = app.descendants(matching: .any)["painting-length"]
        scroll(app, to: picker)
        XCTAssertTrue(picker.exists, "Settings has no Painting Length picker")
        XCTAssertTrue(describe(picker).contains("Relaxed"), "Painting Length doesn't start on Relaxed: \(describe(picker))")
        XCTAssertTrue(app.staticTexts["Suggested settings aim for about an hour of painting."].waitForExistence(timeout: 5))
        picker.tap()
        for choice in ["Quick", "Relaxed", "Detailed"] {
            XCTAssertTrue(app.buttons[choice].waitForExistence(timeout: 5), "The Painting Length picker has no \(choice)")
        }
        app.buttons["Quick"].firstMatch.tap()
        let chosen = NSPredicate(format: "label CONTAINS 'Quick' OR value CONTAINS 'Quick'")
        let result = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: chosen, object: picker)], timeout: 5)
        XCTAssertEqual(result, .completed, "Choosing Quick didn't change the picker: \(describe(picker))")
        XCTAssertTrue(app.staticTexts["Suggested settings aim for about half an hour of painting."].waitForExistence(timeout: 5))
        attachScreenshot(of: app, named: "settings-painting-length-quick")

        // Back to the default, so later create-flow tests and screenshots aim for Relaxed.
        picker.tap()
        XCTAssertTrue(app.buttons["Relaxed"].waitForExistence(timeout: 5))
        app.buttons["Relaxed"].firstMatch.tap()
        XCTAssertEqual(
            XCTWaiter.wait(for: [XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "label CONTAINS 'Relaxed' OR value CONTAINS 'Relaxed'"), object: picker)],
                timeout: 5),
            .completed)
    }

    /// The picker's label and value together: how a menu picker's row reads.
    @MainActor
    private func describe(_ element: XCUIElement) -> String {
        "\(element.label) \(element.value as? String ?? "")"
    }

    /// Color Names offers Playful and Plain, Playful by default.
    @MainActor
    func testColorNamesPickerOffersPlayfulAndPlain() throws {
        let app = openSettings()
        let picker = app.descendants(matching: .any)["settings-color-names"]
        scroll(app, to: picker)
        XCTAssertTrue(picker.exists, "Settings has no Color Names row")
        XCTAssertEqual(picker.value as? String, "Playful")
        picker.tap()
        let plain = app.buttons["Plain"]
        XCTAssertTrue(plain.waitForExistence(timeout: 10), "The picker has no Plain option")
        XCTAssertTrue(app.buttons["Playful"].exists, "The picker has no Playful option")
        plain.tap()
        XCTAssertEqual(picker.value as? String, "Plain")
        attachScreenshot(of: app, named: "settings-color-names")
        // The choice is stored in the simulator's defaults: put it back for the other tests.
        picker.tap()
        let playful = app.buttons["Playful"]
        XCTAssertTrue(playful.waitForExistence(timeout: 10))
        playful.tap()
        XCTAssertEqual(picker.value as? String, "Playful")
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
