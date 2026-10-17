import XCTest

/// The create preview's Refine button once the sliders have been moved. Refine draws on the final
/// template of the sliders' settings alone, so after a slider moves the button waits for the
/// painting to be made again at full resolution; each test moves sliders like a painter does, then
/// times how long the button takes to come back and how long the status says "Updating…".
final class RefineAfterSlidersTests: XCTestCase {
    /// A drag of Detail, the slider Paul moved, released.
    @MainActor
    func testADragThenRefine() throws {
        let app = launchPreview()
        let detail = app.sliders["Detail"]
        centre(detail, in: app)
        let before = detail.value as? String
        drag(detail, to: 0.95)
        XCTAssertNotEqual(detail.value as? String, before, "The drag didn't move Detail")
        attachScreenshot(of: app, named: "drag-released")
        awaitRefine(app, after: "a drag of Detail")
    }

    /// A tap on a slider's track, away from its thumb.
    @MainActor
    func testATapOnTheTrackThenRefine() throws {
        let app = launchPreview()
        let detail = app.sliders["Detail"]
        centre(detail, in: app)
        let before = detail.value as? String
        detail.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        attachNote("Detail read \(before ?? "nil"), then \(detail.value as? String ?? "nil") after the tap", named: "track-tap")
        attachScreenshot(of: app, named: "track-tapped")
        awaitRefine(app, after: "a tap on Detail's track")
    }

    /// Two drags of two sliders, one after the other.
    @MainActor
    func testTwoQuickDragsThenRefine() throws {
        let app = launchPreview()
        let detail = app.sliders["Detail"], lines = app.sliders["Lines"]
        centre(detail, in: app)
        drag(lines, to: 0.9)
        drag(detail, to: 0.1)
        attachScreenshot(of: app, named: "two-drags-released")
        awaitRefine(app, after: "two quick drags")
    }

    /// A touch on a slider that moves nothing, while the painting is being made again.
    @MainActor
    func testATouchDuringTheUpdateThenRefine() throws {
        let app = launchPreview()
        let detail = app.sliders["Detail"], lines = app.sliders["Lines"]
        centre(detail, in: app)
        drag(detail, to: 0.95)
        let updating = app.staticTexts["Updating…"]
        XCTAssertTrue(updating.waitForExistence(timeout: 10), "The painting never said it was updating")
        // Lines rests in its middle, where its thumb is: a press there moves nothing.
        let lineValue = lines.value as? String
        lines.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.05)
        XCTAssertEqual(lines.value as? String, lineValue, "The touch moved Lines")
        attachScreenshot(of: app, named: "touched-while-updating")
        awaitRefine(app, after: "a touch on Lines during the update")
    }

    // MARK: - Helpers

    /// The Great Wave's preview, once Refine is ready on its suggested settings.
    @MainActor
    private func launchPreview() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "create-preview", "-demoFixedPictures", "YES"]
        app.launch()
        let start = app.buttons["Start Painting"]
        XCTAssertTrue(start.waitForExistence(timeout: 30), "The preview didn't open")
        let enabled = NSPredicate(format: "isEnabled == true")
        XCTAssertTrue(waitFor(start, toMatch: enabled, timeout: 120), "The preview never finished choosing its settings")
        XCTAssertTrue(
            waitFor(app.buttons["refine"], toMatch: enabled, timeout: 120), "The preview never became ready to refine")
        return app
    }

    /// Puts a slider's thumb in the middle of its track, where a touch finds it, and waits for the
    /// painting to be made again.
    @MainActor
    private func centre(_ slider: XCUIElement, in app: XCUIApplication) {
        slider.adjust(toNormalizedSliderPosition: 0.5)
        awaitRefine(app, after: "\(slider.label) adjusted to the middle")
    }

    /// A finger put on the thumb in the middle of `slider`, dragged to `position` and lifted.
    @MainActor
    private func drag(_ slider: XCUIElement, to position: CGFloat) {
        slider.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.1, thenDragTo: slider.coordinate(withNormalizedOffset: CGVector(dx: position, dy: 0.5)))
    }

    /// Waits up to two minutes for Refine to be enabled, and notes how long it took and when the
    /// status said "Updating…".
    @MainActor
    @discardableResult
    private func awaitRefine(_ app: XCUIApplication, after what: String) -> Bool {
        let refine = app.buttons["refine"]
        // The button goes off a moment after the slider moved.
        Thread.sleep(forTimeInterval: 0.5)
        let began = Date()
        var updating: (first: TimeInterval, last: TimeInterval)?
        var enabled = false
        while Date().timeIntervalSince(began) < 120 {
            let now = Date().timeIntervalSince(began)
            if refine.isEnabled {
                enabled = true
                break
            }
            if app.staticTexts["Updating…"].exists { updating = (updating?.first ?? now, now) }
            Thread.sleep(forTimeInterval: 0.25)
        }
        let took = Date().timeIntervalSince(began)
        let said = updating.map { "“Updating…” seen from \(String(format: "%.1f", $0.first)) s to \(String(format: "%.1f", $0.last)) s" }
            ?? "“Updating…” never seen"
        attachNote(
            "Refine after \(what): \(enabled ? "enabled after \(String(format: "%.1f", took)) s" : "STILL DISABLED after \(String(format: "%.0f", took)) s"); \(said)",
            named: "refine-after-\(what)")
        if !enabled { attachScreenshot(of: app, named: "refine-stuck-after-\(what)") }
        XCTAssertTrue(enabled, "Refine was still disabled \(Int(took)) s after \(what); \(said)")
        return enabled
    }
}
