import XCTest

/// Gallery → painting → gallery. The painting is pushed with a zoom transition, whose
/// interactive dismissal (swipe down, pinch in) must not steal the canvas's own gestures.
final class PaintingNavigationTests: XCTestCase {
    @MainActor
    func testCanvasGesturesStayInPainting() throws {
        let app = openSeededPainting()
        let close = app.buttons["Close"]
        let window = app.windows.firstMatch
        window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
            .press(forDuration: 0.1, thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8)))
        window.pinch(withScale: 0.4, velocity: -2)
        sleep(2)
        attachScreenshot(of: app, named: "painting-after-gestures")
        XCTAssertTrue(close.isHittable, "A canvas gesture dismissed the painting")
    }

    @MainActor
    func testTopBarWorksAndCloseReturnsToGallery() throws {
        let app = openSeededPainting()
        app.buttons["More"].tap()
        let fit = app.buttons["Fit to Screen"]
        XCTAssertTrue(fit.waitForExistence(timeout: 5), "The More menu didn't open")
        if fit.exists { fit.tap() }
        sleep(1)

        app.buttons["Close"].tap()
        let gallery = app.buttons["New Painting"]
        let returned = gallery.waitForExistence(timeout: 10)
        attachScreenshot(of: app, named: "after-close")
        XCTAssertTrue(returned, "Close didn't return to the gallery")
    }

    /// Launches the demo that seeds a painting in the background and opens it once it is ready.
    @MainActor
    private func openSeededPainting() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "gallery-open"]
        app.launch()
        XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: 90), "The painting didn't open")
        sleep(2)
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
