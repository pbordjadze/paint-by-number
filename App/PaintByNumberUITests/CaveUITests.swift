import XCTest

/// The Cave (painting-company rows 371 and 379) in the frame every mode shares: a library picture
/// drawn on the rock from the + menu, its painting screen pushed, painted to Finished (the
/// frame's rule 10: every mode played to the end before it ships), and its card saying so.
final class CaveUITests: XCTestCase {
    #if UNRELEASED
    /// The whole way, from the empty cave's mouth to a finished painting's card. The blowing is
    /// the scene's own (`-caveAutoPaint`: area by area, then the hand, as VoiceOver's actions do),
    /// since a drag can't hold a finger on the rock for each area; the frames are attached.
    @MainActor
    func testALibraryPicturePaintsToFinished() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "cave-mouth", "-caveAutoPaint", "YES"]
        app.launch()
        let new = app.buttons["cave-new"]
        XCTAssertTrue(new.waitForExistence(timeout: 60), "The Cave has no + menu")
        attachScreenshot(of: app, named: "cave-1-mouth")
        new.tap()
        let library = app.buttons["The Library"]
        XCTAssertTrue(library.waitForExistence(timeout: 10), "The + menu has no Library")
        library.tap()
        let picture = app.buttons["cave-library-picture"].firstMatch
        XCTAssertTrue(picture.waitForExistence(timeout: 30), "The Library shows no pictures")
        picture.tap()
        let wall = app.descendants(matching: .any)["cave-painting"]
        XCTAssertTrue(wall.waitForExistence(timeout: 120), "The picture's painting screen didn't open")
        attachScreenshot(of: app, named: "cave-2-drawn")
        var frame = 3
        let start = Date()
        while wall.value as? String != "Finished" && Date().timeIntervalSince(start) < 180 {
            sleep(6)
            attachScreenshot(of: app, named: "cave-\(frame)-blowing")
            frame += 1
        }
        XCTAssertEqual(wall.value as? String, "Finished", "The painting never reached Finished")
        app.navigationBars.firstMatch.buttons.element(boundBy: 0).tap()
        let card = app.buttons["cave-card"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 20), "The gallery shows no card")
        XCTAssertEqual(card.value as? String, "Finished", "The card doesn't say the painting is finished")
        sleep(3)
        attachScreenshot(of: app, named: "cave-\(frame)-gallery")
    }
    #endif
}
