import XCTest

/// Start Painting hands the create flow over to the painting in one motion (`StartHandoff`): the
/// painting opens under the flow's cover, which dissolves into it, and the way back is the zoom to
/// the new card. With the making-of off, the preview's picture moves to the painting; with it on,
/// the preview's picture becomes the show's, and the show's last frame moves to the painting.
///
/// Each test attaches a burst of screenshots of the whole screen (`XCUIScreen`, one after the other
/// as fast as they come) across the hand-off, for the motion to be judged by eye. The `Slowed`
/// tests run the same journey with every duration of the hand-off five times as long
/// (`-handoffSlowdown 5`), so that a burst catches more of the motion.
final class StartHandoffUITests: XCTestCase {
    /// The painting the `create-preview` demo makes with the fixed pictures.
    private let title = "The Great Wave"

    @MainActor
    func testStartOpensThePaintingAndBackReturnsToItsCard() throws {
        let app = launchPreview()
        let start = waitForStart(in: app)
        start.tap()
        burst(named: "start-making-of-off", count: 8)

        expectPainting(in: app)
        returnToGallery(from: app, byEdgeSwipe: false)
    }

    @MainActor
    func testSkippingTheShowOpensThePaintingAndBackReturnsToItsCard() throws {
        let app = launchPreview(makingOf: true)
        let start = waitForStart(in: app)
        start.tap()
        // The preview's picture becomes the show's, and the show begins.
        burst(named: "start-making-of-on", count: 6)

        skipTheShow(in: app, burstNamed: "skip-making-of-on", count: 8)
        expectPainting(in: app)
        returnToGallery(from: app, byEdgeSwipe: true)
    }

    @MainActor
    func testSlowedStartWithoutTheShow() throws {
        let app = launchPreview(slowdown: 5)
        let start = waitForStart(in: app)
        start.tap()
        burst(named: "slowed-start-making-of-off", count: 12)

        expectPainting(in: app)
    }

    @MainActor
    func testSlowedStartAndSkipWithTheShow() throws {
        let app = launchPreview(makingOf: true, slowdown: 5)
        let start = waitForStart(in: app)
        start.tap()
        burst(named: "slowed-start-making-of-on", count: 10)

        skipTheShow(in: app, burstNamed: "slowed-skip-making-of-on", count: 12)
        expectPainting(in: app)
    }

    // MARK: - Steps

    /// The create flow on the first fixed picture's preview, with the show on or off.
    @MainActor
    private func launchPreview(makingOf: Bool = false, slowdown: Int? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        var arguments = ["-demo", "create-preview", "-demoFixedPictures", "YES"]
        if makingOf { arguments += ["-playsMakingOf", "YES"] }
        if let slowdown { arguments += ["-handoffSlowdown", String(slowdown)] }
        app.launchArguments = arguments
        app.launch()
        return app
    }

    /// Start Painting, once the template is ready to start from.
    @MainActor
    private func waitForStart(in app: XCUIApplication) -> XCUIElement {
        let start = app.buttons["Start Painting"]
        XCTAssertTrue(start.waitForExistence(timeout: 30), "The preview has no Start Painting")
        expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: start)
        waitForExpectations(timeout: 90)
        return start
    }

    /// Waits for the show to play, then skips it, with a burst of screenshots right after the tap.
    @MainActor
    private func skipTheShow(in app: XCUIApplication, burstNamed name: String, count: Int) {
        let skip = app.buttons["making-of-skip"]
        XCTAssertTrue(skip.waitForExistence(timeout: 60), "Start didn't open the making-of")
        let card = app.descendants(matching: .any)["making-of-card"]
        XCTAssertTrue(card.waitForExistence(timeout: 120), "The making-of never showed a step's card")
        attachScreenshot(of: app, named: "making-of-playing")

        // The show is about 17 s, and while it animates every query waits on it: on a slow runner it
        // can end on its own, which opens the painting too, between finding Skip and tapping it.
        let showMayEnd = XCTExpectedFailure.Options()
        showMayEnd.isStrict = false
        XCTExpectFailure("The show ended on its own before Skip was tapped", options: showMayEnd) {
            skip.tap()
        }
        burst(named: name, count: count)
    }

    /// The painting is open, and the create flow is gone from the screen.
    @MainActor
    private func expectPainting(in app: XCUIApplication) {
        let badge = app.staticTexts["\(title), 0 percent painted"]
        XCTAssertTrue(badge.waitForExistence(timeout: 90), "Start didn't open the painting")
        XCTAssertTrue(
            app.buttons["Start Painting"].waitForNonExistence(timeout: 30), "The create flow stayed on screen")
        XCTAssertFalse(app.buttons["making-of-skip"].exists, "The making-of stayed on screen")
        attachScreenshot(of: app, named: "painting-opened")
    }

    /// Back to the gallery, where the new painting's card is.
    @MainActor
    private func returnToGallery(from app: XCUIApplication, byEdgeSwipe: Bool) {
        if byEdgeSwipe {
            let window = app.windows.firstMatch
            window.coordinate(withNormalizedOffset: CGVector(dx: 0.005, dy: 0.5))
                .press(forDuration: 0.05, thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)))
        } else {
            app.buttons["Close"].tap()
        }
        let returned = app.buttons["New Painting"].waitForExistence(timeout: 15)
        attachScreenshot(of: app, named: "back-in-gallery")
        XCTAssertTrue(returned, "Going back didn't return to the gallery")
        XCTAssertTrue(app.buttons[title].firstMatch.waitForExistence(timeout: 15), "The new painting has no card")
        XCTAssertFalse(app.buttons["Start Painting"].exists, "The create flow came back")
    }

    /// `count` screenshots of the whole screen, one after the other as fast as they come, attached
    /// in order with the second each was taken at (counted from the first).
    @MainActor
    private func burst(named name: String, count: Int) {
        let began = Date()
        var shots: [(XCUIScreenshot, TimeInterval)] = []
        for _ in 0..<count {
            let shot = XCUIScreen.main.screenshot()
            shots.append((shot, Date().timeIntervalSince(began)))
        }
        for (index, entry) in shots.enumerated() {
            attach(entry.0, named: "\(name)-\(String(format: "%02d", index + 1))")
        }
        let times = shots.map { String(format: "%.2f", $0.1) }.joined(separator: " ")
        attachNote("seconds since the first: \(times)", named: "\(name)-times")
    }
}
