import XCTest

/// Both sections of the contents page open native reader pages, including at large text sizes.
final class MarginariumReaderUITests: XCTestCase {
    @MainActor
    func testChapterAndAppendixOpenFromContents() {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "marginarium"]
        app.launch()
        XCTAssertTrue(app.navigationBars["The Marginarium"].waitForExistence(timeout: 15))
        openEntry("lampBrush", in: app)
        XCTAssertTrue(app.navigationBars["The Lamp Picks Up a Brush"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["A Mac arrives, with a plan for the guardians to play."].exists)
        attachScreenshot(of: app, named: "marginarium-reader-chapter")
        app.navigationBars["The Lamp Picks Up a Brush"].buttons.firstMatch.tap()
        openEntry("thirtySixColors", in: app)
        XCTAssertTrue(app.navigationBars["Thirty-Six Colors"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["The Moon struck every name with daylight in it, four times."].exists)
        attachScreenshot(of: app, named: "marginarium-reader-appendix")
    }

    @MainActor
    func testReaderAtAccessibilitySizeWithLongText() {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "marginarium-chapter-long-text", "-NSDoubleLocalizedStrings", "YES",
                               "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        let reader = app.scrollViews["marginarium-reader"]
        XCTAssertTrue(reader.waitForExistence(timeout: 15))
        // At this size the title itself wraps; scrolling must still reach the quotation.
        let passage = reader.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Before any guardian got a pet")).firstMatch
        for _ in 0..<12 {
            if passage.exists && passage.isHittable { break }
            reader.swipeUp()
        }
        XCTAssertTrue(passage.exists)
        XCTAssertTrue(passage.isHittable)
        attachScreenshot(of: app, named: "marginarium-reader-accessibility-long-text")
    }

    @MainActor
    private func openEntry(_ id: String, in app: XCUIApplication) {
        let contents = app.scrollViews["marginarium-contents"]
        XCTAssertTrue(contents.waitForExistence(timeout: 10))
        let link = app.buttons["marginarium-entry-\(id)"]
        for _ in 0..<15 {
            if link.exists && link.isHittable { break }
            contents.swipeUp()
        }
        XCTAssertTrue(link.exists && link.isHittable, "Contents entry isn't reachable: \(id)")
        link.tap()
        XCTAssertTrue(app.scrollViews["marginarium-reader"].waitForExistence(timeout: 10))
    }
}
