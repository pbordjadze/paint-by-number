import XCTest

/// A painting someone sent with Send Template… (a `.moonlight` file) opened in the app: it joins
/// the gallery as a new painting, blank, and opens; a damaged one says so and adds nothing.
final class ReceivePaintingTests: XCTestCase {
    @MainActor
    func testSentPaintingOpensAsANewBlankPainting() {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "gallery-received"]
        app.launch()

        let badge = app.staticTexts.matching(NSPredicate(format: "label ENDSWITH 'percent painted'")).firstMatch
        XCTAssertTrue(badge.waitForExistence(timeout: 120), "The sent painting didn't open")
        XCTAssertTrue(badge.label.range(of: #"(^|, )0 percent painted$"#, options: .regularExpression) != nil,
                      "The sent painting isn't blank: \(badge.label)")
        attachScreenshot(of: app, named: "received-painting")

        XCTAssertTrue(waitUntil(timeout: 15) { app.buttons["Back"].isHittable })
        app.buttons["Back"].tap()
        XCTAssertTrue(app.buttons["The Great Wave"].firstMatch.waitForExistence(timeout: 10), "The sent painting isn't in the gallery")
        let counts = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "1 ready to paint")).firstMatch
        XCTAssertTrue(counts.waitForExistence(timeout: 10), "The gallery doesn't count the sent painting as ready to paint")
    }

    @MainActor
    func testDamagedPaintingFileSaysSoAndAddsNothing() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "Broken Template.moonlight")
        try Data("PBMS not really a painting".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let app = XCUIApplication()
        app.launchArguments = ["-demo", "gallery-empty", "-openFile", url.path]
        app.launch()

        let alert = app.alerts["Couldn’t Open Painting"]
        XCTAssertTrue(alert.waitForExistence(timeout: 30), "No alert for a damaged painting file")
        XCTAssertTrue(alert.staticTexts["The file is damaged, or isn’t a painting."].exists)
        attachScreenshot(of: app, named: "received-painting-damaged")
        alert.buttons["OK"].tap()
        XCTAssertTrue(alert.waitForNonExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Broken"].exists)
        XCTAssertFalse(app.buttons["Broken Template"].exists)
    }
}
