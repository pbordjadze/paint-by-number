import XCTest

/// Feedback on a painting: a finger draws a mark, Next reviews it (the mark gets its own
/// comment field, which takes typing), Back returns to drawing, and Cancel › Discard returns
/// to painting.
final class FeedbackUITests: XCTestCase {
    @MainActor
    func testDrawReviewAndDiscard() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "gallery-open"]
        app.launch()
        XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: 90), "The painting didn't open")
        sleep(2)
        // The top bar where it has room (iPad), else the More menu.
        let give = app.buttons["Give Feedback"]
        if give.exists {
            give.tap()
        } else {
            app.buttons["More"].tap()
            app.buttons["Give Feedback…"].tap()
        }
        let next = app.buttons["feedback-next"]
        XCTAssertTrue(next.waitForExistence(timeout: 10), "Feedback didn't start")
        let undo = app.buttons["feedback-undo"]
        XCTAssertFalse(undo.isEnabled, "Undo is on before anything was drawn")

        let window = app.windows.firstMatch
        window.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.45))
            .press(forDuration: 0.05, thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.5)))
        let drawn = XCTWaiter.wait(
            for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: undo)], timeout: 10)
        attachScreenshot(of: app, named: "feedback-drawn")
        XCTAssertEqual(drawn, .completed, "A finger drag drew nothing")

        next.tap()
        sleep(2)
        // The screen as it is, without asking the app (should it stop answering, this shows where).
        attach(XCUIScreen.main.screenshot(), named: "feedback-next")
        XCTAssertTrue(app.navigationBars["Send Feedback"].waitForExistence(timeout: 10), "Next didn't open the review")
        let comment = app.descendants(matching: .any)["feedback-mark-1"]
        XCTAssertTrue(comment.waitForExistence(timeout: 10), "The mark has no comment field")
        comment.tap()
        comment.typeText("Too busy")
        XCTAssertTrue((comment.value as? String)?.contains("Too busy") == true, "The mark's comment can't be typed")
        attachScreenshot(of: app, named: "feedback-review")

        app.buttons["feedback-back"].tap()
        XCTAssertTrue(next.waitForExistence(timeout: 10), "Back didn't return to drawing")
        app.buttons["feedback-cancel"].tap()
        let discard = app.buttons["Discard"]
        XCTAssertTrue(discard.waitForExistence(timeout: 10), "Cancel didn't ask before throwing the mark away")
        discard.tap()
        XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: 10), "Discarding didn't return to painting")
        XCTAssertFalse(next.exists, "Feedback mode is still on")
    }
}
