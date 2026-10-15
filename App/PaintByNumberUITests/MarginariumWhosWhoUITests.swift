import XCTest

/// The contents page opens on the drawings: a tap makes one wave and shows its name, which opens its
/// brief. Who's Who opens from the contents, and a guardian's card opens its brief too, which stays
/// readable at the largest text sizes.
final class MarginariumWhosWhoUITests: XCTestCase {
    @MainActor
    func testADrawingShowsItsNameWhichOpensItsBrief() {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "marginarium"]
        app.launch()
        let page = app.scrollViews["marginarium-contents"]
        let pip = app.buttons["marginarium-drawing-pip"]
        XCTAssertTrue(pip.waitForExistence(timeout: 15))
        XCTAssertTrue(waitUntil { pip.isHittable })
        XCTAssertEqual(pip.label, "Pip, Codex's teapot")
        let dino = app.buttons["marginarium-drawing-dinotopia"]
        for _ in 0..<8 {
            if dino.exists && dino.isHittable { break }
            page.swipeUp()
        }
        XCTAssertTrue(dino.isHittable)
        XCTAssertEqual(dino.label, "Dino")
        dino.tap()
        let name = app.buttons["marginarium-name-dinotopia"]
        XCTAssertTrue(name.waitForExistence(timeout: 5), "Tapping Dino didn't show its name")
        XCTAssertTrue(name.label.contains("Dino"), name.label)
        attachScreenshot(of: app, named: "marginarium-drawing-named")
        name.tap()
        XCTAssertTrue(app.navigationBars["Dino"].waitForExistence(timeout: 10))
        // The title names the guardian; its drawing keeps the name for VoiceOver alone.
        let drawing = app.scrollViews["marginarium-guardian-page"].buttons["marginarium-pet-dinotopia"]
        XCTAssertTrue(drawing.waitForExistence(timeout: 10))
        XCTAssertEqual(drawing.label, "Dino")
    }

    @MainActor
    func testWhosWhoOpensFromContentsAndAGuardianOpensItsBrief() {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "marginarium"]
        app.launch()
        let contents = app.scrollViews["marginarium-contents"]
        let link = app.buttons["marginarium-whos-who-link"]
        XCTAssertTrue(contents.waitForExistence(timeout: 15))
        for _ in 0..<15 {
            if link.exists && link.isHittable { break }
            contents.swipeUp()
        }
        XCTAssertTrue(link.exists && link.isHittable, "Who's Who isn't reachable from the contents")
        link.tap()
        XCTAssertTrue(app.navigationBars["Who's Who"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["marginarium-person-caroline"].exists)
        let card = app.buttons["marginarium-guardian-dinotopia"]
        let page = app.scrollViews["marginarium-whos-who"]
        for _ in 0..<8 {
            if card.exists && card.isHittable { break }
            page.swipeUp()
        }
        XCTAssertTrue(card.isHittable)
        XCTAssertTrue(card.label.contains("Guards the storybook feel"), card.label)
        attachScreenshot(of: app, named: "marginarium-whos-who")
        card.tap()
        XCTAssertTrue(app.navigationBars["Dino"].waitForExistence(timeout: 10))
        let brief = app.scrollViews["marginarium-guardian-page"]
        XCTAssertTrue(brief.buttons["marginarium-pet-dinotopia"].waitForExistence(timeout: 10))
        XCTAssertFalse(brief.descendants(matching: .any)["marginarium-egg"].exists)
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Teammates")).firstMatch.label
            .contains("The Storybook"))
        attachScreenshot(of: app, named: "marginarium-guardian-dinotopia")
    }

    @MainActor
    func testBriefAtAccessibilitySizeWithLongText() {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "marginarium-guardian-long-text", "-NSDoubleLocalizedStrings", "YES",
                               "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        let page = app.scrollViews["marginarium-guardian-page"]
        XCTAssertTrue(page.waitForExistence(timeout: 15))
        let happiest = page.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "a newcomer is made welcome")).firstMatch
        for _ in 0..<20 {
            if happiest.exists && happiest.isHittable { break }
            page.swipeUp()
        }
        XCTAssertTrue(happiest.exists && happiest.isHittable)
        XCTAssertGreaterThanOrEqual(happiest.frame.minX, page.frame.minX)
        XCTAssertLessThanOrEqual(happiest.frame.maxX, page.frame.maxX)
        attachScreenshot(of: app, named: "marginarium-guardian-accessibility-long-text")
    }
}
