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

    /// Smallest Area moves one VoiceOver step at a time; the preview regenerates with fewer
    /// areas than the defaults' and the setting's effect is measured; the Pipeline section
    /// offers Reset, and Reset All (confirmed) puts everything back.
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

        // Settings an earlier, interrupted run may have left behind go first.
        let resetAll = app.descendants(matching: .any)["advanced-reset-all"]
        reveal(resetAll, in: list, up: true)
        if resetAll.isEnabled { confirmResetAll(app, resetAll) }

        let control = app.descendants(matching: .any)["advanced-control-minimumCellSize"]
        reveal(control, in: list, up: false)
        XCTAssertTrue(control.exists, "Pipeline has no Smallest Area slider")
        XCTAssertTrue(value(of: control).hasPrefix("1×"), "Smallest Area doesn't start at 1×: \(value(of: control))")
        XCTAssertTrue(value(of: areas).contains("Default"), "The areas don't start at the defaults: \(value(of: areas))")
        // Four quarter doublings: twice the smallest area.
        for _ in 0..<4 { control.increment() }
        let doubled = NSPredicate(format: "value BEGINSWITH '2×'")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: doubled, object: control)], timeout: 5), .completed,
                       "Four steps didn't take Smallest Area to 2×: \(value(of: control))")
        // Larger smallest areas: fewer of them than at the defaults.
        let fewer = NSPredicate(format: "value CONTAINS %@", "−")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: fewer, object: areas)], timeout: 90), .completed,
                       "The preview's areas didn't go down: \(value(of: areas))")
        let measured = NSPredicate(format: "value CONTAINS %@", "−")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: measured, object: control)], timeout: 90), .completed,
                       "Smallest Area's effect was never measured as fewer areas: \(value(of: control))")
        XCTAssertTrue(app.buttons["advanced-reset-pipeline"].waitForExistence(timeout: 5), "Pipeline offers no Reset")
        attachScreenshot(of: app, named: "advanced-changed")

        reveal(resetAll, in: list, up: true)
        XCTAssertTrue(resetAll.isEnabled, "Reset All Settings is off with a setting changed")
        confirmResetAll(app, resetAll)
        reveal(control, in: list, up: false)
        let reset = NSPredicate(format: "value BEGINSWITH '1×'")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: reset, object: control)], timeout: 5), .completed,
                       "Reset All didn't put Smallest Area back: \(value(of: control))")
        XCTAssertFalse(app.buttons["advanced-reset-pipeline"].exists, "Pipeline still offers Reset at its defaults")
        // The defaults' preview was kept: their numbers are back at once.
        let back = NSPredicate(format: "value CONTAINS 'Default'")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: back, object: areas)], timeout: 10), .completed,
                       "The areas didn't go back to the defaults': \(value(of: areas))")
    }

    @MainActor
    private func confirmResetAll(_ app: XCUIApplication, _ button: XCUIElement) {
        button.tap()
        let confirm = app.buttons["Reset All"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "Reset All Settings asks for no confirmation")
        confirm.tap()
    }

    /// Scrolls the settings list until `element` can be tapped: towards the end (`up`) or back.
    @MainActor
    private func reveal(_ element: XCUIElement, in list: XCUIElement, up: Bool, maxSwipes: Int = 12) {
        var swipes = 0
        while !(element.exists && element.isHittable) && swipes < maxSwipes {
            if up { list.swipeUp() } else { list.swipeDown() }
            swipes += 1
        }
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
