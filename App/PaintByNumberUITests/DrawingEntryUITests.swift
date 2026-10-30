import UIKit
import XCTest

/// Start from a Drawing's way in (SideStore and Debug builds, painting-company row 190): a long
/// press of the photo step's photo button (Browse All… on iPad, Choose Photo on iPhone) offers
/// Choose Photo of a Drawing…, and the toolbar itself offers nothing of it.
final class DrawingEntryUITests: XCTestCase {
    @MainActor
    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    @MainActor
    func testLongPressOfThePhotoButtonOffersADrawing() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "create"]
        app.launch()
        // iPhone's Photos pane is the Choose Photo button (`PhotoSourceView.embedsPicker`).
        let button = isPad ? app.buttons["Browse All…"] : app.buttons["choose-photo"]
        XCTAssertTrue(button.waitForExistence(timeout: 20), "No photo button on the photo step")
        // First use may explain limited library access.
        let ok = app.buttons["OK"]
        if ok.waitForExistence(timeout: 2) { ok.tap() }
        XCTAssertTrue(waitUntil(timeout: 10) { button.isHittable }, "The photo button isn't ready")

        // Off the toolbar on purpose: nothing names the drawing before the long press.
        let item = element(labeled: "Choose Photo of a Drawing…", in: app)
        XCTAssertFalse(element(labeled: "From a Drawing", in: app).exists, "The toolbar still offers From a Drawing")
        XCTAssertFalse(item.exists, "The drawing's item shows before any long press")

        button.press(forDuration: 1.2)
        let offered = item.waitForExistence(timeout: 5)
        attachScreenshot(of: app, named: "drawing-entry-menu")
        if !offered { attachTree(of: app, named: "drawing-entry-menu-tree") }
        XCTAssertTrue(offered, "A long press of the photo button doesn't offer Choose Photo of a Drawing…")

        // A tap away from the menu closes it, and nothing was presented.
        app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08)).tap()
        XCTAssertTrue(waitUntil(timeout: 5) { !item.exists }, "The menu stayed up after a tap away")
        XCTAssertFalse(app.buttons["Start Painting"].exists)
    }
}
