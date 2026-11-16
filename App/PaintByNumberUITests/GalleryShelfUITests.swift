import XCTest

/// Tonight's Picture on the gallery (`GalleryShelf`, painting-company row 317): under a newcomer's
/// two paintings, tonight's library picture with the nights after it, and a tap paints it.
final class GalleryShelfUITests: XCTestCase {
    @MainActor
    func testTonightsPictureOnTheGalleryPaints() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "gallery-first-run"]
        app.launch()

        let tonight = app.buttons["gallery-tonight"]
        XCTAssertTrue(tonight.waitForExistence(timeout: 60), "The gallery has no Tonight's Picture")
        for _ in 0..<6 where !tonight.isHittable { app.swipeUp() }
        XCTAssertTrue(tonight.isHittable, "Tonight's Picture can't be reached")
        XCTAssertEqual(tonight.value as? String, "Tonight’s Picture", "Tonight's tile doesn't say it is tonight's")
        XCTAssertTrue(app.buttons["gallery-night"].exists, "A gallery of two paintings shows no nights after tonight")
        XCTAssertTrue(app.buttons["gallery-more-to-paint"].exists, "No More to Paint under the nights")
        attachScreenshot(of: app, named: "gallery-tonight")

        tonight.tap()
        XCTAssertTrue(waitForPaintingWithoutStart(in: app), "Tonight's Picture didn't open as a painting")
    }
}
