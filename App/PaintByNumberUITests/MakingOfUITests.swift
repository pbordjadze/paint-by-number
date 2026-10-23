import XCTest

/// The making-of show (Settings › The Making-of, on through `-playsMakingOf YES`): Start Painting
/// plays it over the create flow, and Skip opens the painting Start saved.
final class MakingOfUITests: XCTestCase {
    @MainActor
    func testStartPlaysTheShowAndSkipOpensThePainting() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "create-preview", "-demoFixedPictures", "YES", "-playsMakingOf", "YES"]
        app.launch()

        let start = app.buttons["Start Painting"]
        XCTAssertTrue(start.waitForExistence(timeout: 30))
        expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: start)
        waitForExpectations(timeout: 90)
        XCTAssertTrue(waitForSuggestion(in: app), "The preview never chose its settings")
        start.tap()

        let skip = app.buttons["making-of-skip"]
        XCTAssertTrue(skip.waitForExistence(timeout: 60), "Start didn't open the making-of")
        // A card shows once the show is made and playing (the photo shows meanwhile).
        let card = app.descendants(matching: .any)["making-of-card"]
        let played = card.waitForExistence(timeout: 120)
        attachScreenshot(of: app, named: "making-of-playing")
        XCTAssertTrue(played, "The making-of never showed a step's card")

        // The show is about 17 s, and while it animates every query waits on it: on a slow runner it
        // can end on its own, which opens the painting too, between finding Skip and tapping it.
        let showMayEnd = XCTExpectedFailure.Options()
        showMayEnd.isStrict = false
        XCTExpectFailure("The show ended on its own before Skip was tapped", options: showMayEnd) {
            skip.tap()
        }
        XCTAssertTrue(
            app.staticTexts["The Great Wave, 0 percent painted"].waitForExistence(timeout: 60),
            "Skipping the making-of didn't open the painting")
    }
}
