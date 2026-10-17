import XCTest

/// A painting whose template file is damaged explains itself and can be regenerated from its
/// photo, after which it opens for painting; deleting it asks first.
final class RecoveryTests: XCTestCase {
    /// Delete Painting asks before it deletes, with the dialog pointing at its button; Cancel keeps
    /// the painting (the screen stays, its buttons with it), and confirming deletes it with the
    /// gallery's Undo.
    @MainActor
    func testDeletePaintingAsksFirstAndCancelKeepsIt() {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "gallery-damaged", "-demoFixedPictures", "YES"]
        app.launch()
        let delete = app.buttons["Delete Painting"]
        XCTAssertTrue(delete.waitForExistence(timeout: 90), "The recovery screen didn't appear")
        let source = delete.frame
        delete.tap()

        let title = "Delete this painting?"
        guard let dialog = checkDialog(
            showing: [title, "Delete “The Great Wave”"], pointsAt: source, "recovery-delete", in: app) else { return }
        let message = app.staticTexts.matching(NSPredicate(format: "label MATCHES %@", ".*[0-9]+% painted.*")).firstMatch
        XCTAssertTrue(message.exists, "The dialog doesn't say how much of the painting is at stake")
        dismissDialog(at: dialog, titled: title, in: app)
        XCTAssertTrue(delete.exists, "The painting was deleted by Cancel: its recovery screen is gone")
        XCTAssertTrue(app.buttons["Regenerate"].exists, "Cancel left the recovery screen without its buttons")

        delete.tap()
        let confirm = app.buttons["Delete “The Great Wave”"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "Delete Painting didn't ask again")
        confirm.tap()
        let undo = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Undo'")).firstMatch
        XCTAssertTrue(undo.waitForExistence(timeout: 10), "Confirming didn't delete the painting (no Undo in the gallery)")
        XCTAssertTrue(delete.waitForNonExistence(timeout: 5), "The recovery screen stayed after the painting was deleted")
        attachScreenshot(of: app, named: "recovery-deleted")
    }

    @MainActor
    func testDamagedPaintingRegenerates() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "gallery-damaged"]
        app.launch()
        let regenerate = app.buttons["Regenerate"]
        XCTAssertTrue(regenerate.waitForExistence(timeout: 90), "The recovery screen didn't appear")
        XCTAssertTrue(app.buttons["Delete Painting"].exists)
        attachScreenshot(of: app, named: "recovery")

        regenerate.tap()
        XCTAssertTrue(app.buttons["Back"].waitForExistence(timeout: 120), "The regenerated painting didn't open")
        sleep(1)
        attachScreenshot(of: app, named: "regenerated")
    }
}
