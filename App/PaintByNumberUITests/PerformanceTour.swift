import XCTest

/// The performance tour (painting-company row 292, Step 0): one pass through the app's moving
/// parts, the same every run, for Instruments and the app's `-tourLog` to measure on a device.
///
/// Segments, in order, each marked in the test's output as `TOURMARK <segment> begin|end <epoch s>`
/// (the device's clock, which the app's `tmp/tour-log-<pid>.tsv` shares):
/// forming (the create flow's picture, from launch to Start Painting ready), refine (open, one line,
/// Cancel and Discard), start (preview to painting), palette, zoom-pan, zen-30 (Zen Mode on, thirty
/// fills by tap and drag), transitions (back to the gallery and into the painting, twice).
///
/// Run it alone on a device: `-only-testing:PaintByNumberUITests/PerformanceTour` with `TEST_RUNNER_TOUR=1`
/// (without `TOUR` it skips, so CI's UI test runs, which take every class, don't spend minutes on it).
@MainActor
final class PerformanceTour: XCTestCase {
    private var marks: [String] = []

    override func setUp() async throws {
        continueAfterFailure = true
        XCUIDevice.shared.orientation = .portrait
    }

    /// Seconds of rest before each segment (`TOUR_GAP`, default 0), marked `pre`: time for a Mac
    /// script watching the test's output to start (and an earlier one to finish) an Instruments
    /// recording of that segment alone.
    private let gap = UInt32(ProcessInfo.processInfo.environment["TOUR_GAP"] ?? "") ?? 0

    private func segment(_ name: String, _ body: () -> Void) {
        if gap > 0 { mark(name, "pre"); sleep(gap) }
        mark(name, "begin")
        body()
        mark(name, "end")
    }

    private func mark(_ name: String, _ edge: String) {
        let line = String(format: "TOURMARK %@ %@ %.4f", name, edge, Date().timeIntervalSince1970)
        print(line)
        marks.append(line)
    }

