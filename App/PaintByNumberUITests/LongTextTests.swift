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

    @MainActor
    private func attachScreenshot(of app: XCUIApplication, named name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
