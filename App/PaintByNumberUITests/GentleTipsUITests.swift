import XCTest

/// The gentle tips: on for everyone from the first launch, with no question asked, and off only by
/// Settings › Tips' switch. (`gallery-tip` is the first launch's gallery, the two starters unpainted;
/// `gallery-tips-off` is the same with the switch off and the desk not muted; `gallery-tip-gear` has
/// one finished painting. Every other launch hides tips.)
final class GentleTipsUITests: XCTestCase {
    /// How long the first launch's gallery takes to make its starters, and the first tip to come up
    /// beside them.
    private static let tipTimeout: TimeInterval = 150

    @MainActor
    private func launch(_ scenario: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", scenario]
        app.launch()
        return app
    }

    /// Opens The Great Wave from the shelf and waits for the painting screen.
    @MainActor
    private func openTheGreatWave(in app: XCUIApplication) {
        let card = app.buttons["The Great Wave"]
        XCTAssertTrue(card.waitForExistence(timeout: 30), "The gallery has no starter to open")
        card.tap()
        let badge = app.staticTexts.matching(NSPredicate(format: "label ENDSWITH 'percent painted'")).firstMatch
        XCTAssertTrue(badge.waitForExistence(timeout: 90), "The painting didn't open")
    }

    /// The first visit to the shelf, once the starters show: A Page Is Waiting, with nothing asked
    /// and no button but its close button.
    @MainActor
    func testAPageIsWaitingComesWithNoQuestion() throws {
        let app = launch("gallery-tip")
        let tip = app.staticTexts["A Page Is Waiting"]
        XCTAssertTrue(tip.waitForExistence(timeout: Self.tipTimeout), "The first tip never came up")
        attachScreenshot(of: app, named: "page-is-waiting")
        XCTAssertTrue(
            app.staticTexts["Tap a page in Ready to Paint to begin. Nothing needs setting up first."].exists,
            "The tip doesn't say what to do")
        XCTAssertFalse(app.staticTexts["Small Tips?"].exists, "The shelf asks whether to give tips")
        XCTAssertFalse(app.buttons["No Thanks"].exists, "The shelf has a No Thanks")
        XCTAssertFalse(app.buttons["Turn Off Tips"].exists, "The tip has a Turn Off Tips")
    }

    /// From the shelf into the first painting: opening the page ends the shelf's tip, and the bench
    /// says how to paint.
    @MainActor
    func testTheFirstTipsLeadIntoThePainting() throws {
        let app = launch("gallery-tip")
        XCTAssertTrue(app.staticTexts["A Page Is Waiting"].waitForExistence(timeout: Self.tipTimeout), "The first tip never came up")
        openTheGreatWave(in: app)
        let tapToPaint = app.staticTexts["Tap to Paint"]
        XCTAssertTrue(tapToPaint.waitForExistence(timeout: 60), "The first painting didn't say how to paint")
        attachScreenshot(of: app, named: "bench-after-the-shelf-tip")
        XCTAssertFalse(app.staticTexts["A Page Is Waiting"].exists, "The shelf's tip stayed over the painting")
        XCTAssertFalse(app.buttons["Turn Off Tips"].exists, "The tip has a Turn Off Tips")
    }

    /// With the Settings switch off no tip comes up: not on the shelf, not on the bench.
    @MainActor
    func testTipsSwitchedOffMeanNoTips() throws {
        let app = launch("gallery-tips-off")
        let card = app.buttons["The Great Wave"]
        XCTAssertTrue(card.waitForExistence(timeout: Self.tipTimeout), "The gallery has no starter to open")
        // The first tip would come up within a few seconds of the starters showing.
        sleep(10)
        attachScreenshot(of: app, named: "shelf-with-tips-off")
        XCTAssertFalse(app.staticTexts["A Page Is Waiting"].exists, "The shelf gave a tip with tips off")
        openTheGreatWave(in: app)
        sleep(8)
        attachScreenshot(of: app, named: "bench-with-tips-off")
        XCTAssertFalse(app.staticTexts["Tap to Paint"].exists, "The bench gave a tip with tips off")
    }

    /// A tip about a button in the navigation bar: Settings and Tips, a card under the bar that
    /// leaves the gear in sight.
    @MainActor
    func testSettingsAndTipsLiesUnderTheBar() throws {
        let app = launch("gallery-tip-gear")
        let tip = app.staticTexts["Settings and Tips"]
        XCTAssertTrue(tip.waitForExistence(timeout: Self.tipTimeout), "The tip about the gear never came up")
        attachScreenshot(of: app, named: "settings-and-tips")
        let gear = app.buttons["Settings"].firstMatch
        XCTAssertTrue(gear.exists, "The gear is gone")
        XCTAssertGreaterThanOrEqual(tip.frame.minY, gear.frame.maxY, "The tip covers the gear")
        XCTAssertTrue(
            app.staticTexts["The gear holds paper tone, sound and painting length. Tips can be turned off there."].exists,
            "The tip doesn't say where tips can be turned off")
    }
}
