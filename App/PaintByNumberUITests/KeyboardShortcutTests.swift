import UIKit
import XCTest

/// A hardware keyboard's shortcuts that no other test presses: the Paint menu's single keys (`[`,
/// H, N, Z, R) and its zooms (⌘+, ⌘-, ⌘0), the gallery's ⌘N and ⌘F, and the cancel key on Settings
/// and on the Paint page. (`]`, P, ⌘[, ⌘Z and ⇧⌘Z are `PaintingNavigationTests`'.) Menu bar commands
/// are an iPad feature.
///
/// The cancel key is pressed as ⌘. here: it is Esc's twin (one `.cancelAction` answers both), and an
/// Esc that XCUITest types never reaches the app in a simulator.
final class KeyboardShortcutTests: XCTestCase {
    // MARK: The Paint menu

    /// `[` selects the previous color, as `]` the next: one after the other comes back to the
    /// color the painting opened on.
    @MainActor
    func testBracketKeysStepThroughTheColors() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "Menu bar commands are an iPad feature")
        let app = openSeededPainting()
        let swatches = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'swatch-'"))
        func selected() -> String? {
            swatches.matching(NSPredicate(format: "selected == true")).allElementsBoundByIndex.first?.identifier
        }
        let first = try XCTUnwrap(selected(), "No color is selected")
        app.typeKey("[", modifierFlags: [])
        XCTAssertTrue(waitUntil(timeout: Self.stateTimeout) { selected().map { $0 != first } ?? false }, "[ didn't select another color")
        let previous = try XCTUnwrap(selected())
        app.typeKey("]", modifierFlags: [])
        XCTAssertTrue(waitUntil(timeout: Self.stateTimeout) { selected() == first }, "] didn't come back from \(previous) to \(first)")
        // And round the other way: ] then [.
        app.typeKey("]", modifierFlags: [])
        XCTAssertTrue(waitUntil(timeout: Self.stateTimeout) { selected().map { $0 != first && $0 != previous } ?? false },
                      "] didn't select the color after \(first)")
        app.typeKey("[", modifierFlags: [])
        XCTAssertTrue(waitUntil(timeout: Self.stateTimeout) { selected() == first }, "[ didn't come back to \(first)")
    }

    /// H flies the camera to an unpainted area, as the Hint button does.
    @MainActor
    func testHintKeyMovesTheCanvas() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "Menu bar commands are an iPad feature")
        let app = openSeededPainting()
        let before = try stillCanvas(of: app)
        app.typeKey("h", modifierFlags: [])
        XCTAssertTrue(waitUntil(timeout: Self.stateTimeout) { self.canvasArea(of: app.screenshot()) != before }, "H didn't move the canvas")
        attachScreenshot(of: app, named: "after-hint-key")
    }

    /// N hides the numbers and N again shows them: the page is back as it was.
    @MainActor
    func testNumbersKeyHidesAndShowsTheNumbers() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "Menu bar commands are an iPad feature")
        let app = openSeededPainting()
        let before = try stillCanvas(of: app)
        app.typeKey("n", modifierFlags: [])
        XCTAssertTrue(waitUntil(timeout: Self.stateTimeout) { self.canvasArea(of: app.screenshot()) != before }, "N changed nothing on the page")
        // The numbers fade for a quarter of a second.
        sleep(1)
        attachScreenshot(of: app, named: "numbers-hidden")
        app.typeKey("n", modifierFlags: [])
        let back = waitUntil(timeout: Self.stateTimeout) { self.canvasArea(of: app.screenshot()) == before }
        if !back { attachScreenshot(of: app, named: "numbers-not-back") }
        XCTAssertTrue(back, "N again didn't bring the numbers back")
    }

    /// Z turns Zen Mode on, which says what it does, and Z again turns it off, which says nothing.
    @MainActor
    func testZenKeyTurnsZenModeOnAndOff() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "Menu bar commands are an iPad feature")
        let app = openSeededPainting()
        let note = app.descendants(matching: .any)["zen-note"]
        app.typeKey("z", modifierFlags: [])
        if !note.waitForExistence(timeout: 4) {
            // Zen Mode was on already (a test before this one left it so): that Z turned it off.
            app.typeKey("z", modifierFlags: [])
            XCTAssertTrue(note.waitForExistence(timeout: Self.stateTimeout), "Z didn't turn Zen Mode on")
        }
        XCTAssertTrue(note.label.contains("next area"), "The note doesn't say what Zen does: \(note.label)")
        XCTAssertTrue(note.waitForNonExistence(timeout: 10), "The note stayed")
        // Off again, for the tests after this one.
        app.typeKey("z", modifierFlags: [])
        XCTAssertFalse(note.waitForExistence(timeout: 3), "Z turning Zen Mode off said something")
    }

    /// ⌘+ zooms in, ⌘- back out to the whole painting, and ⌘0 fits it from any zoom. (+ is typed
    /// with Shift, as on the keyboards that have it over =.)
    @MainActor
    func testZoomKeys() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "Menu bar commands are an iPad feature")
        let app = openSeededPainting()
        let fitted = try stillCanvas(of: app)
        func canvas() -> Data? { canvasArea(of: app.screenshot()) }

        XCTAssertTrue(press("+", [.command, .shift], in: app) { canvas() != fitted }, "⌘+ didn't zoom in")
        sleep(1)
        let zoomed = canvas()
        attachScreenshot(of: app, named: "zoomed-in")
        app.typeKey("-", modifierFlags: .command)
        XCTAssertTrue(waitUntil(timeout: Self.stateTimeout) { canvas() == fitted }, "⌘- didn't zoom back out to the whole painting")

        app.typeKey("+", modifierFlags: [.command, .shift])
        XCTAssertTrue(waitUntil(timeout: Self.stateTimeout) { canvas() == zoomed }, "⌘+ didn't zoom in as far again")
        app.typeKey("+", modifierFlags: [.command, .shift])
        XCTAssertTrue(waitUntil(timeout: Self.stateTimeout) { canvas() != zoomed && canvas() != fitted }, "A second ⌘+ didn't zoom further")
        sleep(1)
        app.typeKey("0", modifierFlags: .command)
        let fit = waitUntil(timeout: Self.stateTimeout) { canvas() == fitted }
        if !fit { attachScreenshot(of: app, named: "not-fitted") }
        XCTAssertTrue(fit, "⌘0 didn't fit the whole painting")
    }

    /// On a finished painting R stops the replay that is playing and R again plays it.
    @MainActor
    func testReplayKeyStopsAndPlays() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "Menu bar commands are an iPad feature")
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "paint-replay"]
        app.launch()
        let stop = app.buttons["Stop"], replay = app.buttons["Replay"]
        XCTAssertTrue(stop.waitForExistence(timeout: 60), "The replay's bar has no Stop")
        app.typeKey("r", modifierFlags: [])
        XCTAssertTrue(replay.waitForExistence(timeout: Self.stateTimeout), "R didn't stop the replay")
        XCTAssertTrue(app.buttons["Undo"].isEnabled, "Undo stayed off after the replay")
        app.typeKey("r", modifierFlags: [])
        XCTAssertTrue(stop.waitForExistence(timeout: Self.stateTimeout), "R didn't play the painting again")
        attachScreenshot(of: app, named: "replay-key")
    }

    // MARK: The gallery

    /// ⌘N opens the Paint page, as the gallery's Paint button does, and the cancel key closes it.
    @MainActor
    func testNewPaintingKeyAndCancelKey() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "Menu bar commands are an iPad feature")
        let app = launchGallery()
        let photo = app.buttons["choose-photo"]
        XCTAssertFalse(photo.exists)
        app.typeKey("n", modifierFlags: .command)
        XCTAssertTrue(photo.waitForExistence(timeout: Self.stateTimeout), "⌘N didn't open the Paint page")
        attachScreenshot(of: app, named: "new-painting-key")
        sleep(2)
        app.typeKey(".", modifierFlags: .command)
        XCTAssertTrue(photo.waitForNonExistence(timeout: Self.stateTimeout), "The cancel key didn't close the Paint page")
        XCTAssertTrue(app.buttons["Paint"].waitForExistence(timeout: Self.stateTimeout), "The gallery didn't come back")
    }

    /// ⌘F puts the keyboard in the gallery's search field: what is typed next narrows the shelf.
    /// (What a painter with a keyboard gets; iPadOS's own Find may be what answers, so this is not
    /// proof of the app's own binding.)
    @MainActor
    func testSearchKey() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "Menu bar commands are an iPad feature")
        let app = launchGallery()
        let wave = app.buttons["The Great Wave"].firstMatch
        XCTAssertTrue(wave.waitForExistence(timeout: 60), "The gallery has no Great Wave")
        sleep(2)
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: Self.stateTimeout), "The gallery has no search field")
        XCTAssertTrue(press("f", .command, in: app) { (field.value(forKey: "hasKeyboardFocus") as? Bool) == true },
                      "⌘F didn't put the keyboard in the search field")
        app.typeText("re")
        XCTAssertTrue(app.buttons["Red Fox in Snow"].firstMatch.waitForExistence(timeout: Self.stateTimeout), "“re” didn't find Red Fox in Snow")
        XCTAssertTrue(wave.waitForNonExistence(timeout: Self.stateTimeout), "The Great Wave matches “re”")
        attachScreenshot(of: app, named: "search-key")
    }

    /// The cancel key closes Settings, as Done does.
    @MainActor
    func testCancelKeyClosesSettings() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "Menu bar commands are an iPad feature")
        let app = openSettings()
        let sheet = app.navigationBars["Settings"]
        sleep(2)
        app.typeKey(".", modifierFlags: .command)
        XCTAssertTrue(sheet.waitForNonExistence(timeout: Self.stateTimeout), "The cancel key didn't close Settings")
    }

    // MARK: Helpers

    /// Presses a key until `done`, four times at most. The first ⌘F and the first ⌘+ of a launch
    /// often do nothing in a simulator under XCUITest (November 12, 2026: a later press works, and
    /// so do ⌘N, ⌘[ and the single keys the first time; iPadOS has commands of its own on both,
    /// Find and Bigger), so those two are pressed again when nothing came of a press. Whether a
    /// real keyboard's first press is lost too is not known.
    @MainActor
    private func press(_ key: String, _ flags: XCUIElement.KeyModifierFlags, in app: XCUIApplication, until done: () -> Bool) -> Bool {
        for attempt in 1...4 {
            if attempt > 1 {
                XCTContext.runActivity(named: "Nothing came of \(key), pressed \(attempt - 1) time(s): pressing it again") { _ in }
            }
            app.typeKey(key, modifierFlags: flags)
            if waitUntil(timeout: 4, done) { return true }
        }
        return false
    }

    /// As `PaintingNavigationTests`': a state waited for persists once reached, so a long wait only
    /// absorbs a busy simulator's stalls.
    private static let stateTimeout: TimeInterval = 15

    /// The middle half of the screen, clear of the status bar and the chrome.
    @MainActor
    private func canvasArea(of shot: XCUIScreenshot) -> Data? {
        guard let image = shot.image.cgImage else { return nil }
        let rect = CGRect(x: 0, y: image.height / 4, width: image.width, height: image.height / 2)
        return image.cropping(to: rect).flatMap { UIImage(cgImage: $0).pngData() }
    }

    /// The canvas once it has come to rest (two looks a second apart alike): what a key's effect is
    /// told from.
    @MainActor
    private func stillCanvas(of app: XCUIApplication) throws -> Data {
        var last = canvasArea(of: app.screenshot())
        for _ in 0..<10 {
            sleep(1)
            let now = canvasArea(of: app.screenshot())
            if let now, now == last { return now }
            last = now
        }
        attachScreenshot(of: app, named: "canvas-never-still")
        XCTFail("The canvas never came to rest, so a key's effect can't be told from the screen")
        throw CancellationError()
    }

    /// Launches the demo that seeds a painting in the background and opens it once it is ready.
    @MainActor
    private func openSeededPainting() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "gallery-open"]
        app.launch()
        let badge = app.staticTexts.matching(NSPredicate(format: "label ENDSWITH 'percent painted'")).firstMatch
        XCTAssertTrue(badge.waitForExistence(timeout: 90), "The painting didn't open")
        XCTAssertTrue(waitUntil(timeout: 15) { badge.isHittable && app.buttons["Back"].isHittable })
        sleep(2)
        return app
    }

    @MainActor
    private func launchGallery() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "gallery", "-demoFixedPictures", "YES"]
        app.launch()
        XCTAssertTrue(app.buttons["Paint"].waitForExistence(timeout: 90), "The gallery didn't open")
        sleep(1)
        return app
    }
}
