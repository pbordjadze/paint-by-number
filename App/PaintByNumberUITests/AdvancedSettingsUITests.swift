import XCTest

/// Settings › Advanced: it opens from Settings on its preview's numbers, and a slider changes
/// those numbers, shows its effect and goes back to its default.
final class AdvancedSettingsUITests: XCTestCase {
    /// The Advanced row (marked Experimental) opens the screen; the preview's picture is
    /// prepared and its numbers appear.
    @MainActor
    func testAdvancedOpensFromSettingsWithThePreviewsNumbers() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "gallery-empty"]
        app.launch()
        let settings = app.buttons["Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 30), "The gallery has no Settings button")
        settings.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 10), "The settings sheet didn't open")
        let row = app.descendants(matching: .any)["settings-advanced"]
        var swipes = 0
        while !(row.exists && row.isHittable) && swipes < 8 {
            app.swipeUp()
            swipes += 1
        }
        XCTAssertTrue(row.exists, "Settings has no Advanced row")
        XCTAssertTrue(row.label.contains("Experimental"), "The Advanced row isn't marked Experimental: \(row.label)")
        row.tap()

        XCTAssertTrue(app.descendants(matching: .any)["advanced-preview"].waitForExistence(timeout: 15), "Advanced didn't open")
        let areas = app.descendants(matching: .any)["advanced-stat-areas"]
        XCTAssertTrue(areas.waitForExistence(timeout: 10), "The preview has no areas count")
        let counted = NSPredicate(format: "value MATCHES %@", ".*[0-9].*")
        XCTAssertEqual(
            XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: counted, object: areas)], timeout: 120), .completed,
            "The preview's areas never showed: \(areas.value as? String ?? "")")
        XCTAssertTrue(app.descendants(matching: .any)["advanced-intro"].exists, "The screen doesn't say what its settings apply to")
        attachScreenshot(of: app, named: "advanced-from-settings")
    }

    /// Smallest Area moved to about 2×: the preview regenerates with fewer areas than the
    /// defaults' and the setting's effect is measured; the Pipeline section's Reset puts it
    /// back, and the defaults' numbers return.
    @MainActor
    func testASliderChangesThePreviewsNumbersAndResets() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "settings-advanced"]
        app.launch()
        let list = app.descendants(matching: .any)["advanced-controls"].firstMatch
        XCTAssertTrue(list.waitForExistence(timeout: 60), "Advanced didn't open")
        let areas = app.descendants(matching: .any)["advanced-stat-areas"]
        XCTAssertEqual(
            XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value MATCHES %@", ".*[0-9].*"), object: areas)],
                           timeout: 120), .completed, "The preview never got its numbers")

        let control = app.sliders["advanced-control-minimumCellSize"]
        reveal(control, in: list)
        XCTAssertTrue(control.exists, "Pipeline has no Smallest Area slider")
        let sectionReset = app.buttons["advanced-reset-pipeline"]
        // Settings an earlier, interrupted run may have left behind go first.
        if sectionReset.exists { sectionReset.tap() }
        XCTAssertTrue(value(of: control).hasPrefix("1×"), "Smallest Area doesn't start at 1×: \(value(of: control))")
        // From the thumb at 1×, the middle of the log scale from 0.25× to 4×, to three quarters of
        // the way along: about twice the smallest area. Not `adjust(toNormalizedSliderPosition:)`,
        // which finds the thumb from a value read as a percentage ("1×" isn't one). A drag the
        // simulator drops now and then (a touch on a list still settling only stops it) is
        // tried once more.
        let moved = NSPredicate(format: "NOT (value BEGINSWITH '1×')")
        var attempts = 0
        repeat {
            waitUntilStill(control)
            control.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                .press(forDuration: 0.2, thenDragTo: control.coordinate(withNormalizedOffset: CGVector(dx: 0.78, dy: 0.5)))
            attempts += 1
        } while XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: moved, object: control)], timeout: 5) != .completed && attempts < 2
        XCTAssertFalse(value(of: control).hasPrefix("1×"), "The slider didn't move Smallest Area: \(value(of: control))")
        // Larger smallest areas: fewer of them than at the defaults.
        let fewer = NSPredicate(format: "value CONTAINS %@", "−")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: fewer, object: areas)], timeout: 90), .completed,
                       "The preview's areas didn't go down: \(value(of: areas))")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: fewer, object: control)], timeout: 90), .completed,
                       "Smallest Area's effect was never measured as fewer areas: \(value(of: control))")
        attachScreenshot(of: app, named: "advanced-changed")

        reveal(sectionReset, in: list, up: false)
        XCTAssertTrue(sectionReset.exists, "Pipeline offers no Reset with a setting changed")
        sectionReset.tap()
        let reset = NSPredicate(format: "value BEGINSWITH '1×'")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: reset, object: control)], timeout: 5), .completed,
                       "Reset didn't put Smallest Area back: \(value(of: control))")
        // The defaults' preview was kept: their numbers are back at once.
        let back = NSPredicate(format: "value CONTAINS 'Default'")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: back, object: areas)], timeout: 10), .completed,
                       "The areas didn't go back to the defaults': \(value(of: areas))")
        XCTAssertFalse(sectionReset.exists, "Pipeline still offers Reset at its defaults")
    }

    /// Scrolls the settings list until `element` can be tapped well inside it: towards the end
    /// (`up`) or back. Short drags held at the end, so the list never coasts past it (on iPhone
    /// it is a third of the screen, and a swipe flung it past the Pipeline header), along the
    /// leading margin, clear of slider thumbs. Hittable is not enough: a slider left in the
    /// list's bottom strip, by the home indicator, got its drag taken by the system.
    @MainActor
    private func reveal(_ element: XCUIElement, in list: XCUIElement, up: Bool = true, maxDrags: Int = 30) {
        let low = list.coordinate(withNormalizedOffset: CGVector(dx: 0.06, dy: 0.75))
        let high = list.coordinate(withNormalizedOffset: CGVector(dx: 0.06, dy: 0.35))
        var drags = 0
        while drags < maxDrags {
            if isWellInside(element, list) { return }
            let (from, to) = up ? (low, high) : (high, low)
            from.press(forDuration: 0.05, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 0.2)
            drags += 1
        }
    }

    /// `element` can be tapped and, once the list has stopped, its middle lies in the list's
    /// middle band (from 15 % down to 30 % up from the bottom), clear of the edges.
    @MainActor
    private func isWellInside(_ element: XCUIElement, _ list: XCUIElement) -> Bool {
        guard element.exists, element.isHittable, let settled = settledFrame(of: element) else { return false }
        let frame = list.frame
        return (frame.minY + frame.height * 0.15...frame.maxY - frame.height * 0.3).contains(settled.midY)
    }

    /// Waits (up to 3 s) until `element` stays put for a moment: the list has stopped scrolling.
    @MainActor
    private func waitUntilStill(_ element: XCUIElement) { _ = settledFrame(of: element) }

    /// `element`'s frame once it has stayed put for half a second (the list has stopped
    /// scrolling), or nil when it leaves the screen meanwhile: a row still coasting out of view
    /// exists one moment and has no frame to read the next, which XCTest counts as a failure.
    @MainActor
    private func settledFrame(of element: XCUIElement) -> CGRect? {
        var last: CGRect?
        var still = 0
        let deadline = Date().addingTimeInterval(3)
        while still < 2 && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
            guard element.exists else { return nil }
            let frame = element.frame
            still = frame == last ? still + 1 : 0
            last = frame
        }
        return last
    }

    @MainActor
    private func value(of element: XCUIElement) -> String { element.value as? String ?? "" }

    @MainActor
    private func attachScreenshot(of app: XCUIApplication, named name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
