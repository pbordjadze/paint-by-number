import XCTest

/// The create preview's Refine button once the sliders have been moved. Refine draws on the final
/// template of the sliders' settings alone, which a full resolution takes tens of seconds to make
/// again on a phone (a simulator takes one or two, so `-slowFullResolution` makes them wait): the
/// button stays on meanwhile, a tap shows "Preparing…", and Refine opens by itself once the
/// template is made. Each test moves sliders as a painter does, taps Refine while the status still
/// says "Updating…" and notes how long Refine took to open (`refine-after-*`).
final class RefineAfterSlidersTests: XCTestCase {
    /// How long each full resolution waits before it starts.
    private static let delay = 8

    /// A drag of Detail, the slider Paul moved, released.
    @MainActor
    func testRefineOpensByItselfAfterADrag() throws {
        let app = launchPreview()
        let detail = settingSlider("Detail", in: app)
        centre(detail, in: app)
        let before = detail.value as? String
        drag(detail, to: 0.95)
        XCTAssertNotEqual(detail.value as? String, before, "The drag didn't move Detail")
        attachScreenshot(of: app, named: "drag-released")
        tapRefine(app, after: "a drag of Detail")
    }

    /// A tap on a slider's track, away from its thumb (it moves nothing), while the painting is
    /// being made again.
    @MainActor
    func testRefineOpensAfterATapOnTheTrack() throws {
        let app = launchPreview()
        drag(settingSlider("Lines", in: app), to: 0.9)
        XCTAssertTrue(app.staticTexts["Updating…"].waitForExistence(timeout: 10), "The painting never said it was updating")
        let detail = settingSlider("Detail", in: app)
        let before = detail.value as? String
        detail.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        attachNote("Detail read \(before ?? "nil"), then \(detail.value as? String ?? "nil") after the tap", named: "track-tap")
        tapRefine(app, after: "a tap on Detail's track")
    }

    /// Two drags of two sliders, one after the other.
    @MainActor
    func testRefineOpensAfterTwoQuickDrags() throws {
        let app = launchPreview()
        centre(settingSlider("Detail", in: app), in: app)
        drag(settingSlider("Lines", in: app), to: 0.9)
        drag(settingSlider("Detail", in: app), to: 0.1)
        tapRefine(app, after: "two quick drags")
    }

