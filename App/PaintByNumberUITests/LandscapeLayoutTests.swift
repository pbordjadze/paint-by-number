import UIKit
import XCTest

/// iPad layouts in landscape (the CI screenshot pass is portrait only); each test attaches a
/// screenshot for review.
final class LandscapeLayoutTests: XCTestCase {
    /// The palette (along the trailing edge) shows every color without scrolling.
    @MainActor
    func testPaintingPaletteAlongTrailingEdge() throws {
        let app = try launchInLandscape("paint-progress")
        XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: 60))
        sleep(3)
        attachScreenshot(of: app, named: "landscape-paint-progress")
        let swatches = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Color '")).allElementsBoundByIndex
        XCTAssertFalse(swatches.isEmpty)
        let window = app.windows.firstMatch.frame
        for swatch in swatches {
            XCTAssertTrue(window.contains(swatch.frame), "\(swatch.label) is scrolled out of view")
        }
    }

    @MainActor
    func testCreatePreview() throws {
        let app = try launchInLandscape("create-preview")
        let start = app.buttons["Start Painting"]
        XCTAssertTrue(start.waitForExistence(timeout: 30))
        expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: start)
        waitForExpectations(timeout: 60)
        sleep(1)
        attachScreenshot(of: app, named: "landscape-create-preview")
    }

    @MainActor
    func testGallery() throws {
        let app = try launchInLandscape("gallery")
        let preparing = app.staticTexts["Preparing…"]
        XCTAssertTrue(app.buttons["New Painting"].waitForExistence(timeout: 30))
        let deadline = Date.now.addingTimeInterval(120)
        while preparing.exists && Date.now < deadline { sleep(1) }
        sleep(2)
        attachScreenshot(of: app, named: "landscape-gallery")
        XCTAssertFalse(preparing.exists, "Samples were still being prepared")
    }

    @MainActor
    private func launchInLandscape(_ scenario: String) throws -> XCUIApplication {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "iPad layouts")
        XCUIDevice.shared.orientation = .landscapeLeft
        addTeardownBlock { @MainActor in XCUIDevice.shared.orientation = .portrait }
        let app = XCUIApplication()
        app.launchArguments = ["-demo", scenario]
        app.launch()
        return app
    }

    @MainActor
    private func attachScreenshot(of app: XCUIApplication, named name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
