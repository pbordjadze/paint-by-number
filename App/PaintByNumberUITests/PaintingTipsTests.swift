import XCTest

/// The bench's first tip: the first painting says how to paint, and the tip goes away for good once
/// dismissed or once an area is filled. (`paint-tip` and `paint-tip-fill` are among the few launches
/// that show tips; each starts from an empty TipKit datastore and tips turned on.)
final class PaintingTipsTests: XCTestCase {
    @MainActor
    func testFirstTipAppearsAndDismisses() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "paint-tip"]
        app.launch()

        let tip = app.staticTexts["Tap to Paint"]
        XCTAssertTrue(tip.waitForExistence(timeout: 90), "The first tip didn't appear")
        XCTAssertTrue(
            app.staticTexts["Pick a color, then tap an area marked with its number to fill it."].exists,
            "The first tip doesn't say what to do")
        attachScreenshot(of: app, named: "first-tip")
        // It asks for a color: it covers none (QA, November 7: on iPad it hid a line of swatches).
        let message = app.staticTexts["Pick a color, then tap an area marked with its number to fill it."]
        XCTAssertTrue(waitUntil(timeout: 5) { tip.isHittable }, "The tip isn't settled on screen")
        let words = tip.frame.union(message.frame)
        let swatches = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'swatch-'")).allElementsBoundByIndex
        let covered = swatches.filter { $0.isHittable || $0.frame.intersects(words) }.filter { $0.frame.intersects(words) }
        XCTAssertTrue(covered.isEmpty, "The tip covers \(covered.map(\.identifier))")

        // Outside the popover, which sits over the canvas above the palette at the bottom.
        app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)).tap()
        XCTAssertTrue(tip.waitForNonExistence(timeout: 10), "Tapping outside didn't dismiss the tip")
        sleep(2)
        XCTAssertFalse(tip.exists, "The dismissed tip came back")
    }

    /// Filling an area is using what the tip is about: the tip closes by itself and stays closed.
    @MainActor
    func testFirstTipClosesAfterAFill() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "paint-tip-fill"]
        app.launch()

        let tip = app.staticTexts["Tap to Paint"]
        XCTAssertTrue(tip.waitForExistence(timeout: 90), "The first tip didn't appear")
        attachScreenshot(of: app, named: "first-tip-before-fill")
        // The scenario fills an area once the tip is up.
        XCTAssertTrue(tip.waitForNonExistence(timeout: 30), "A fill didn't close the tip")
        attachScreenshot(of: app, named: "first-tip-after-fill")
        sleep(2)
        XCTAssertFalse(tip.exists, "The tip came back after the fill")
    }
}
