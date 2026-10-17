import XCTest

/// The gentle tips: the invitation beside the gear on the shelf's first visit, and what each answer
/// leads to. (`gallery-tips-invitation` is the first launch's gallery, the two starters unpainted,
/// with tips left to the scenario: every other launch hides them, and starts with no answer.)
final class GentleTipsUITests: XCTestCase {
    /// How long the first launch's gallery takes to make its starters, and the invitation to come up
    /// beside them.
    private static let invitationTimeout: TimeInterval = 150

    @MainActor
    private func launchInvitation() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "gallery-tips-invitation"]
        app.launch()
        return app
    }

    /// The note comes up once the starters are in view, and offers its two buttons.
    @MainActor
    func testTheInvitationOffersShowTipsAndNoThanks() throws {
        let app = launchInvitation()
        let title = app.staticTexts["Small Tips?"]
        XCTAssertTrue(title.waitForExistence(timeout: Self.invitationTimeout), "The invitation never came up")
        attachScreenshot(of: app, named: "invitation")
        XCTAssertTrue(
            app.staticTexts["Would you like small tips as you go? You can change this in Settings."].exists,
            "The invitation doesn't say what it asks")
        XCTAssertTrue(app.buttons["Show Tips"].exists, "The invitation has no Show Tips")
        XCTAssertTrue(app.buttons["No Thanks"].exists, "The invitation has no No Thanks")
    }

    /// Show Tips leads to the first tip: a page is waiting in Ready to Paint. The invitation is
    /// gone for good.
    @MainActor
    func testShowTipsLeadsToAPageIsWaiting() throws {
        let app = launchInvitation()
        let show = app.buttons["Show Tips"]
        XCTAssertTrue(show.waitForExistence(timeout: Self.invitationTimeout), "The invitation never came up")
        show.tap()
        let tip = app.staticTexts["A Page Is Waiting"]
        XCTAssertTrue(tip.waitForExistence(timeout: 60), "Show Tips led to no tip")
        attachScreenshot(of: app, named: "page-is-waiting")
        XCTAssertTrue(
            app.staticTexts["Tap a page in Ready to Paint to begin. Nothing needs setting up first."].exists,
            "The tip doesn't say what to do")
        XCTAssertTrue(app.staticTexts["Small Tips?"].waitForNonExistence(timeout: 10), "The invitation stayed after it was answered")
        // Turn Off Tips is beneath the close button of the hint, not of the invitation.
        XCTAssertTrue(element(labeled: "Turn Off Tips", in: app).exists, "The tip has no Turn Off Tips")
    }

    /// No Thanks means no tips at all: the first painting says nothing about tapping.
    @MainActor
    func testNoThanksLeavesTheBenchQuiet() throws {
        let app = launchInvitation()
        let no = app.buttons["No Thanks"]
        XCTAssertTrue(no.waitForExistence(timeout: Self.invitationTimeout), "The invitation never came up")
        no.tap()
        XCTAssertTrue(app.staticTexts["Small Tips?"].waitForNonExistence(timeout: 10), "No Thanks left the invitation up")
        XCTAssertFalse(app.staticTexts["A Page Is Waiting"].exists, "No Thanks was followed by a tip")

        let card = app.buttons["The Great Wave"]
        XCTAssertTrue(card.waitForExistence(timeout: 30), "The gallery has no starter to open")
        card.tap()
        let badge = app.staticTexts.matching(NSPredicate(format: "label ENDSWITH 'percent painted'")).firstMatch
        XCTAssertTrue(badge.waitForExistence(timeout: 90), "The painting didn't open")
        // A tip would have come up within a few seconds of the painting appearing.
        sleep(8)
        attachScreenshot(of: app, named: "bench-after-no-thanks")
        XCTAssertFalse(app.staticTexts["Tap to Paint"].exists, "No Thanks was followed by a tip on the bench")
    }

    /// The note closed with a tap outside it counts as No Thanks: it does not come back.
    @MainActor
    func testClosingTheInvitationCountsAsNoThanks() throws {
        let app = launchInvitation()
        let title = app.staticTexts["Small Tips?"]
        XCTAssertTrue(title.waitForExistence(timeout: Self.invitationTimeout), "The invitation never came up")
        app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7)).tap()
        XCTAssertTrue(title.waitForNonExistence(timeout: 10), "Tapping outside didn't close the invitation")
        sleep(4)
        XCTAssertFalse(title.exists, "The closed invitation came back")
        XCTAssertFalse(app.staticTexts["A Page Is Waiting"].exists, "Closing the invitation was taken for Show Tips")
    }
}
