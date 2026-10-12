import XCTest

/// The create flow's draft in the gallery (`gallery-draft`: three paintings and the draft of The
/// Great Wave, refined with two changes): Continue Refining reopens the flow on it, closing the
/// flow keeps it, and Discard asks before it goes.
final class DraftUITests: XCTestCase {
    @MainActor
    func testContinueKeepsTheDraftAndDiscardRemovesIt() {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "gallery-draft", "-demoFixedPictures", "YES"]
        app.launch()
        let row = app.descendants(matching: .any)["draft-row"]
        XCTAssertTrue(row.waitForExistence(timeout: 120), "The gallery shows no draft")
        attachScreenshot(of: app, named: "draft-row")

        app.buttons["draft-continue"].tap()
        let refine = app.buttons["refine"]
        XCTAssertTrue(refine.waitForExistence(timeout: 30), "Continue Refining didn't open the create flow")
        XCTAssertTrue(
            waitFor(refine, toMatch: NSPredicate(format: "value == %@", "2 changes")),
            "The draft's refinements weren't put back: \(refine.value ?? "")")
        XCTAssertTrue(
            waitFor(refine, toMatch: NSPredicate(format: "isEnabled == true"), timeout: 120),
            "The resumed draft never became ready to refine again")
        attachScreenshot(of: app, named: "draft-resumed")

        app.buttons["Close"].tap()
        XCTAssertTrue(row.waitForExistence(timeout: 10), "Closing the create flow lost the draft")

        app.buttons["draft-discard"].tap()
        let confirm = app.buttons["Discard “The Great Wave”"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "Discard didn't ask for confirmation")
        XCTAssertTrue(row.exists, "The draft was discarded before confirming")
        attachScreenshot(of: app, named: "draft-discard-confirmation")
        confirm.tap()
        XCTAssertTrue(row.waitForNonExistence(timeout: 10), "The draft is still in the gallery")
    }
}
