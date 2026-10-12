import XCTest

/// Who's Who opens from the contents page's New here? box; a guardian's card opens its brief,
/// which stays readable at the largest text sizes.
final class MarginariumWhosWhoUITests: XCTestCase {
    @MainActor
    func testWhosWhoOpensFromContentsAndAGuardianOpensItsBrief() {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "marginarium"]
        app.launch()
        let link = app.buttons["marginarium-whos-who-link"]
        XCTAssertTrue(link.waitForExistence(timeout: 15))
        XCTAssertTrue(waitUntil { link.isHittable })
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
        XCTAssertTrue(app.navigationBars["Dinotopia"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["marginarium-egg"].exists)
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
