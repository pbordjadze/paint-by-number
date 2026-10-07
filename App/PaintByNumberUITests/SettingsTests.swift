import XCTest

/// Settings: About (version, acknowledgements), Paper, Line Weight and Painting Length.
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

    /// Acknowledgements opens on the sample pictures' credits; the algorithm ports follow them.
    @MainActor
    func testAcknowledgementsListTheAlgorithmPorts() throws {
        let app = openSettings()
        let row = app.descendants(matching: .any)["about-acknowledgements"]
        scroll(app, to: row)
        XCTAssertTrue(row.exists, "Settings has no Acknowledgements row")
        row.tap()

        XCTAssertTrue(app.navigationBars["Acknowledgements"].waitForExistence(timeout: 10))
        let pictures = app.descendants(matching: .any).matching(NSPredicate(format: "label ==[c] 'Pictures'")).firstMatch
        XCTAssertTrue(pictures.waitForExistence(timeout: 5), "Acknowledgements doesn't open on the Pictures section")
        for credit in ["mapbox/earcut", "mapbox/polylabel", "Peter Selinger"] {
            let entry = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", credit)).firstMatch
            // Past every picture's credit.
            scroll(app, to: entry, maxDrags: 30)
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
        XCTAssertTrue(shows(picker, "Dark"), "Choosing Dark didn't change the picker: \(describe(picker))")
        attachScreenshot(of: app, named: "settings-paper-dark")
        // The choice is stored in the simulator's defaults: put it back for the other tests.
        picker.tap()
        XCTAssertTrue(app.buttons["Light"].waitForExistence(timeout: 5))
        app.buttons["Light"].firstMatch.tap()
        XCTAssertTrue(shows(picker, "Light"), "Choosing Light didn't change the picker: \(describe(picker))")
    }

    /// Settings › Line Weight offers Fine, Regular and Bold, starts on Regular and keeps the choice.
    @MainActor
    func testLineWeightPickerChangesTheValue() throws {
        let app = openSettings()
        let picker = app.descendants(matching: .any)["settings-line-weight"]
        scroll(app, to: picker)
        XCTAssertTrue(picker.exists, "Settings has no Line Weight picker")
        XCTAssertTrue(describe(picker).contains("Regular"), "Line Weight doesn't start on Regular: \(describe(picker))")
        picker.tap()
        for choice in ["Fine", "Regular", "Bold"] {
            XCTAssertTrue(app.buttons[choice].waitForExistence(timeout: 5), "The Line Weight picker has no \(choice)")
        }
        app.buttons["Bold"].firstMatch.tap()
        XCTAssertTrue(shows(picker, "Bold"), "Choosing Bold didn't change the picker: \(describe(picker))")
        attachScreenshot(of: app, named: "settings-line-weight-bold")
        // The choice is stored in the simulator's defaults: put it back for the other tests.
        picker.tap()
        XCTAssertTrue(app.buttons["Regular"].waitForExistence(timeout: 5))
        app.buttons["Regular"].firstMatch.tap()
        XCTAssertTrue(shows(picker, "Regular"), "Choosing Regular didn't change the picker: \(describe(picker))")
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
        // The footer sits below the picker: a list only builds the rows it has scrolled to.
        let footer = app.staticTexts["painting-length-footer"]
        scroll(app, to: footer)
        XCTAssertTrue(footer.label.hasPrefix("Suggested settings aim for about half an hour"), "Relaxed footer: \(footer.label)")
        picker.tap()
        for choice in ["Quick", "Relaxed", "Detailed"] {
            XCTAssertTrue(app.buttons[choice].waitForExistence(timeout: 5), "The Painting Length picker has no \(choice)")
        }
        app.buttons["Quick"].firstMatch.tap()
        XCTAssertTrue(shows(picker, "Quick"), "Choosing Quick didn't change the picker: \(describe(picker))")
        let quickFooter = NSPredicate(format: "label == 'Suggested settings aim for about 15 minutes of painting.'")
        XCTAssertEqual(
            XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: quickFooter, object: footer)], timeout: 5), .completed,
            "Quick footer: \(footer.label)")
        attachScreenshot(of: app, named: "settings-painting-length-quick")

        // Back to the default, so later create-flow tests and screenshots aim for Relaxed.
        picker.tap()
        XCTAssertTrue(app.buttons["Relaxed"].waitForExistence(timeout: 5))
        app.buttons["Relaxed"].firstMatch.tap()
        XCTAssertTrue(shows(picker, "Relaxed"))
    }

    /// The picker's label and value together: how a menu picker's row reads.
    @MainActor
    private func describe(_ element: XCUIElement) -> String {
        "\(element.label) \(element.value as? String ?? "")"
    }

    /// Waits for a menu picker's row to read `choice` (in its label or its value, see `describe`).
    @MainActor
    private func shows(_ picker: XCUIElement, _ choice: String) -> Bool {
        let chosen = NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", choice, choice)
        return XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: chosen, object: picker)], timeout: 5) == .completed
    }

    /// The form is a lazy list: rows below the fold exist once they are scrolled into view. Each
    /// drag moves the list by four fifths of its frame, less than what shows below the navigation
    /// bar, and rests before lifting, so it can't fling past a row and leaves nothing to settle:
    /// swipes, with a second's wait for the row before each, took 138 s to reach the end of
    /// Acknowledgements on iPad (a form sheet), past every picture's credit and license text.
    @MainActor
    private func scroll(_ app: XCUIApplication, to element: XCUIElement, maxDrags: Int = 6) {
        let list = app.collectionViews.firstMatch
        let dragsList = list.exists
        var drags = 0
        while !element.exists && drags < maxDrags {
            if dragsList {
                list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9)).press(
                    forDuration: 0.05, thenDragTo: list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1)),
                    withVelocity: .default, thenHoldForDuration: 0.1)
            } else {
                app.swipeUp()
            }
            drags += 1
        }
        _ = element.waitForExistence(timeout: 2)
    }
}
