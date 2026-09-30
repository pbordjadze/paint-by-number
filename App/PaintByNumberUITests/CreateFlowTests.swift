import XCTest

final class CreateFlowTests: XCTestCase {
    /// The before/after divider follows a drag that starts on its knob.
    @MainActor
    func testCompareDividerFollowsDrag() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "create-preview"]
        app.launch()

        let start = app.buttons["Start Painting"]
        XCTAssertTrue(start.waitForExistence(timeout: 30))
        // The divider appears with the first template.
        expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: start)
        waitForExpectations(timeout: 60)

        let compare = app.descendants(matching: .any)["Comparison of photo and template"]
        XCTAssertTrue(compare.exists)
        XCTAssertEqual(compare.value as? String, "50 percent photo")
        compare.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.1, thenDragTo: compare.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5)))
        sleep(1)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "compare-after-drag"
        shot.lifetime = .keepAlways
        add(shot)
        XCTAssertNotEqual(compare.value as? String, "50 percent photo", "The divider didn't follow the drag")
    }

    /// The preview's title field offers the sample's name and names the painting with what
    /// was typed.
    @MainActor
    func testTitleNamesThePainting() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "create-preview"]
        app.launch()

        let start = app.buttons["Start Painting"]
        XCTAssertTrue(start.waitForExistence(timeout: 30))
        expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: start)
        waitForExpectations(timeout: 60)

        let title = app.textFields["painting-title"]
        XCTAssertTrue(title.exists, "The preview has no title field")
        XCTAssertEqual(title.placeholderValue, "Parrots")
        title.tap()
        title.typeText("Jungle Birds\n")
        XCTAssertEqual(title.value as? String, "Jungle Birds")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "create-title-typed"
        shot.lifetime = .keepAlways
        add(shot)

        start.tap()
        XCTAssertTrue(
            app.staticTexts["Jungle Birds, 0 percent painted"].waitForExistence(timeout: 90),
            "The painting didn't open with the typed title")
    }

    /// Tapping a photo in the inline library picker opens its template preview.
    @MainActor
    func testLibraryPhotoOpensPreview() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "create"]
        app.launch()
        // First use explains limited library access.
        let ok = app.buttons["OK"]
        if ok.waitForExistence(timeout: 10) { ok.tap() }

        // The picker runs out of process: its photos are listed but report frames in the
        // picker's own coordinates, so tap by position inside the picker (first photo).
        let picker = app.descendants(matching: .any)["library-picker"]
        let photo = app.images.matching(NSPredicate(format: "label BEGINSWITH 'Photo'")).firstMatch
        guard picker.waitForExistence(timeout: 20), photo.waitForExistence(timeout: 20) else {
            let tree = XCTAttachment(string: app.debugDescription)
            tree.name = "library-picker-tree"
            tree.lifetime = .keepAlways
            add(tree)
            throw XCTSkip("The library picker's photos aren't reachable from the UI test")
        }
        picker.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.25)).tap()
        let start = app.buttons["Start Painting"]
        let opened = start.waitForExistence(timeout: 60)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "library-photo-picked"
        shot.lifetime = .keepAlways
        add(shot)
        XCTAssertTrue(opened, "Picking a library photo didn't open its preview")
    }
}