    /// A touch on a slider that moves nothing, while the painting is being made again: it used to
    /// cancel the template being made and let go with no other, and Refine never came on.
    @MainActor
    func testATouchDuringTheUpdateDoesntLoseTheTemplate() throws {
        let app = launchPreview()
        centre(settingSlider("Smoothness", in: app), in: app)
        drag(settingSlider("Lines", in: app), to: 0.9)
        XCTAssertTrue(app.staticTexts["Updating…"].waitForExistence(timeout: 10), "The painting never said it was updating")
        let smoothness = settingSlider("Smoothness", in: app)
        // Smoothness rests in its middle, where its thumb is: a press there moves nothing.
        let smoothValue = smoothness.value as? String
        smoothness.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.05)
        XCTAssertEqual(smoothness.value as? String, smoothValue, "The touch moved Smoothness")
        attachScreenshot(of: app, named: "touched-while-updating")
        tapRefine(app, after: "a touch on Smoothness during the update")
    }

    /// Refine tapped while the painting updates is called off by going back to a slider: it
    /// doesn't open by itself once the painting is made, and a tap then opens it at once.
    @MainActor
    func testTouchingASliderCallsOffAWaitingRefine() throws {
        let app = launchPreview()
        let refine = app.buttons["refine"]
        let canvas = app.descendants(matching: .any)["refine-canvas"]
        centre(settingSlider("Smoothness", in: app), in: app)
        drag(settingSlider("Lines", in: app), to: 0.9)
        XCTAssertTrue(app.staticTexts["Updating…"].waitForExistence(timeout: 10), "The painting never said it was updating")
        refine.tap()
        XCTAssertTrue(
            waitUntil(timeout: 5) { refine.value as? String == "Preparing…" },
            "Refine tapped while updating doesn't say it is waiting: \(refine.value ?? "")")
        attachScreenshot(of: app, named: "preparing")

        // Back to a slider: a drag, as a touch that moves nothing needn't count as one for a slider.
        drag(settingSlider("Smoothness", in: app), to: 0.6)
        XCTAssertTrue(
            waitFor(refine, toMatch: NSPredicate(format: "value == %@", "No changes"), timeout: 5),
            "A drag of a slider didn't call the wait off: \(refine.value ?? "")")
        settle(app)
        Thread.sleep(forTimeInterval: 2)
        XCTAssertFalse(canvas.exists, "Refine opened by itself after the wait was called off")

        refine.tap()
        XCTAssertTrue(canvas.waitForExistence(timeout: 10), "Refine didn't open at once on the final template")
    }

    // MARK: - Helpers

    /// The Great Wave's preview, once Refine is on, with each full resolution made to wait.
    @MainActor
    private func launchPreview() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "create-preview", "-demoFixedPictures", "YES", "-slowFullResolution", "\(Self.delay)"]
        app.launch()
        let start = app.buttons["Start Painting"]
        XCTAssertTrue(start.waitForExistence(timeout: 30), "The preview didn't open")
        let enabled = NSPredicate(format: "isEnabled == true")
        XCTAssertTrue(waitFor(start, toMatch: enabled, timeout: 120), "The preview never finished choosing its settings")
        XCTAssertTrue(waitFor(app.buttons["refine"], toMatch: enabled, timeout: 120), "Refine never came on")
        settle(app)
        return app
    }

    /// Waits for the painting to be made: the status has no "Updating…" or "Making the painting…".
    @MainActor
    private func settle(_ app: XCUIApplication) {
        // The full resolution starts a moment after a slider moved.
        _ = app.staticTexts["Updating…"].waitForExistence(timeout: 3)
        let gone = NSPredicate(format: "exists == false")
        for text in ["Making the painting…", "Updating…"] {
            XCTAssertTrue(waitFor(app.staticTexts[text], toMatch: gone, timeout: 120), "“\(text)” never went")
        }
    }

    /// Puts a slider's thumb in the middle of its track, where a touch finds it, and waits for the
    /// painting to be made again.
    @MainActor
    private func centre(_ slider: XCUIElement, in app: XCUIApplication) {
        slider.adjust(toNormalizedSliderPosition: 0.5)
        settle(app)
    }

    /// A finger put on `slider`'s thumb, dragged to `position` and lifted. The thumb rests where its
    /// setting's detents put it, not always mid-track (Smoothness on an iPad), and a press beside it
    /// moves nothing.
    @MainActor
    private func drag(_ slider: XCUIElement, to position: CGFloat) {
        slider.coordinate(withNormalizedOffset: CGVector(dx: slider.normalizedSliderPosition, dy: 0.5))
            .press(forDuration: 0.1, thenDragTo: slider.coordinate(withNormalizedOffset: CGVector(dx: position, dy: 0.5)))
    }

    /// Taps Refine, which is on while the painting updates, and waits up to two minutes for Refine
    /// to open; notes whether the status still said "Updating…", whether the button said it was
    /// preparing and how long it took. Done leaves again.
    @MainActor
    private func tapRefine(_ app: XCUIApplication, after what: String) {
        let refine = app.buttons["refine"]
        let canvas = app.descendants(matching: .any)["refine-canvas"]
        XCTAssertTrue(refine.isEnabled, "Refine was off after \(what)")
        let updating = app.staticTexts["Updating…"].exists
        let began = Date()
        refine.tap()
        // The button says so a moment after the tap (one read straight after it found the old value
        // now and then), unless the template was made between the status's read and the tap and
        // Refine opened at once. Read afresh each time: a predicate expectation can time out while
        // the app is busy with the element already matching. Preparing… seen once counts: Refine
        // may open before a second read.
        var sawPreparing = false
        _ = waitUntil(timeout: 5) {
            if refine.value as? String == "Preparing…" { sawPreparing = true }
            return sawPreparing || canvas.exists
        }
        let preparing = sawPreparing
        let openedAtOnce = !preparing && canvas.exists
        if preparing { attachScreenshot(of: app, named: "preparing-after-\(what)") }
        let opened = canvas.waitForExistence(timeout: 120)
        let took = Date().timeIntervalSince(began)
        attachNote(
            "Refine tapped after \(what), when “Updating…” \(updating ? "showed" : "had gone"): the button \(preparing ? "said Preparing…" : openedAtOnce ? "opened Refine at once" : "did not say Preparing…"); Refine \(opened ? "opened" : "DID NOT OPEN") \(String(format: "%.1f", took)) s after the tap",
            named: "refine-after-\(what)")
        XCTAssertTrue(opened, "Refine didn't open \(Int(took)) s after a tap that followed \(what)")
        if updating && !openedAtOnce {
            XCTAssertTrue(preparing, "Refine tapped while the painting updated didn't say it was preparing")
        }
        app.buttons["refine-done"].tap()
        XCTAssertTrue(
            waitFor(refine, toMatch: NSPredicate(format: "value == %@", "No changes")), "Done didn't leave Refine: \(refine.value ?? "")")
    }
}
