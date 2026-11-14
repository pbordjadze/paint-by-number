import XCTest
import UIKit

/// Blank Page (SideStore and Debug builds, painting-company rows 231 and 239): the Paint page's
/// tile opens Refine on a blank page, with no Start From (nothing to generate), named a drawing
/// of today; Done goes straight into the painting, with no preview between.
final class ScratchUITests: XCTestCase {
    @MainActor
    func testBlankPageOpensRefineAndPaints() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "create"]
        app.launch()
        let scratch = app.buttons["from-scratch"]
        XCTAssertTrue(scratch.waitForExistence(timeout: 20), "The Paint page has no Blank Page")
        // First use may explain limited library access.
        let ok = app.buttons["OK"]
        if ok.waitForExistence(timeout: 2) { ok.tap() }
        XCTAssertEqual(scratch.label, "Blank Page")
        XCTAssertTrue(reveal(scratch, in: app), "Blank Page isn't ready")
        scratch.tap()

        // Straight into Refine: no Refine tap, no picture picked.
        let canvas = app.descendants(matching: .any)["refine-canvas"]
        let opened = canvas.waitForExistence(timeout: 60)
        attachScreenshot(of: app, named: "scratch-refine")
        if !opened { attachTree(of: app, named: "scratch-refine-tree") }
        XCTAssertTrue(opened, "Blank Page didn't open Refine")
        XCTAssertEqual(canvas.value as? String, "No changes")
        XCTAssertFalse(app.descendants(matching: .any)["refine-start"].exists, "A blank page still offers Start From")

        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.4))
            .press(forDuration: 0.05, thenDragTo: canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.45)))
        XCTAssertTrue(
            waitFor(canvas, toMatch: NSPredicate(format: "value == %@", "1 change")), "The line didn't count: \(canvas.value ?? "")")
        attachScreenshot(of: app, named: "scratch-drawn")

        // New Paint's picker on the first tap (QA, November 5: SwiftUI's ColorPicker there
        // presented nothing for a newcomer's first taps, and CI's first launch saw none in 40 s).
        let bucket = app.buttons["refine-tool-bucket"]
        // The Colors group's tab (Paint in the release), in Refine's chooser: the gallery's Paint (+) lies beneath.
        if !bucket.exists { app.descendants(matching: .any)["refine-groups"].firstMatch.buttons["Colors"].tap() }
        XCTAssertTrue(bucket.waitForExistence(timeout: 5), "Refine has no Bucket")
        bucket.tap()
        let wheel = app.buttons["refine-palette-new"]
        XCTAssertTrue(wheel.waitForExistence(timeout: 5), "The palette has no New Paint")
        wheel.tap()
        let picker = app.descendants(matching: .any).matching(NSPredicate(format: "label IN %@", ["Grid", "Spectrum", "Sliders"])).firstMatch
        let picks = picker.waitForExistence(timeout: 10)
        attachScreenshot(of: app, named: "scratch-new-paint")
        XCTAssertTrue(picks, "New Paint opened no color picker on its first tap")
        let close = app.buttons.matching(NSPredicate(format: "label ==[c] %@", "Close")).firstMatch
        if close.exists {
            close.tap()
        } else if UIDevice.current.userInterfaceIdiom == .phone {
            // A sheet there, with no close button: a tap above it, at the status bar, closed nothing,
            // and Done's tap after it only closed the sheet (main's iPhone job, November 6). It goes
            // as a painter sends it, dragged down by its header.
            // Read once the sheet has stopped rising.
            var frame = CGRect.null
            _ = waitUntil(timeout: 5) {
                let now = picker.frame
                defer { frame = now }
                return now == frame && picker.isHittable
            }
            let header = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: frame.midX, dy: frame.minY - 40))
            header.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.99)))
        } else {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.03)).tap()
        }
        XCTAssertTrue(waitUntil(timeout: 10) { !picker.exists }, "New Paint's picker didn't close")

        app.buttons["refine-done"].tap()

        // Straight into the painting: no preview, no Start Painting, and its own name: a drawing
        // of today, not a sample's title.
        let swatch = app.buttons["swatch-1"]
        let painting = swatch.waitForExistence(timeout: 90)
        attachScreenshot(of: app, named: "scratch-painting")
        if !painting { attachTree(of: app, named: "scratch-painting-tree") }
        XCTAssertTrue(painting, "Done didn't open the drawing to paint")
        XCTAssertFalse(app.buttons["Start Painting"].exists, "A blank page still shows the preview's Start Painting")
        XCTAssertFalse(app.textFields["painting-title"].exists, "A blank page still shows the preview")
        let badge = app.staticTexts.matching(NSPredicate(format: "label ENDSWITH 'percent painted'")).firstMatch
        XCTAssertTrue(badge.waitForExistence(timeout: 10), "The painting has no progress badge")
        XCTAssertTrue(badge.label.hasPrefix("Drawing, "), "The page is named \(badge.label)")
    }

    /// Done with nothing drawn goes back to the Paint page: no preview, no painting.
    @MainActor
    func testBlankPageDoneWithNothingDrawnGoesBack() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "create"]
        app.launch()
        let scratch = app.buttons["from-scratch"]
        XCTAssertTrue(scratch.waitForExistence(timeout: 20), "The Paint page has no Blank Page")
        let ok = app.buttons["OK"]
        if ok.waitForExistence(timeout: 2) { ok.tap() }
        XCTAssertTrue(reveal(scratch, in: app), "Blank Page isn't ready")
        scratch.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["refine-canvas"].waitForExistence(timeout: 60), "Blank Page didn't open Refine")

        let done = app.buttons["refine-done"]
        XCTAssertTrue(done.waitForExistence(timeout: 10), "Refine has no Done")
        done.tap()
        // Nothing drawn: back on the Paint page, whose own tiles are there again.
        XCTAssertTrue(
            app.descendants(matching: .any)["refine-canvas"].waitForNonExistence(timeout: 30), "Done on a blank page left Refine open")
        XCTAssertTrue(app.buttons["choose-photo"].waitForExistence(timeout: 30), "Done on a blank page didn't go back to the Paint page")
        XCTAssertFalse(app.buttons["Start Painting"].exists)
        XCTAssertFalse(app.buttons["swatch-1"].exists, "Done on a blank page opened a painting")
    }

    /// Where Unlimited Paintings is sold and not bought, Blank Page offers it, worded for Refine,
    /// with the Tool Guide free to try; bought there, the blank page opens in Refine.
    @MainActor
    func testBlankPageWaitsForTheUnlockAndTheGuideIsFree() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "create", "-demoRefineLocked", "YES"]
        app.launch()
        let scratch = app.buttons["from-scratch"]
        XCTAssertTrue(scratch.waitForExistence(timeout: 20), "The Paint page has no Blank Page")
        let ok = app.buttons["OK"]
        if ok.waitForExistence(timeout: 2) { ok.tap() }
        XCTAssertTrue(reveal(scratch, in: app), "Blank Page isn't ready")
        XCTAssertEqual(scratch.value as? String, "Comes with Unlimited Paintings", "Blank Page doesn't say it waits for the purchase")
        scratch.tap()

        let buy = app.buttons["unlock-buy"]
        XCTAssertTrue(buy.waitForExistence(timeout: 10), "Blank Page didn't offer the unlock")
        let guide = app.buttons["unlock-try-guide"]
        XCTAssertTrue(guide.exists, "The sheet doesn't offer the Tool Guide")
        attachScreenshot(of: app, named: "scratch-unlock")
        guide.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["refine-guide-page"].waitForExistence(timeout: 30), "Try It didn't open the Tool Guide")
        XCTAssertTrue(
            app.navigationBars["Bend Line"].exists, "Try It didn't open the guide on Bend Line")
        app.buttons["refine-guide-done"].tap()

        XCTAssertTrue(reveal(scratch, in: app), "The guide didn't go back to the Paint page")
        scratch.tap()
        XCTAssertTrue(buy.waitForExistence(timeout: 10), "Blank Page didn't offer the unlock again")
        XCTAssertTrue(waitFor(buy, toMatch: NSPredicate(format: "label CONTAINS '4.99'")), "The buy button never showed the price")
        buy.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["refine-canvas"].waitForExistence(timeout: 60), "Buying didn't open the blank page in Refine")
    }
}