    func testTour() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["TOUR"] != nil, "The tour runs only when asked for (TOUR)")
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "create-preview", "-demoFixedPictures", "YES", "-tourLog", "YES"]
        let start = app.buttons["Start Painting"]

        segment("forming") {
            app.launch()
            XCTAssertTrue(start.waitForExistence(timeout: 60))
            XCTAssertTrue(waitFor(start, toMatch: NSPredicate(format: "isEnabled == true"), timeout: 180))
            XCTAssertTrue(waitFor(app.buttons["refine"], toMatch: NSPredicate(format: "isEnabled == true"), timeout: 180))
            XCTAssertTrue(waitForSuggestion(in: app))
        }
        sleep(3)

        segment("refine") {
            app.buttons["refine"].tap()
            let canvas = app.descendants(matching: .any)["refine-canvas"]
            XCTAssertTrue(canvas.waitForExistence(timeout: 120), "Refine didn't open")
            sleep(3)
            canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.4))
                .press(forDuration: 0.05, thenDragTo: canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.45)))
            sleep(1)
            app.buttons["refine-cancel"].tap()
            let discard = app.buttons["Discard Changes"]
            if discard.waitForExistence(timeout: 5) { discard.tap() }
            XCTAssertTrue(waitFor(start, toMatch: NSPredicate(format: "isEnabled == true"), timeout: 180))
        }
        sleep(3)

        // The progress badge, or the quiet bar's ring (a button) once the bar has faded.
        let badge = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label ENDSWITH 'percent painted' AND NOT (identifier BEGINSWITH 'swatch-')")).firstMatch
        segment("start") {
            start.tap()
            XCTAssertTrue(badge.waitForExistence(timeout: 90), "The painting didn't open")
            // The bar stays hidden (not hittable) until the page is touched, so the segment ends
            // when the painting screen exists.
            XCTAssertTrue(app.buttons["Back"].waitForExistence(timeout: 15))
        }
        sleep(3)
        attachScreenshot(of: app, named: "tour-painting")

        segment("palette") {
            let swatches = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'swatch-'"))
            for n in [2, 3, 4, 5, 1] {
                let swatch = app.buttons["swatch-\(n)"]
                if swatch.exists && swatch.isHittable { swatch.tap() }
                sleep(1)
            }
            if let last = swatches.allElementsBoundByIndex.last, last.exists {
                last.swipeLeft(); sleep(1); last.swipeRight(); sleep(1)
            }
            let first = app.buttons["swatch-1"]
            if first.exists && first.isHittable { first.tap() }
        }
        sleep(2)

        let window = app.windows.firstMatch
        segment("zoom-pan") {
            for _ in 0..<3 {
                window.pinch(withScale: 2.5, velocity: 2)
                window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45))
                    .press(forDuration: 0.05, thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.35)))
                window.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.35))
                    .press(forDuration: 0.05, thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.55)))
                window.pinch(withScale: 0.4, velocity: -2)
                sleep(1)
            }
        }
        sleep(2)

        segment("zen-30") {
            // The quiet bar hides More; its ring brings the rest of the bar back.
            let ring = app.buttons["quiet-ring"]
            if ring.exists && ring.isHittable { ring.tap(); sleep(1) }
            app.buttons["More"].tap()
            let zen = app.buttons["Zen Mode"].firstMatch
            XCTAssertTrue(zen.waitForExistence(timeout: 5), "More has no Zen Mode")
            zen.tap()
            // Zen Mode is a saved setting, so the toggle may have just turned it off: the "Zen Mode is
            // on" toast says it's on; without it, toggle again.
            let on = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Zen Mode is on'")).firstMatch
            var zenOn = on.waitForExistence(timeout: 3)
            if !zenOn {
                if ring.exists && ring.isHittable { ring.tap(); sleep(1) }
                app.buttons["More"].tap()
                if zen.waitForExistence(timeout: 5) { zen.tap() }
                zenOn = on.waitForExistence(timeout: 3)
            }
            XCTAssertTrue(zenOn, "Zen Mode didn't turn on")
            print("TOURNOTE zen on=\(zenOn)")
            sleep(3)
            var fills = 0, tries = 0
            let areas = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'canvas-area-'"))
            while fills < 30 && tries < 60 {
                tries += 1
                let area = areas.firstMatch
                guard area.waitForExistence(timeout: 5) else {
                    if app.buttons["Hint"].exists { app.buttons["Hint"].tap() }
                    sleep(1)
                    continue
                }
                let at = app.coordinate(withNormalizedOffset: .zero)
                    .withOffset(CGVector(dx: area.frame.midX, dy: area.frame.midY))
                if fills % 2 == 0 {
                    at.tap()
                } else {
                    at.press(forDuration: 0.05, thenDragTo: at.withOffset(CGVector(dx: 6, dy: 4)))
                }
                fills += 1
                sleep(1) // Zen Mode's flight to the next area
            }
            attachNote("fills \(fills) in \(tries) tries; \(badge.label)", named: "zen-fills")
            print("TOURNOTE zen fills=\(fills) tries=\(tries) badge=\(badge.label)")
        }
        sleep(2)
        attachScreenshot(of: app, named: "tour-after-zen")

        segment("transitions") {
            for _ in 0..<2 {
                app.buttons["Back"].tap()
                XCTAssertTrue(app.buttons["Paint"].waitForExistence(timeout: 10), "Back didn't return to the gallery")
                sleep(2)
                // The new painting's card, named by its title (`-demoFixedPictures`: The Great Wave).
                let card = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'The Great Wave'")).firstMatch
                XCTAssertTrue(card.waitForExistence(timeout: 15), "The painting has no card")
                card.tap()
                XCTAssertTrue(waitUntil(timeout: 30) { app.buttons["Back"].exists && app.buttons["Back"].isHittable },
                              "The painting didn't reopen")
                sleep(2)
            }
        }
        attachNote(marks.joined(separator: "\n"), named: "tour-marks")
        XCTAssertEqual(app.state, .runningForeground)
    }
}
