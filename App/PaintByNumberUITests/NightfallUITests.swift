import XCTest

/// The two small animations Paul asked to see (October 18, 2026), in SideStore and Debug builds:
/// night falling over a painting just finished (`Nightfall`) and the empty gallery's sketch
/// painting itself (`SelfPaintingSketch`). Each is stretched with `-introSlowdown` so CI's slow
/// screenshots catch its steps, and its frames are attached (`ScreenFrames.swift`) for a look.
final class NightfallUITests: XCTestCase {
    @MainActor
    func testNightFallsOverTheFinishedPainting() throws {
        let app = XCUIApplication()
        // Three times slower: the last fill, the flight out, the shine and about ten seconds of night.
        app.launchArguments = ["-demo", "paint-nightfall", "-introSlowdown", "3"]
        app.launch()

        XCTAssertTrue(app.staticTexts["Finished!"].waitForExistence(timeout: 120), "The painting never finished")
        let frames = captureFrames(timeout: 20, keep: 80) { _ in false }
        attachFrames(frames, named: "nightfall")
        XCTAssertGreaterThan(largestChange(in: frames), ScreenChanges.still, "Nothing moved after the painting finished")
    }

    @MainActor
    func testTheEmptyGallerysSketchPaintsItself() throws {
        let app = XCUIApplication()
        // Four times slower: about nine seconds. The sketch waits for a tap, or a simulator slow to
        // answer could let it finish before the first frame (CI, October 23: twice in one run).
        app.launchArguments = ["-demo", "gallery-empty", "-introSlowdown", "4", "-introWaitsForTap", "YES"]
        app.launch()

        let title = app.staticTexts["Every painting starts with a photo"]
        XCTAssertTrue(title.waitForExistence(timeout: 60))
        let unpainted = ScreenFrame(since: .now)
        // The sketch is hidden from VoiceOver: it is tapped where it stands, 198 pt high and 34 pt
        // above the title (`EmptyGalleryView`).
        let sketch = CGVector(dx: title.frame.midX, dy: title.frame.minY - 34 - 198 / 2)
        app.coordinate(withNormalizedOffset: .zero).withOffset(sketch).tap()
        let frames = [unpainted] + captureFrames(timeout: 12, keep: 60) { _ in false }
        attachFrames(frames, named: "empty-gallery-sketch")
        XCTAssertGreaterThan(largestChange(in: frames), ScreenChanges.still, "The sketch didn't paint itself")
    }

    /// How far the screen got from its first frame: the sketch is a small part of the screen, so
    /// no step from one frame to the next need count as a move.
    @MainActor
    private func largestChange(in frames: [ScreenFrame]) -> Double {
        guard let first = frames.first else { return 0 }
        return frames.map { $0.difference(from: first) }.max() ?? 0
    }
}
