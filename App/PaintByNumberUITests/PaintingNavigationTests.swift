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
        // A painting opens with a color selected: take one that isn't.
        let unselected = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'swatch-' AND selected == false"))
        // On a phone the palette scrolls: take one that is on screen.
        let identifier = try XCTUnwrap(
            unselected.allElementsBoundByIndex.first(where: \.isHittable)?.identifier, "No unselected swatch on screen")
        let swatch = app.buttons[identifier]
        XCTAssertFalse(swatch.isSelected)
        swatch.tap()
        let selected = wait(for: swatch, toMatch: NSPredicate(format: "selected == true"))
        XCTAssertTrue(selected, "Tapping a swatch didn't select it")
    }

    /// Hardware keyboard: `]` selects the next color; a fill is undone with ⌘Z and redone
    /// with ⇧⌘Z (window undo manager).
    @MainActor
    func testKeyboardColorsUndoAndRedo() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "Menu bar commands are an iPad feature")
        let app = openSeededPainting()
        let swatches = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'swatch-'"))
        func selected() -> Set<String> {
            Set(swatches.matching(NSPredicate(format: "selected == true")).allElementsBoundByIndex.map(\.identifier))
        }

        let before = selected()
        app.typeKey("]", modifierFlags: [])
        sleep(1)
        let newlySelected = try XCTUnwrap(selected().subtracting(before).first, "] didn't select another color")
        let swatch = swatches[newlySelected]

        // The hint centres a region of the selected color in the canvas area: tap it, or (when
        // the camera couldn't centre it) drag-paint across the middle.
        app.buttons["Hint"].tap()
        sleep(2)
        let top = app.buttons["Close"].frame.maxY + 6
        let bottom = swatches.allElementsBoundByIndex.map(\.frame.minY).min().map { $0 - 20 } ?? app.frame.maxY
        let origin = app.coordinate(withNormalizedOffset: .zero)
        func point(_ x: CGFloat, _ y: CGFloat) -> XCUICoordinate {
            origin.withOffset(CGVector(dx: app.frame.minX + x * app.frame.width, dy: top + y * (bottom - top)))
        }
        // A color whose last area gets painted is finished, and its swatch leaves the palette.
        func state() -> String? { swatch.exists ? swatch.value as? String : "finished" }
        let unpainted = state()
        point(0.5, 0.5).tap()
        sleep(1)
        if state() == unpainted {
            point(0.1, 0.5).press(forDuration: 0.5, thenDragTo: point(0.9, 0.5))
            point(0.5, 0.1).press(forDuration: 0.5, thenDragTo: point(0.5, 0.9))
            sleep(1)
        }
        let painted = state()
        attachScreenshot(of: app, named: "keyboard-painted")
        XCTAssertNotEqual(painted, unpainted, "Couldn't paint the hinted color")

        app.typeKey("z", modifierFlags: .command)
        sleep(1)
        XCTAssertNotEqual(state(), painted, "⌘Z didn't undo")
        app.typeKey("z", modifierFlags: [.command, .shift])
        sleep(1)
        XCTAssertEqual(state(), painted, "⇧⌘Z didn't redo")
    }

    /// The Photo control: a tap keeps the photo shown until the next tap; a hold only peeks.
    @MainActor
    func testPhotoControlPeeksAndLatches() throws {
        let app = openSeededPainting()
        let photo = app.buttons["Photo"]
        XCTAssertTrue(photo.exists, "The painting has no Photo control")
        XCTAssertEqual(photo.value as? String, "Hidden")
        photo.tap()
        XCTAssertTrue(wait(for: photo, value: "Showing"), "A tap didn't keep the photo shown")
        attachScreenshot(of: app, named: "photo-shown")
        photo.tap()
        XCTAssertTrue(wait(for: photo, value: "Hidden"), "A second tap didn't hide the photo")
        photo.press(forDuration: 1.2)
        XCTAssertTrue(wait(for: photo, value: "Hidden"), "A hold kept the photo shown")
    }

    /// Holding the Photo control shows the photo while held and hides it on release.
    /// `press(forDuration:)` blocks until the release, so the app traces the control's values
    /// in its accessibility identifier (`-tracePhotoPeek`).
    @MainActor
    func testHoldingPhotoPeeks() throws {
        let app = openSeededPainting(tracingPhotoPeek: true)
        let photo = app.buttons.matching(NSPredicate(format: "label == 'Photo'")).firstMatch
        XCTAssertTrue(photo.exists, "The painting has no Photo control")
        XCTAssertEqual(photo.identifier, "Hidden")
        photo.press(forDuration: 1.2)
        let traced = wait(for: photo, toMatch: NSPredicate(format: "identifier == 'Hidden,Showing,Hidden'"))
        XCTAssertTrue(traced, "Holding didn't show the photo only while held: \(photo.identifier)")
        XCTAssertEqual(photo.value as? String, "Hidden")
    }

    /// A tap on the canvas while the photo shows hides it instead of painting blind.
    @MainActor
    func testCanvasTapHidesThePhoto() throws {
        let app = openSeededPainting()
        // An unpainted area of the selected color, centred on its number: a tap there paints
        // it, so the area's element would go away.
        let area = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'canvas-area-'")).firstMatch
        XCTAssertTrue(area.waitForExistence(timeout: 10), "The canvas offers no unpainted area")
        let identifier = area.identifier, frame = area.frame
        let photo = app.buttons["Photo"]
        photo.tap()
        XCTAssertTrue(wait(for: photo, value: "Showing"), "A tap didn't keep the photo shown")
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: frame.midX, dy: frame.midY)).tap()
        XCTAssertTrue(wait(for: photo, value: "Hidden"), "A canvas tap didn't hide the photo")
        sleep(1)
        XCTAssertTrue(app.buttons[identifier].exists, "The tap that hid the photo also painted")
    }

    /// Hardware keyboard: `p` toggles the photo (Paint ▸ Show Photo).
    @MainActor
    func testPhotoKey() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "Menu bar commands are an iPad feature")
        let app = openSeededPainting()
        let photo = app.buttons["Photo"]
        app.typeKey("p", modifierFlags: [])
        XCTAssertTrue(wait(for: photo, value: "Showing"), "p didn't show the photo")
        app.typeKey("p", modifierFlags: [])
        XCTAssertTrue(wait(for: photo, value: "Hidden"), "p didn't hide the photo")
    }

    /// How long a check waits for the state an action leads to. The CI's iPad simulator can
    /// stall for seconds: a photo shown by a tap once took 5 s to appear (a 560 px image) and
    /// the control didn't read "Showing" within a 3 s wait; a tapped swatch once wasn't
    /// selected a second later, the screen unchanged to the end of the test. Every state waited
    /// for here persists once reached, so a long wait only absorbs such stalls: a wrong state
    /// still fails.
    private static let stateTimeout: TimeInterval = 15

    @MainActor
    private func wait(for element: XCUIElement, value: String) -> Bool {
        wait(for: element, toMatch: NSPredicate(format: "value == %@", value))
    }

    @MainActor
    private func wait(for element: XCUIElement, toMatch predicate: NSPredicate) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter.wait(for: [expectation], timeout: Self.stateTimeout) == .completed
    }

    /// The middle half of the screen, clear of the status bar and the chrome.
    @MainActor
    private func canvasArea(of shot: XCUIScreenshot) -> Data? {
        guard let image = shot.image.cgImage else { return nil }
        let rect = CGRect(x: 0, y: image.height / 4, width: image.width, height: image.height / 2)
        return image.cropping(to: rect).flatMap { UIImage(cgImage: $0).pngData() }
    }

    /// Launches the demo that seeds a painting in the background and opens it once it is ready.
    @MainActor
    private func openSeededPainting(tracingPhotoPeek: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "gallery-open"] + (tracingPhotoPeek ? ["-tracePhotoPeek", "YES"] : [])
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
