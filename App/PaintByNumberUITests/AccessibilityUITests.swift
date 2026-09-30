import UIKit
import XCTest

/// What VoiceOver reads on the painting screen, and the screen at the largest text sizes.
final class AccessibilityUITests: XCTestCase {
    /// Swatches say their number and color name ("12, dark green") and how far they are painted;
    /// the selected color's name is on screen for people who can't tell the paints apart.
    @MainActor
    func testSwatchesSpeakNumberAndColorName() throws {
        let app = launch(["-demo", "paint-ax"])
        let swatches = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'swatch-'")).allElementsBoundByIndex
        XCTAssertFalse(swatches.isEmpty)
        for swatch in swatches {
            let label = swatch.label
            XCTAssertNotNil(label.range(of: #"^[0-9]+, [a-z]+( [a-z]+){0,3}$"#, options: .regularExpression), label)
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
        first.tap()
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
        for name in ["Close", "Hint", "Undo"] {
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
