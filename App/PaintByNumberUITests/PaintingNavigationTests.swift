import UIKit
import XCTest

/// Gallery → painting → gallery. The painting is pushed with a zoom transition, whose
/// interactive dismissal (swipe down, pinch in) must not steal the canvas's own gestures.
final class PaintingNavigationTests: XCTestCase {
    @MainActor
    func testCanvasGesturesStayInPainting() throws {
        let app = openSeededPainting()
        let window = app.windows.firstMatch
        window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
            .press(forDuration: 0.1, thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8)))
        window.pinch(withScale: 0.4, velocity: -2)
        sleep(2)
        attachScreenshot(of: app, named: "painting-after-gestures")
        XCTAssertTrue(app.buttons["Close"].isHittable, "A canvas gesture dismissed the painting")
    }

    @MainActor
    func testCloseReturnsToGallery() throws {
        let app = openSeededPainting()
        app.buttons["Close"].tap()
        let returned = app.buttons["New Painting"].waitForExistence(timeout: 10)
        attachScreenshot(of: app, named: "after-close")
        XCTAssertTrue(returned, "Close didn't return to the gallery")
    }

    @MainActor
    func testEdgeSwipeReturnsToGallery() throws {
        let app = openSeededPainting()
        let window = app.windows.firstMatch
        window.coordinate(withNormalizedOffset: CGVector(dx: 0.005, dy: 0.5))
            .press(forDuration: 0.05, thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)))
        let returned = app.buttons["New Painting"].waitForExistence(timeout: 10)
        attachScreenshot(of: app, named: "after-edge-swipe")
        XCTAssertTrue(returned, "The edge swipe didn't return to the gallery")
    }

    /// The top bar's icon buttons act (Undo takes back painted areas).
    @MainActor
    func testUndoButtonActs() throws {
        let app = openSeededPainting()
        let badge = app.staticTexts.matching(NSPredicate(format: "label ENDSWITH 'percent painted'")).firstMatch
        let before = badge.label
        for _ in 0..<3 { app.buttons["Undo"].tap() }
        sleep(1)
        XCTAssertNotEqual(badge.label, before, "Undo didn't take anything back")
    }

    /// The Hint button flies the camera to an unpainted area.
    @MainActor
    func testHintButtonMovesTheCanvas() throws {
        let app = openSeededPainting()
        let before = app.screenshot()
        app.buttons["Hint"].tap()
        sleep(2)
        let after = app.screenshot()
        for (shot, name) in [(before, "before-hint"), (after, "after-hint")] {
            let attachment = XCTAttachment(screenshot: shot)
            attachment.name = name
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        XCTAssertNotEqual(canvasArea(of: before), canvasArea(of: after), "Hint didn't move the canvas")
    }

    /// Palette swatches select their color.
    @MainActor
    func testPaletteButtonSelects() throws {
        let app = openSeededPainting()
        let swatch = app.buttons["Color 14"]
        XCTAssertFalse(swatch.isSelected)
        swatch.tap()
        sleep(1)
        XCTAssertTrue(swatch.isSelected, "Tapping a swatch didn't select it")
    }

    /// The middle half of the screen, clear of the status bar and the chrome.
    private func canvasArea(of shot: XCUIScreenshot) -> Data? {
        guard let image = shot.image.cgImage else { return nil }
        let rect = CGRect(x: 0, y: image.height / 4, width: image.width, height: image.height / 2)
        return image.cropping(to: rect).flatMap { UIImage(cgImage: $0).pngData() }
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
