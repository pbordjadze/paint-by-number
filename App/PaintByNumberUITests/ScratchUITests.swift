import XCTest

/// From Scratch (SideStore and Debug builds, painting-company row 231): the New Painting
/// screen's button opens Refine on a blank page, with no Start From (nothing to generate), named
/// a drawing of today; Done goes back to the preview and Start Painting opens the painting.
final class ScratchUITests: XCTestCase {
    @MainActor
    func testFromScratchOpensRefineOnABlankPageAndPaints() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "create"]
        app.launch()
        let scratch = app.buttons["from-scratch"]
        XCTAssertTrue(scratch.waitForExistence(timeout: 20), "The New Painting screen has no From Scratch")
        // First use may explain limited library access.
        let ok = app.buttons["OK"]
        if ok.waitForExistence(timeout: 2) { ok.tap() }
        XCTAssertEqual(scratch.label, "From Scratch")
        XCTAssertTrue(waitUntil(timeout: 10) { scratch.isHittable }, "From Scratch isn't ready")
        scratch.tap()

        // Straight into Refine: no Refine tap, no sample picked.
        let canvas = app.descendants(matching: .any)["refine-canvas"]
        let opened = canvas.waitForExistence(timeout: 60)
        attachScreenshot(of: app, named: "scratch-refine")
        if !opened { attachTree(of: app, named: "scratch-refine-tree") }
        XCTAssertTrue(opened, "From Scratch didn't open Refine")
        XCTAssertEqual(canvas.value as? String, "No changes")
        XCTAssertFalse(app.descendants(matching: .any)["refine-start"].exists, "A blank page still offers Start From")

        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.4))
            .press(forDuration: 0.05, thenDragTo: canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.45)))
        XCTAssertTrue(
            waitFor(canvas, toMatch: NSPredicate(format: "value == %@", "1 change")), "The line didn't count: \(canvas.value ?? "")")
        attachScreenshot(of: app, named: "scratch-drawn")
        app.buttons["refine-done"].tap()

        // Its own name: a drawing of today, not a sample's title.
        let title = app.textFields["painting-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 20), "Done didn't go back to the preview")
        let name = title.placeholderValue ?? ""
        XCTAssertTrue(name.hasPrefix("Drawing, "), "The page is named \(name)")
        for setting in ["Colors", "Detail", "Smoothness", "Lines"] {
            XCTAssertFalse(app.sliders[setting].exists, "A blank page offers the \(setting) slider")
        }
        attachScreenshot(of: app, named: "scratch-preview")

        let start = app.buttons["Start Painting"]
        XCTAssertTrue(waitFor(start, toMatch: NSPredicate(format: "isEnabled == true"), timeout: 60), "Start Painting stays off")
        start.tap()
        let swatch = app.buttons["swatch-1"]
        let painting = swatch.waitForExistence(timeout: 60)
        attachScreenshot(of: app, named: "scratch-painting")
        XCTAssertTrue(painting, "Start Painting didn't open the drawing to paint")
    }

    /// Where Unlimited Paintings is sold and not bought, From Scratch offers it, worded for Refine,
    /// with the Tool Guide free to try; bought there, the blank page opens in Refine.
    @MainActor
    func testFromScratchWaitsForTheUnlockAndTheGuideIsFree() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "create", "-demoRefineLocked", "YES"]
        app.launch()
        let scratch = app.buttons["from-scratch"]
        XCTAssertTrue(scratch.waitForExistence(timeout: 20), "The New Painting screen has no From Scratch")
        let ok = app.buttons["OK"]
        if ok.waitForExistence(timeout: 2) { ok.tap() }
        XCTAssertTrue(waitUntil(timeout: 10) { scratch.isHittable }, "From Scratch isn't ready")
        scratch.tap()

        let buy = app.buttons["unlock-buy"]
        XCTAssertTrue(buy.waitForExistence(timeout: 10), "From Scratch didn't offer the unlock")
        let guide = app.buttons["unlock-try-guide"]
        XCTAssertTrue(guide.exists, "The sheet doesn't offer the Tool Guide")
        attachScreenshot(of: app, named: "scratch-unlock")
        guide.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["refine-guide-page"].waitForExistence(timeout: 30), "Try It didn't open the Tool Guide")
        app.buttons["refine-guide-done"].tap()

        XCTAssertTrue(waitUntil(timeout: 10) { scratch.isHittable }, "The guide didn't go back to the New Painting screen")
        scratch.tap()
        XCTAssertTrue(buy.waitForExistence(timeout: 10), "From Scratch didn't offer the unlock again")
        XCTAssertTrue(waitFor(buy, toMatch: NSPredicate(format: "label CONTAINS '4.99'")), "The buy button never showed the price")
        buy.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["refine-canvas"].waitForExistence(timeout: 60), "Buying didn't open the blank page in Refine")
    }
}
