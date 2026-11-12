import UIKit
import XCTest

#if UNRELEASED
/// Start from a Drawing's way in (SideStore and Debug builds, painting-company row 190): the
/// Paint page's A Drawing on Paper tile, in Your Own, presents the system picker for a drawing.
final class DrawingEntryUITests: XCTestCase {
    @MainActor
    func testADrawingOnPaperPresentsThePicker() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "create"]
        app.launch()
        let tile = app.buttons["choose-drawing"]
        XCTAssertTrue(tile.waitForExistence(timeout: 20), "Your Own has no A Drawing on Paper")
        // First use may explain limited library access.
        let ok = app.buttons["OK"]
        if ok.waitForExistence(timeout: 2) { ok.tap() }
        XCTAssertEqual(tile.label, "A Drawing on Paper")
        XCTAssertTrue(reveal(tile, in: app), "A Drawing on Paper isn't ready for a tap")

        // The tile presents the system picker: a new Cancel or Close comes up with its sheet
        // (the way CreateFlowTests tells a sheet). The out-of-process picker's cold start can
        // swallow a first tap, so one more tap is allowed.
        let dismissals = app.buttons.matching(NSPredicate(format: "label IN {'Cancel', 'Close'}"))
        let before = dismissals.count
        tile.tap()
        var presented = waitUntil(timeout: 15) { dismissals.count > before }
        if !presented {
            attachScreenshot(of: app, named: "drawing-entry-tap-missed")
            attachTree(of: app, named: "drawing-entry-tap-missed-tree")
            if tile.isHittable { tile.tap() }
            presented = waitUntil(timeout: 25) { dismissals.count > before }
        }
        attachScreenshot(of: app, named: "drawing-entry-picker")
        if !presented { attachTree(of: app, named: "drawing-entry-picker-tree") }
        XCTAssertTrue(presented, "A Drawing on Paper didn't present the system picker")
        XCTAssertFalse(app.buttons["Start Painting"].exists)
    }
}
#else
/// The release has no Start from a Drawing yet: its Paint page offers no A Drawing on Paper.
final class DrawingEntryUITests: XCTestCase {
    @MainActor
    func testTheReleaseOffersNoDrawingOnPaper() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "create"]
        app.launch()
        XCTAssertTrue(app.buttons["choose-photo"].waitForExistence(timeout: 20), "The Paint page didn't open")
        XCTAssertFalse(app.buttons["choose-drawing"].exists, "The release offers A Drawing on Paper")
    }
}
#endif
