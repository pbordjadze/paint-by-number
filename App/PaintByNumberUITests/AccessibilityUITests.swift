import UIKit
import XCTest

/// What VoiceOver reads on the painting screen, and the screen at the largest text sizes.
final class AccessibilityUITests: XCTestCase {
    /// Swatches say their number, nickname and plain color name ("12, Harbor Fog, dark grayish blue")
    /// and how far they are painted; the selected color's name is on screen for people who can't
    /// tell the paints apart by eye.
    @MainActor
    func testSwatchesSpeakNumberAndColorName() throws {
        let app = launch(["-demo", "paint-ax"])
        let swatches = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'swatch-'")).allElementsBoundByIndex
        XCTAssertFalse(swatches.isEmpty)
        for swatch in swatches {
            let label = swatch.label
            XCTAssertNotNil(
                label.range(of: #"^[0-9]+, [A-Z][A-Za-z]+( [A-Za-z]+)?(-[A-Za-z]+)?, [a-z]+( [a-z]+){0,3}$"#, options: .regularExpression), label)
            XCTAssertEqual(label.split(separator: ",").first.map(String.init), String(swatch.identifier.dropFirst("swatch-".count)))
            let value = swatch.value as? String ?? ""
            XCTAssertNotNil(value.range(of: #"^(finished|[0-9]{1,3} percent painted)$"#, options: .regularExpression), value)
        }
        let selected = swatches.filter(\.isSelected)
        XCTAssertEqual(selected.count, 1)
        let current = app.descendants(matching: .any)["current-color"]
        XCTAssertTrue(current.exists, "The selected color's name isn't on screen")
        XCTAssertEqual(current.value as? String, selected.first?.label)
        attachScreenshot(of: app, named: "paint-ax")
    }

    /// Under Plain color names the swatches read as before: number and structured name only.
    @MainActor
    func testPlainColorNamesDropTheNicknames() throws {
        let app = launch(["-demo", "paint-names-plain"])
        let swatches = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'swatch-'")).allElementsBoundByIndex
        XCTAssertFalse(swatches.isEmpty)
        for swatch in swatches {
            XCTAssertNotNil(
                swatch.label.range(of: #"^[0-9]+, [a-z]+( [a-z]+){0,3}$"#, options: .regularExpression), swatch.label)
        }
        let current = app.descendants(matching: .any)["current-color"]
        XCTAssertTrue(current.exists, "The selected color's name isn't on screen")
        XCTAssertEqual(current.value as? String, swatches.first(where: \.isSelected)?.label)
        attachScreenshot(of: app, named: "paint-names-plain")
    }

    /// A long press on a swatch shows its number, nickname, shade and hex code, and leaves the
    /// selected color alone.
    @MainActor
    func testLongPressShowsTheColorDetails() throws {
        let app = launch(["-demo", "paint-ax"])
        let swatches = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'swatch-'")).allElementsBoundByIndex
        let window = app.windows.firstMatch.frame
        let target = try XCTUnwrap(swatches.first { !$0.isSelected && window.contains($0.frame) })
        let selectedBefore = swatches.first(where: \.isSelected)?.identifier
        let parts = target.label.components(separatedBy: ", ")
        XCTAssertEqual(parts.count, 3, target.label)
        target.press(forDuration: 1)
        let details = app.descendants(matching: .any)["swatch-details"]
        XCTAssertTrue(details.waitForExistence(timeout: 10), "Long-pressing \(target.identifier) showed no details")
        attachScreenshot(of: app, named: "paint-swatch-details")
        let number = app.descendants(matching: .any)["swatch-details-number"]
        XCTAssertTrue(number.label.contains(String(target.identifier.dropFirst("swatch-".count))), number.label)
        XCTAssertTrue(app.descendants(matching: .any)["swatch-details-name"].label.contains(parts[1]))
        XCTAssertTrue(app.descendants(matching: .any)["swatch-details-shade"].label.localizedCaseInsensitiveContains(parts[2]))
        let hex = app.descendants(matching: .any)["swatch-details-hex"].label
        XCTAssertNotNil(hex.range(of: #"#[0-9A-F]{6}$"#, options: .regularExpression), hex)
        // Dismiss by tapping outside the popover: that touch only closes it.
        app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.5)).tap()
        XCTAssertTrue(waitForDisappearance(of: details), "The details didn't close")
        let selectedAfter = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'swatch-' AND selected == true")).firstMatch
        XCTAssertEqual(selectedAfter.identifier, selectedBefore, "The long press changed the selected color")
    }

    /// Plain names have no nickname row.
    @MainActor
    func testPlainDetailsHaveNoNameRow() throws {
        let app = launch(["-demo", "paint-names-plain"])
        // Finished colors leave the palette: press one that is still on screen.
        let swatches = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'swatch-'"))
        XCTAssertTrue(swatches.firstMatch.waitForExistence(timeout: 10))
        let window = app.windows.firstMatch.frame
        let swatch = try XCTUnwrap(swatches.allElementsBoundByIndex.first { window.contains($0.frame) })
        swatch.press(forDuration: 1)
        XCTAssertTrue(app.descendants(matching: .any)["swatch-details"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.descendants(matching: .any)["swatch-details-name"].exists, "Plain names show a nickname")
        XCTAssertTrue(app.descendants(matching: .any)["swatch-details-shade"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["swatch-details-hex"].exists)
    }

    /// The canvas offers the unpainted areas of the selected color to VoiceOver, top to bottom,
    /// and activating one paints it.
    @MainActor
    func testCanvasOffersUnpaintedAreas() throws {
        let app = launch(["-demo", "paint-ax"])
        let swatch = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'swatch-' AND selected == true")).firstMatch
        XCTAssertTrue(swatch.exists)
        let number = String(swatch.identifier.dropFirst("swatch-".count))
        let query = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'canvas-area-'"))
        let areas = query.allElementsBoundByIndex
        XCTAssertTrue((1...40).contains(areas.count), "\(areas.count) areas")
        let window = app.windows.firstMatch.frame
        for area in areas {
            XCTAssertEqual(area.label, "Area \(number)")
            let value = area.value as? String ?? ""
            XCTAssertTrue(value.hasPrefix("not painted"), value)
            XCTAssertTrue(window.contains(area.frame), "\(area.identifier) is outside the window")
        }
        for (a, b) in zip(areas, areas.dropFirst()) {
            XCTAssertGreaterThanOrEqual(b.frame.midY, a.frame.midY - 44, "\(b.identifier) goes back up after \(a.identifier)")
        }
        let first = try XCTUnwrap(areas.first)
        let id = first.identifier
        let value = swatch.value as? String
        let count = areas.count
        // By coordinate: neighbouring areas' frames can overlap at fit zoom, which fails an
        // element tap's hittability check; each frame is centred on its area's number.
        first.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        sleep(2)
        attachScreenshot(of: app, named: "paint-ax-after-tap")
        XCTAssertFalse(app.buttons[id].exists, "The tapped area is still unpainted")
        XCTAssertTrue(swatch.value as? String != value || query.count < count, "Tapping the area didn't paint it")
    }

    /// At the largest accessibility size the palette and the bar stay on screen and usable.
    @MainActor
    func testLargestTextKeepsPaletteUsable() throws {
        let app = launch(["-demo", "paint-ax-large"])
        attachScreenshot(of: app, named: "paint-ax-large")
        let window = app.windows.firstMatch.frame
        let swatches = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'swatch-'")).allElementsBoundByIndex
        let visible = swatches.filter { window.contains($0.frame) }
        XCTAssertFalse(visible.isEmpty, "No swatch is on screen")
        if UIDevice.current.userInterfaceIdiom == .pad {
            // Regular widths wrap the palette so every color stays on screen.
            XCTAssertEqual(visible.count, swatches.count)
        }
        for swatch in visible { XCTAssertTrue(swatch.isHittable, "\(swatch.identifier) can't be tapped") }
        // A phone's bar has no room for Hint at this size; the selected swatch still offers it.
        let controls = UIDevice.current.userInterfaceIdiom == .pad ? ["Close", "Hint", "Undo"] : ["Close", "Undo"]
        for name in controls {
            XCTAssertTrue(app.buttons[name].isHittable, "\(name) can't be tapped")
        }
        let other = try XCTUnwrap(visible.first { !$0.isSelected })
        other.tap()
        sleep(1)
        XCTAssertTrue(other.isSelected, "Tapping a swatch didn't select it")
    }

    /// The finished painting's bar keeps Done and Replay whole at accessibility sizes.
    @MainActor
    func testCompletionBarAtAccessibilitySize() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "paint-complete", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        let done = app.buttons["Done"], replay = app.buttons["Replay"]
        XCTAssertTrue(done.waitForExistence(timeout: 60))
        XCTAssertTrue(replay.waitForExistence(timeout: 10))
        sleep(2)
        attachScreenshot(of: app, named: "paint-complete-ax")
        let window = app.windows.firstMatch.frame
        for button in [done, replay] {
            XCTAssertTrue(button.isHittable, "\(button.label) can't be tapped")
            XCTAssertTrue(window.contains(button.frame), "\(button.label) is cut off")
        }
    }

    /// The system text size reaches the palette: swatches grow (1.4× at accessibility sizes).
    @MainActor
    func testPaintingSizeSettingsReachSwiftUI() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "paint-progress", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: 60))
        sleep(3)
        let swatches = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'swatch-'")).allElementsBoundByIndex
        XCTAssertFalse(swatches.isEmpty)
        for swatch in swatches {
            XCTAssertGreaterThanOrEqual(swatch.frame.width, 63, "\(swatch.identifier) didn't grow with the text size")
        }
    }

    @MainActor
    private func waitForDisappearance(of element: XCUIElement, timeout: TimeInterval = 10) -> Bool {
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        return XCTWaiter().wait(for: [gone], timeout: timeout) == .completed
    }

    @MainActor
    private func launch(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = arguments
        app.launch()
        XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: 60), "The painting didn't open")
        sleep(3)
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
