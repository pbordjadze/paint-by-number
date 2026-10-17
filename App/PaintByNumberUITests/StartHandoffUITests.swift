import XCTest

/// Start Painting hands the create flow over to the painting in one motion (`StartHandoff`): the
/// painting opens under the flow's cover, which dissolves into it, and the way back is the zoom to
/// the new card. With the making-of off, the preview's picture moves to the painting; with it on,
/// the preview's picture becomes the show's, and the show's picture moves to the painting.
///
/// The tests that look at the motion attach the frames of the screen around the change (see
/// `ScreenFrames.swift`; the attachments are named after the step, then numbered). A screenshot
/// takes half a second or more on CI's simulators, whose main thread also stalls for seconds while
/// a painting opens, so a motion of under half a second is a frame or two at best: the `Slowed`
/// tests run the journey with every duration five times as long (`-handoffSlowdown 5`). Every test
/// gives the painting longer than the 2.5 s the app does to draw its first frame
/// (`-handoffFallback`), as CI's simulators take several, so that the hand-off, and not its
/// fallback, is what is seen; `testAPaintingThatNeverDrawsStillOpens` takes the fallback.
final class StartHandoffUITests: XCTestCase {
    /// The painting the `create-preview` demo makes with the fixed pictures.
    private let title = "The Great Wave"

    override func setUp() {
        super.setUp()
        // A show that ends on its own while Skip is being tapped is an expected failure (below);
        // what the test checks after it still counts.
        continueAfterFailure = true
    }

    @MainActor
    func testStartOpensThePaintingAndBackReturnsToItsCard() throws {
        let app = launchPreview()
        waitForStart(in: app).tap()
        let frames = captureHandoff(in: app)
        attachFrames(frames, named: "start-making-of-off")

        expectPainting(in: app)
        returnToGallery(from: app, byEdgeSwipe: false)
    }

    @MainActor
    func testSkippingTheShowOpensThePaintingAndBackReturnsToItsCard() throws {
        let app = launchPreview(makingOf: true)
        waitForStart(in: app).tap()
        attachFrames(captureEntry(after: 5), named: "start-making-of-on")

        // Skip at once: tapping while the show animates waits for the app to be idle, which on CI's
        // simulators it is not before the show has ended on its own (which opens the painting too,
        // between finding Skip and tapping it).
        let skip = app.buttons["making-of-skip"]
        XCTAssertTrue(skip.waitForExistence(timeout: 60), "Start didn't open the making-of")
        let showMayEnd = XCTExpectedFailure.Options()
        showMayEnd.isStrict = false
        XCTExpectFailure("The show ended on its own before Skip was tapped", options: showMayEnd) {
            skip.tap()
        }
        attachFrames(captureHandoff(in: app), named: "skip-making-of-on")

        expectPainting(in: app)
        returnToGallery(from: app, byEdgeSwipe: true)
    }

    @MainActor
    func testSlowedStartWithoutTheShow() throws {
        let app = launchPreview(slowdown: 5)
        waitForStart(in: app).tap()
        attachFrames(captureHandoff(in: app), named: "slowed-start-making-of-off")

        expectPainting(in: app)
    }

    /// The preview's picture becomes the show's, and the show's goes to the painting when it ends.
    @MainActor
    func testSlowedStartAndTheShowsEndWithTheShow() throws {
        let app = launchPreview(makingOf: true, slowdown: 5)
        waitForStart(in: app).tap()
        attachFrames(captureEntry(), named: "slowed-start-making-of-on")

        let card = app.descendants(matching: .any)["making-of-card"]
        XCTAssertTrue(card.waitForExistence(timeout: 120), "The making-of never showed a step's card")
        attachScreenshot(of: app, named: "making-of-playing")
        // The show is about 17 s: its end hands over to the painting. No tap: the app is never idle
        // while it plays, and the frames are taken meanwhile.
        attachFrames(captureHandoff(in: app, timeout: 180, keep: 60), named: "slowed-end-making-of-on")

        expectPainting(in: app)
    }

    /// A painting that hasn't drawn when the cover has waited for it (0.1 s here) still opens: the
    /// cover fades out alone and the painting stays where it was pushed, under it.
    @MainActor
    func testAPaintingThatNeverDrawsStillOpens() throws {
        let app = launchPreview(fallback: 0.1)
        waitForStart(in: app).tap()

        expectPainting(in: app)
        returnToGallery(from: app, byEdgeSwipe: false)
    }

    // MARK: - Steps

    /// The create flow on the first fixed picture's preview, with the show on or off.
    @MainActor
    private func launchPreview(
        makingOf: Bool = false, slowdown: Int? = nil, fallback: Double = 30
    ) -> XCUIApplication {
        let app = XCUIApplication()
        var arguments = ["-demo", "create-preview", "-demoFixedPictures", "YES", "-handoffFallback", String(fallback)]
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

    /// The frames from the preview to the show's first moments: those from just before the screen
    /// first changes (the preview's picture moving to the show's place, the show coming in) to
    /// `count` after.
    @MainActor
    private func captureEntry(after count: Int = 12) -> [ScreenFrame] {
        let frames = captureFrames(timeout: 90, keep: 80) { changes in
            guard let first = changes.first else { return false }
            return changes.frames.count - first >= count
        }
        let changes = ScreenChanges(frames: frames)
        let first = changes.first ?? max(frames.count - count, 1)
        return Array(frames[max(first - 1, 0)..<min(first + count, frames.count)])
    }

    /// The frames of the hand-off to the painting: the screen changes (the picture moving to the
    /// painting, the flow fading to it) and then holds still, with the painting in the place of the
    /// flow. Those from ten frames before the last change to one after it.
    @MainActor
    private func captureHandoff(in app: XCUIApplication, timeout: TimeInterval = 120, keep: Int = 40) -> [ScreenFrame] {
        let frames = captureFrames(timeout: timeout, keep: keep) { changes in
            // Holding still is not enough: the show's last frame holds while the painting opens.
            guard changes.first != nil, changes.holdsStill(for: 4) else { return false }
            return !app.buttons["Start Painting"].exists && !app.buttons["making-of-skip"].exists
        }
        let changes = ScreenChanges(frames: frames)
        guard let last = changes.last else { return Array(frames.suffix(8)) }
        return Array(frames[max(last - 9, 0)..<min(last + 2, frames.count)])
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
}
