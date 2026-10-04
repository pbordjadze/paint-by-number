import XCTest

/// Screens with every localized string twice as long (`-NSDoubleLocalizedStrings YES`), standing in
/// for long translations: controls stay whole, tappable and on screen, and the selected color's
/// name is still shown. Labels are matched by prefix because the system doubles them.
final class LongTextTests: XCTestCase {
    @MainActor
    func testPaintingBarsKeepTheirControlsAndTheColorName() {
        let app = launch("paint-long-text")
        XCTAssertTrue(button(app, labelPrefix: "Close").waitForExistence(timeout: 60), "The painting didn't open")
        sleep(3)
        attachScreenshot(of: app, named: "paint-long-text")
        let window = app.windows.firstMatch.frame
        for prefix in ["Close", "Undo", "More"] {
            let control = button(app, labelPrefix: prefix)
            XCTAssertTrue(control.exists, "\(prefix) is missing")
            XCTAssertTrue(control.isHittable, "\(prefix) can't be tapped")
            XCTAssertTrue(window.contains(control.frame), "\(prefix) is cut off")
        }
        let color = app.descendants(matching: .any)["current-color"]
        XCTAssertTrue(color.exists, "The selected color's name isn't on screen")
        XCTAssertTrue(window.contains(color.frame), "The selected color's name runs off the screen")
    }

    @MainActor
    func testCompletionBarKeepsDoneAndReplay() {
        let app = launch("paint-complete-long-text")
        XCTAssertTrue(button(app, labelPrefix: "Done").waitForExistence(timeout: 60), "The finished painting didn't open")
        sleep(2)
        attachScreenshot(of: app, named: "paint-complete-long-text")
        let window = app.windows.firstMatch.frame
        for prefix in ["Done", "Replay"] {
            let control = button(app, labelPrefix: prefix)
            XCTAssertTrue(control.exists, "\(prefix) is missing")
            XCTAssertTrue(control.isHittable, "\(prefix) can't be tapped")
            XCTAssertTrue(window.contains(control.frame), "\(prefix) is cut off")
        }
    }

    /// The Undo toast of a deleted painting fits the screen with its action beside a long message.
    @MainActor
    func testGalleryToastFitsTheScreen() {
        let app = launch("gallery-long-text")
        let toast = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Undo'")).firstMatch
        XCTAssertTrue(toast.waitForExistence(timeout: 150), "The gallery never showed the deletion's Undo toast")
        // Measured at once: the toast leaves when the undo window closes.
        let frame = toast.frame
        attachScreenshot(of: app, named: "gallery-long-text")
        XCTAssertTrue(app.windows.firstMatch.frame.contains(frame), "The toast runs off the screen")
    }

    /// The Favorites filter's empty state and the Show menu's button fit the screen when text doubles.
    @MainActor
    func testNoFavoritesStateAndShowMenuFitTheScreen() {
        let app = launch("gallery-no-favorites-long-text")
        let title = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'No Favorites'")).firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 150), "The Favorites filter shows no empty state")
        let show = button(app, labelPrefix: "Show")
        // The menu is disabled while the demo library is still being made.
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: show)
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 150), .completed, "The Show menu never became available")
        attachScreenshot(of: app, named: "gallery-no-favorites-long-text")
        let window = app.windows.firstMatch.frame
        XCTAssertTrue(show.isHittable, "The Show menu can't be tapped")
        XCTAssertTrue(window.contains(show.frame), "The Show menu is cut off")
        XCTAssertTrue(window.contains(title.frame), "The empty state's title runs off the screen")
    }

    /// The time-lapse sheet keeps its title and Pace control on screen (the control becomes a menu
    /// at accessibility sizes, so it is found by identifier, whichever form it takes).
    @MainActor
    func testTimelapseSheetKeepsItsPaceControl() {
        let app = launch("gallery-timelapse-long-text")
        let title = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Making Your Time-lapse'")).firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 150), "The time-lapse sheet never opened")
        attachScreenshot(of: app, named: "gallery-timelapse-long-text")
        let pace = app.descendants(matching: .any)["timelapse-pace"]
        XCTAssertTrue(pace.exists, "The Pace control is missing")
        XCTAssertTrue(app.windows.firstMatch.frame.contains(pace.frame), "The Pace control is cut off")
    }

    /// The create flow's settings chip keeps Reset to Suggested whole and tappable.
    @MainActor
    func testCreateSettingsChipKeepsReset() {
        let app = launch("create-custom-long-text")
        let reset = app.buttons["settings-origin"]
        XCTAssertTrue(reset.waitForExistence(timeout: 150), "The create flow never offered Reset to Suggested")
        sleep(1)
        attachScreenshot(of: app, named: "create-custom-long-text")
        XCTAssertTrue(reset.isHittable, "Reset to Suggested can't be tapped")
        XCTAssertTrue(app.windows.firstMatch.frame.contains(reset.frame), "Reset to Suggested is cut off")
    }

    @MainActor
    func testSettingsKeepsItsDoneButton() {
        let app = launch("settings-long-text")
        let done = button(app, labelPrefix: "Done")
        XCTAssertTrue(done.waitForExistence(timeout: 30), "The settings sheet didn't open")
        attachScreenshot(of: app, named: "settings-long-text")
        XCTAssertTrue(done.isHittable, "Done can't be tapped")
        XCTAssertTrue(app.windows.firstMatch.frame.contains(done.frame), "Done is cut off")
    }

    // MARK: Helpers

    @MainActor
    private func launch(_ scenario: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", scenario, "-NSDoubleLocalizedStrings", "YES"]
        app.launch()
        return app
    }

    @MainActor
    private func button(_ app: XCUIApplication, labelPrefix prefix: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
    }
}
