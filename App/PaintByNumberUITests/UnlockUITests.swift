import XCTest

/// Unlimited Paintings in the create flow: a painting of the painter's own photo with no free
/// painting left offers the unlock at Start Painting (`UnlockSheet`), Not Now keeps the preview,
/// and buying starts the painting; in 1.1 (Debug builds) a library picture takes one too. The App Store is
/// `UnlockStoreStub` (Debug launches): nothing is bought for real.
final class UnlockUITests: XCTestCase {
    @MainActor
    func testStartWithNoFreePaintingOffersTheUnlockAndBuyingStarts() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "create-from-file", "-demoFreePaintings", "0"]
        app.launch()

        let start = app.buttons["Start Painting"]
        XCTAssertTrue(start.waitForExistence(timeout: 60), "The opened file didn't open the create flow")
        XCTAssertTrue(waitFor(start, toMatch: NSPredicate(format: "isEnabled == true"), timeout: 90), "Start Painting never enabled")
        let count = app.staticTexts["free-paintings"]
        XCTAssertTrue(count.exists, "No free paintings line under Start Painting")
        XCTAssertEqual(count.label, "Your next free painting comes tomorrow.")
        // Start works from the first draft: the 60 s for buying to start are the full resolution's.
        XCTAssertTrue(waitForSuggestion(in: app), "The preview never chose its settings")

        start.tap()
        let buy = app.buttons["unlock-buy"]
        XCTAssertTrue(buy.waitForExistence(timeout: 10), "Start Painting with no free painting left didn't offer the unlock")
        XCTAssertTrue(app.buttons["unlock-restore"].exists, "The sheet has no Restore Purchases")
        app.buttons["unlock-not-now"].tap()
        XCTAssertTrue(buy.waitForNonExistence(timeout: 10), "Not Now didn't close the sheet")
        XCTAssertTrue(waitFor(start, toMatch: NSPredicate(format: "isEnabled == true")), "Not Now left Start Painting off")

        start.tap()
        XCTAssertTrue(buy.waitForExistence(timeout: 10), "Start Painting didn't offer the unlock again")
        XCTAssertTrue(waitFor(buy, toMatch: NSPredicate(format: "label CONTAINS '4.99'")), "The buy button never showed the price: \(buy.label)")
        attachScreenshot(of: app, named: "unlock-from-start")
        buy.tap()
        XCTAssertTrue(start.waitForNonExistence(timeout: 60), "Buying didn't start the painting")
    }

    /// At the largest accessibility text size the sheet scrolls, and its buttons can still be
    /// reached: `create-unlock` opens it once the painting is made.
    @MainActor
    func testTheSheetKeepsItsButtonsAtTheLargestTextSize() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "create-unlock", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()

        let buy = app.buttons["unlock-buy"]
        XCTAssertTrue(buy.waitForExistence(timeout: 120), "create-unlock didn't open the sheet")
        XCTAssertTrue(waitFor(buy, toMatch: NSPredicate(format: "label CONTAINS '4.99'")), "The buy button never showed the price: \(buy.label)")
        attachScreenshot(of: app, named: "unlock-accessibility")
        let restore = app.buttons["unlock-restore"]
        for _ in 0..<4 where !restore.isHittable { app.swipeUp() }
        XCTAssertTrue(restore.isHittable, "Restore Purchases can't be reached at the largest text size")
    }

    /// Restore Purchases answers a fingertip beside its words, not the words alone (110 by 16
    /// points, QA, November 7): a tap above them restores, and with nothing bought says so.
    @MainActor
    func testRestorePurchasesTakesATapBesideItsWords() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "create-unlock"]
        app.launch()

        let restore = app.buttons["unlock-restore"]
        XCTAssertTrue(restore.waitForExistence(timeout: 120), "create-unlock didn't open the sheet")
        XCTAssertTrue(waitUntil(timeout: 10) { restore.isHittable }, "Restore Purchases isn't on screen")
        restore.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).withOffset(CGVector(dx: 0, dy: -15)).tap()
        let note = app.descendants(matching: .any)["unlock-note"]
        XCTAssertTrue(note.waitForExistence(timeout: 10), "A tap just above Restore Purchases restored nothing")
    }

    /// A library picture takes a free painting as any new painting does (1.1, the owner's decision
    /// of November 5; Debug builds count as 1.1 does): with none left, its preview says when the
    /// next comes and Start Painting offers the unlock.
    @MainActor
    func testALibraryPictureTakesAFreePaintingToo() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "create-preview", "-demoFixedPictures", "YES", "-demoFreePaintings", "0"]
        app.launch()

        let start = app.buttons["Start Painting"]
        XCTAssertTrue(start.waitForExistence(timeout: 60), "The sample didn't open its preview")
        XCTAssertTrue(waitFor(start, toMatch: NSPredicate(format: "isEnabled == true"), timeout: 90), "Start Painting never enabled")
        XCTAssertTrue(app.staticTexts["free-paintings"].waitForExistence(timeout: 10), "A library picture's preview counts no free paintings")
        XCTAssertTrue(waitForSuggestion(in: app), "The preview never chose its settings")
        start.tap()
        XCTAssertTrue(app.buttons["unlock-buy"].waitForExistence(timeout: 60), "A library picture with no free painting left started")
    }
}
