import XCTest

/// The bench's first tip: the first painting says how to paint, and the tip goes away for good once
/// dismissed or once an area is filled. (`paint-tip` and `paint-tip-fill` are among the few launches
/// that show tips; each starts from an empty TipKit datastore and tips turned on.)
final class PaintingTipsTests: XCTestCase {
    @MainActor
    func testFirstTipAppearsAndDismisses() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "paint-tip"]
        app.launch()

        let tip = app.staticTexts["Tap to Paint"]
        XCTAssertTrue(tip.waitForExistence(timeout: 90), "The first tip didn't appear")
        XCTAssertTrue(
            app.staticTexts["Pick a color, then tap an area marked with its number to fill it."].exists,
            "The first tip doesn't say what to do")
        attachScreenshot(of: app, named: "first-tip")
        // It asks for a color: it covers none (QA, November 7: on iPad it hid a line of swatches).
        let message = app.staticTexts["Pick a color, then tap an area marked with its number to fill it."]
        XCTAssertTrue(waitUntil(timeout: 5) { tip.isHittable }, "The tip isn't settled on screen")
        let words = tip.frame.union(message.frame)
        let swatches = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'swatch-'")).allElementsBoundByIndex
        let covered = swatches.filter { $0.frame.intersects(words) }
        XCTAssertTrue(covered.isEmpty, "The tip covers \(covered.map(\.identifier))")

        // Outside the popover, which sits over the canvas above the palette at the bottom.
        app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)).tap()
        XCTAssertTrue(tip.waitForNonExistence(timeout: 10), "Tapping outside didn't dismiss the tip")
        sleep(2)
        XCTAssertFalse(tip.exists, "The dismissed tip came back")
    }

    /// The tap the tip asks for paints: a popover took a newcomer's first tap on an area to close
    /// itself and painted nothing (QA, November 6). The play harness names every area with its paint.
    @MainActor
    func testTheTapTheTipAsksForPaints() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "paint-tip", "-playHarness"]
        app.launch()

        let tip = app.staticTexts["Tap to Paint"]
        XCTAssertTrue(tip.waitForExistence(timeout: 90), "The first tip didn't appear")
        sleep(1)
        func all(_ element: any XCUIElementSnapshot) -> [any XCUIElementSnapshot] {
            [element] + element.children.flatMap(all)
        }
        let elements = try all(app.snapshot())
        let swatches = elements.filter { $0.identifier.hasPrefix("swatch-") }
        let selected = try XCTUnwrap(swatches.first { $0.isSelected }, "No color is selected")
        let paint = String(selected.identifier.dropFirst("swatch-".count))
        // The tip's popover, which a tap on it would not pass on, and the bars stay clear.
        let popover = elements.filter { $0.elementType == .popover }.map(\.frame).first ?? .null
        let top = app.buttons["Back"].frame.maxY + 24
        let bottom = (swatches.map { $0.frame.minY }.min() ?? app.frame.maxY) - 40
        let canvas = try XCTUnwrap(elements.first { $0.identifier == "canvas" }?.frame, "The canvas has no frame")
        let point = try XCTUnwrap(
            elements.filter { $0.identifier.hasPrefix("area-") && ($0.value as? String) == paint }
                .map { CGPoint(x: $0.frame.midX, y: $0.frame.midY) }
                .first { canvas.insetBy(dx: 24, dy: 0).contains($0) && $0.y > top && $0.y < bottom && !popover.insetBy(dx: -24, dy: -24).contains($0) },
            "No area of paint \(paint) on screen")
        let state = app.descendants(matching: .any)["play-state"]
        func filledAreas() -> Int {
            guard let text = state.value as? String, let object = try? JSONSerialization.jsonObject(with: Data(text.utf8)),
                  let filled = (object as? [String: Any])?["filled_areas"] as? [Any] else { return -1 }
            return filled.count
        }
        let before = filledAreas()
        XCTAssertGreaterThanOrEqual(before, 0, "The play harness has no state")
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: point.x, dy: point.y)).tap()
        XCTAssertTrue(waitUntil(timeout: 10) { filledAreas() > before }, "The tap under the tip painted nothing")
        XCTAssertTrue(tip.waitForNonExistence(timeout: 10), "The tip stayed up after the tap")
        attachScreenshot(of: app, named: "first-tip-tap-painted")
    }

    /// A Calmer Way to Paint hangs from More: one tap on More opens its menu, the tip closing as it
    /// does. The tap closed only the tip, the menu opening and closing again unseen as the tip's
    /// popover went (QA, November 7).
    @MainActor
    func testOneTapOnMoreOpensItsMenuUnderTheTip() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "paint--tip-benchZen"]
        app.launch()

        let tip = app.staticTexts["A Calmer Way to Paint"]
        XCTAssertTrue(tip.waitForExistence(timeout: 90), "The tip about Zen Mode didn't appear")
        XCTAssertTrue(waitUntil(timeout: 5) { tip.isHittable }, "The tip isn't settled on screen")
        app.buttons["More"].tap()
        let restart = app.buttons["Restart"]
        XCTAssertTrue(restart.waitForExistence(timeout: 5), "One tap on More didn't open its menu")
        // Still open once the tip's popover has gone.
        XCTAssertTrue(tip.waitForNonExistence(timeout: 5), "The tip stayed up over the menu")
        sleep(1)
        attachScreenshot(of: app, named: "more-under-the-zen-tip")
        XCTAssertTrue(restart.exists, "More's menu closed with the tip")
        XCTAssertEqual(app.keyboards.count, 0, "A keyboard rose with More's menu (main's iPhone run, November 9)")
    }

    /// Filling an area is using what the tip is about: the tip closes by itself and stays closed.
    @MainActor
    func testFirstTipClosesAfterAFill() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "paint-tip-fill"]
        app.launch()

        let tip = app.staticTexts["Tap to Paint"]
        XCTAssertTrue(tip.waitForExistence(timeout: 90), "The first tip didn't appear")
        attachScreenshot(of: app, named: "first-tip-before-fill")
        // The scenario fills an area once the tip is up.
        XCTAssertTrue(tip.waitForNonExistence(timeout: 30), "A fill didn't close the tip")
        attachScreenshot(of: app, named: "first-tip-after-fill")
        sleep(2)
        XCTAssertFalse(tip.exists, "The tip came back after the fill")
    }
}
