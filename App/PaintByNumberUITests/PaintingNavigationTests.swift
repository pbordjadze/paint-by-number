import XCTest

/// Gallery → painting → gallery. The painting is pushed with a zoom transition, whose
/// interactive dismissal (swipe down, pinch in) must not steal the canvas's own gestures.
final class PaintingNavigationTests: XCTestCase {
    @MainActor
    func testCanvasGesturesStayInPaintingAndCloseReturnsToGallery() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "gallery-open"]
        app.launch()

        // The demo seeds a painting in the background and opens it once it is ready.
        let close = app.buttons["Close"]
        XCTAssertTrue(close.waitForExistence(timeout: 90))
        sleep(2)

        let window = app.windows.firstMatch
        window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
            .press(forDuration: 0.1, thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8)))
        window.pinch(withScale: 0.4, velocity: -2)
        sleep(2)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "painting-after-gestures"
        shot.lifetime = .keepAlways
        add(shot)
        XCTAssertTrue(close.isHittable, "A canvas gesture dismissed the painting")

        close.tap()
        XCTAssertTrue(close.waitForNonExistence(timeout: 10))
        XCTAssertTrue(app.buttons["New Painting"].waitForExistence(timeout: 10))
    }
}
