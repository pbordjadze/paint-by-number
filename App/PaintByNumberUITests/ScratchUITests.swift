import XCTest
import UIKit

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

        // New Paint's picker on the first tap (QA, November 5: SwiftUI's ColorPicker there
        // presented nothing for a newcomer's first taps, and CI's first launch saw none in 40 s).
        let bucket = app.buttons["refine-tool-bucket"]
        if !bucket.exists { app.buttons["Paint"].firstMatch.tap() }
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
