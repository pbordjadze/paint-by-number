import XCTest

#if UNRELEASED
/// Woodblock (painting-company row 375) played from a picture to Finished, as the frame every mode
/// shares asks of a mode before it ships (`ModeShell`, rule 10): New Print › The Library, the key
/// block carved and inked by strokes of a finger, then every step of every block (with
/// `-woodblock-steps`, the buttons VoiceOver has) until the print is finished. Each block's print
/// is attached, and the finished one.
final class WoodblockUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testAPrintFromAPictureToFinished() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "woodblock-empty", "-woodblock-steps"]
        app.launch()

        let new = app.buttons["woodblock-new"]
        XCTAssertTrue(new.waitForExistence(timeout: 60), "Woodblock's gallery has no New")
        new.tap()
        let library = app.buttons["The Library"]
        XCTAssertTrue(library.waitForExistence(timeout: 10), "New has no way into the library")
        library.tap()
        let picture = app.buttons.matching(identifier: "woodblock-library-picture").firstMatch
        XCTAssertTrue(picture.waitForExistence(timeout: 20), "The library shows no picture")
        picture.tap()

        let line = app.staticTexts["woodblock-instruction"]
        XCTAssertTrue(line.waitForExistence(timeout: 180), "The picture's blocks never reached the bench")
        attachScreenshot(of: app, named: "woodblock-play-bench")

        // The key block, carved and inked by a finger: strokes across the middle of the block.
        let window = app.windows.firstMatch
        func strokes(_ count: Int) {
            for i in 0..<count {
                let y = 0.36 + 0.28 * Double(i) / Double(max(1, count - 1))
                window.coordinate(withNormalizedOffset: CGVector(dx: 0.12, dy: y))
                    .press(forDuration: 0.05, thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.88, dy: y)),
                           withVelocity: .fast, thenHoldForDuration: 0.05)
            }
        }
        strokes(6)
        attachScreenshot(of: app, named: "woodblock-play-carved-by-hand")

        var prints = 0
        for _ in 0..<200 {
            if line.label == "Your print is finished." { break }
            if tapIfThere(app.buttons["woodblock-next"], timeout: 0.5) {
                prints += 1
                continue
            }
            if app.staticTexts.matching(NSPredicate(format: "label ENDSWITH %@", "printed.")).firstMatch.exists {
                attachScreenshot(of: app, named: "woodblock-play-print-\(prints + 1)")
            }
            if line.label.hasPrefix("Brush"), prints == 0 {
                strokes(4)
            }
            for id in ["woodblock-carve-it", "woodblock-ink-it", "woodblock-lay", "woodblock-rub-all", "woodblock-peel"] {
                if tapIfThere(app.buttons[id], timeout: 0.3) { break }
            }
            // A step's work (a peel, a block brought) takes a moment.
            _ = waitUntil(timeout: 2) { false }
        }
        XCTAssertEqual(line.label, "Your print is finished.", "The print never reached Finished")
        XCTAssertGreaterThan(prints, 0, "No block was printed before the last")
        attachScreenshot(of: app, named: "woodblock-play-finished")

        // Finished shows on the gallery's card.
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let card = app.buttons["woodblock-card"]
        XCTAssertTrue(card.waitForExistence(timeout: 20), "The gallery has no card for the print")
        XCTAssertTrue(waitUntil(timeout: 10) { card.value as? String == "Finished" }, "The card doesn't say Finished")
        attachScreenshot(of: app, named: "woodblock-play-gallery")
    }

    @MainActor
    private func tapIfThere(_ button: XCUIElement, timeout: TimeInterval) -> Bool {
        guard button.waitForExistence(timeout: timeout), button.isEnabled, button.isHittable else { return false }
        button.tap()
        return true
    }
}
#endif
