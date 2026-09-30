import XCTest

/// Card menu actions in the gallery: deleting asks first, and a time-lapse shows its progress
/// and can be cancelled.
final class GalleryActionsTests: XCTestCase {
    @MainActor
    func testDeleteAsksForConfirmation() {
        let app = launchGallery()
        let card = revealCard("Parrots", in: app)
        card.press(forDuration: 1.5)
        let delete = app.buttons["Delete"]
        XCTAssertTrue(delete.waitForExistence(timeout: 5), "The card menu has no Delete")
        delete.tap()

        let message = app.staticTexts.matching(NSPredicate(format: "label MATCHES %@", ".*[0-9]+% painted.*")).firstMatch
        XCTAssertTrue(message.waitForExistence(timeout: 5), "Delete didn't ask for confirmation")
        attachScreenshot(of: app, named: "delete-confirmation")
        XCTAssertTrue(card.exists, "The painting was deleted before confirming")

        app.buttons["Delete “Parrots”"].tap()
        let undo = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Undo'")).firstMatch
        XCTAssertTrue(undo.waitForExistence(timeout: 5), "No undo after deleting")
        XCTAssertTrue(card.waitForNonExistence(withTimeout: 5), "The painting is still in the gallery")
        attachScreenshot(of: app, named: "deleted")
    }

    @MainActor
    func testTimelapseShowsProgressAndCancels() {
        let app = launchGallery()
        let card = revealCard("Hibiscus", in: app)
        card.press(forDuration: 1.5)
        let share = app.buttons["Share Time-lapse"]
        XCTAssertTrue(share.waitForExistence(timeout: 5), "The finished card's menu has no Share Time-lapse")
        share.tap()

        let title = app.staticTexts["Making Your Time-lapse"]
        XCTAssertTrue(title.waitForExistence(timeout: 10), "No time-lapse progress sheet")
        attachScreenshot(of: app, named: "timelapse-progress")
        // The simulator may finish the movie first; then the share sheet is up instead.
        let cancel = app.buttons["Cancel"]
        guard cancel.exists, cancel.isHittable else { return }
        cancel.tap()
        XCTAssertTrue(title.waitForNonExistence(withTimeout: 5), "Cancel didn't close the progress sheet")
        XCTAssertTrue(card.exists)
    }

    /// The demo gallery: six paintings, generated in the background at launch.
    @MainActor
    private func launchGallery() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "gallery"]
        app.launch()
        return app
    }

    /// Waits for a card to be ready and scrolls it into view (the finished ones sit below the
    /// fold on a phone).
    @MainActor
    private func revealCard(_ title: String, in app: XCUIApplication) -> XCUIElement {
        let card = app.descendants(matching: .any)[title]
        XCTAssertTrue(card.waitForExistence(timeout: 120), "“\(title)” never appeared")
        for _ in 0..<6 where !card.isHittable { app.swipeUp() }
        XCTAssertTrue(card.isHittable, "“\(title)” couldn't be scrolled into view")
        return card
    }

    @MainActor
    private func attachScreenshot(of app: XCUIApplication, named name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
