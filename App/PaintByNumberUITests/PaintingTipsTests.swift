import XCTest

/// First-run tips: the first painting explains tapping, and the tip goes away for good once
/// dismissed. (`paint-tip` is the only launch that shows tips; it starts from an empty
/// TipKit datastore.)
final class PaintingTipsTests: XCTestCase {
    @MainActor
    func testFirstTipAppearsAndDismisses() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "paint-tip"]
        app.launch()

        let tip = app.staticTexts["Tap to Paint"]
        XCTAssertTrue(tip.waitForExistence(timeout: 90), "The first tip didn't appear")
        attachScreenshot(of: app, named: "first-tip")

        // Outside the popover, which sits over the palette at the bottom.
        app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)).tap()
        XCTAssertTrue(tip.waitForNonExistence(timeout: 10), "Tapping outside didn't dismiss the tip")
        sleep(2)
        XCTAssertFalse(tip.exists, "The dismissed tip came back")
    }
}
