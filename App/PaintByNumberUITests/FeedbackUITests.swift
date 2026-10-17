import XCTest

/// Feedback on a painting: a finger draws a mark, the highlighter can be picked, Next reviews
/// the mark (it gets its own comment field, which takes typing), Back returns to drawing, and
/// Cancel › Discard returns to painting. Send goes to the developers through the relay, which
/// Debug builds never reach: `-feedback-upload` picks a stub that succeeds (the default), fails
/// (`fail`) or fails the first time (`fail-once`), so the thanks, the alert and Try Again run.
final class FeedbackUITests: XCTestCase {
    @MainActor
    func testDrawReviewAndDiscard() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "gallery-open"]
        app.launch()
        XCTAssertTrue(app.buttons["Back"].waitForExistence(timeout: 90), "The painting didn't open")
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
        let highlighter = app.buttons["feedback-tool-highlighter"]
        highlighter.tap()
        XCTAssertTrue(waitFor(highlighter, toMatch: NSPredicate(format: "isSelected == true")), "The highlighter didn't become the tool")

        next.tap()
        XCTAssertTrue(app.navigationBars["Send Feedback"].waitForExistence(timeout: 10), "Next didn't open the review")
        let comment = app.descendants(matching: .any)["feedback-mark-1"]
        XCTAssertTrue(comment.waitForExistence(timeout: 10), "The mark has no comment field")
        comment.tap()
        comment.typeText("Too busy")
        XCTAssertTrue(
            waitFor(comment, toMatch: NSPredicate(format: "value CONTAINS %@", "Too busy")),
            "The mark's comment can't be typed: \(comment.value ?? "")")
        attachScreenshot(of: app, named: "feedback-review")

        app.buttons["feedback-back"].tap()
        XCTAssertTrue(next.waitForExistence(timeout: 10), "Back didn't return to drawing")
        let cancel = app.buttons["feedback-cancel"]
        let source = cancel.frame
        cancel.tap()
        let discard = app.buttons["Discard"]
        XCTAssertTrue(discard.waitForExistence(timeout: 10), "Cancel didn't ask before throwing the mark away")
        // It points at the Cancel button it was asked from.
        checkDialog(showing: ["Discard Your Feedback?", "Your marks and notes will be lost."], pointsAt: source, "feedback-discard", in: app)
        discard.tap()
        XCTAssertTrue(app.buttons["Back"].waitForExistence(timeout: 10), "Discarding didn't return to painting")
        XCTAssertFalse(next.exists, "Feedback mode is still on")
    }

    // MARK: Send

    private let failedTitle = "Couldn’t Send Feedback"

    /// The toast that thanks for a sent feedback (its label also names its symbol).
    @MainActor
    private func thanks(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Feedback sent. Thank you!")).firstMatch
    }

    /// The review sheet over `paint-feedback-review`'s painting, marks and note, its Send going to
    /// the stub that `mode` names (the one that succeeds when nil).
    @MainActor
    private func openReview(uploading mode: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "paint-feedback-review"] + (mode.map { ["-feedback-upload", $0] } ?? [])
        app.launch()
        XCTAssertTrue(app.navigationBars["Send Feedback"].waitForExistence(timeout: 120), "The review didn't open")
        XCTAssertTrue(app.buttons["feedback-send"].waitForExistence(timeout: 10), "The review has no Send")
        return app
    }

    @MainActor
    func testSendThanksThePainterAndEndsFeedback() throws {
        let app = openReview()
        attachScreenshot(of: app, named: "feedback-review-send")
        app.buttons["feedback-send"].tap()
        XCTAssertTrue(thanks(in: app).waitForExistence(timeout: 60), "A sent feedback wasn't thanked")
        attachScreenshot(of: app, named: "feedback-sent")
        XCTAssertFalse(app.navigationBars["Send Feedback"].exists, "The review sheet stayed up after sending")
        XCTAssertFalse(app.buttons["feedback-next"].exists, "Feedback mode is still on after sending")
    }

    /// A send that fails asks what to do; Cancel keeps the note and the marks to send another way.
    @MainActor
    func testFailedSendOffersTryAgainShareInsteadAndCancel() throws {
        let app = openReview(uploading: "fail")
        app.buttons["feedback-send"].tap()
        let alert = app.alerts[failedTitle]
        XCTAssertTrue(alert.waitForExistence(timeout: 60), "A send that failed showed no alert")
        attachScreenshot(of: app, named: "feedback-send-failed")
        for button in ["Try Again", "Share Instead", "Cancel"] {
            XCTAssertTrue(alert.buttons[button].exists, "The alert has no \(button) button")
        }
        XCTAssertFalse(thanks(in: app).exists, "A failed send was thanked")

        alert.buttons["Cancel"].tap()
        XCTAssertTrue(alert.waitForNonExistence(timeout: 10), "Cancel left the alert up")
        XCTAssertTrue(app.navigationBars["Send Feedback"].exists, "Cancel closed the review")
        let note = app.descendants(matching: .any)["feedback-note"]
        XCTAssertTrue(
            waitFor(note, toMatch: NSPredicate(format: "value CONTAINS %@", "The sky reads beautifully")),
            "Cancel lost the note: \(note.value ?? "")")
        XCTAssertTrue(app.descendants(matching: .any)["feedback-mark-1"].exists, "Cancel lost the marks")
        XCTAssertTrue(app.buttons["feedback-send"].isEnabled, "Send stayed off after Cancel")
    }

    /// Try Again sends the same files again: the stub fails only the first try, and the second is thanked.
    @MainActor
    func testTryAgainSendsAfterAFailure() throws {
        let app = openReview(uploading: "fail-once")
        app.buttons["feedback-send"].tap()
        let alert = app.alerts[failedTitle]
        XCTAssertTrue(alert.waitForExistence(timeout: 60), "The first try didn't fail")
        alert.buttons["Try Again"].tap()
        XCTAssertTrue(thanks(in: app).waitForExistence(timeout: 60), "Try Again wasn't thanked")
        XCTAssertFalse(app.navigationBars["Send Feedback"].exists, "The review sheet stayed up after sending")
    }
}
