import XCTest

/// Card menu actions in the gallery: deleting asks first, a time-lapse shows its progress and can be
/// cancelled, favorites sort first and filter, and the search field narrows the cards.
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
        XCTAssertTrue(card.waitForNonExistence(timeout: 5), "The painting is still in the gallery")
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
        XCTAssertTrue(app.descendants(matching: .any)["timelapse-pace"].exists, "The time-lapse sheet has no Pace control")
        attachScreenshot(of: app, named: "timelapse-progress")
        // The simulator may finish the movie first; then the share sheet is up instead.
        let cancel = app.buttons["Cancel"]
        guard cancel.exists, cancel.isHittable else { return }
        cancel.tap()
        XCTAssertTrue(title.waitForNonExistence(timeout: 5), "Cancel didn't close the progress sheet")
        XCTAssertTrue(card.exists)
    }

    /// Favorite from the card menu: the card says so (the heart badge is part of its VoiceOver value),
    /// moves ahead of the unmarked ones, and offers Unfavorite next time.
    @MainActor
    func testFavoriteFromTheMenuMarksAndMovesTheCard() {
        let app = launchGallery()
        // The demo gallery's one favorite is Lighthouse; Espresso is the last card in progress.
        let espresso = revealCard("Espresso", in: app)
        XCTAssertFalse(valueOf(espresso).contains("Favorite"), "Espresso starts out as a favorite")
        espresso.press(forDuration: 1.5)
        let favorite = app.buttons["Favorite"]
        XCTAssertTrue(favorite.waitForExistence(timeout: 5), "The card menu has no Favorite")
        favorite.tap()

        XCTAssertTrue(waitFor(espresso, "value CONTAINS 'Favorite'"), "The card doesn't say it is a favorite")
        scrollToTop(app)
        let parrots = app.buttons["Parrots"].firstMatch
        XCTAssertTrue(waitUntil { self.precedes(espresso, parrots) }, "The favorite didn't move ahead of Parrots")
        attachScreenshot(of: app, named: "favorite")

        espresso.press(forDuration: 1.5)
        let unfavorite = app.buttons["Unfavorite"]
        XCTAssertTrue(unfavorite.waitForExistence(timeout: 5), "A favorite's menu has no Unfavorite")
        unfavorite.tap()
        XCTAssertTrue(waitFor(espresso, "NOT (value CONTAINS 'Favorite')"), "Unfavorite left the mark on the card")
        XCTAssertTrue(waitUntil { self.precedes(parrots, espresso) }, "The card didn't return to its place")
    }

    /// The Show menu lists favorites only; with none left the gallery explains how to add one.
    @MainActor
    func testShowMenuFiltersFavorites() {
        let app = launchGallery()
        let lighthouse = revealCard("Lighthouse", in: app)
        let parrots = app.buttons["Parrots"].firstMatch
        XCTAssertTrue(parrots.exists)

        chooseShow("Favorites", in: app)
        XCTAssertTrue(parrots.waitForNonExistence(timeout: 5), "Parrots is not a favorite but still shows")
        XCTAssertTrue(lighthouse.exists, "The favorite disappeared under the Favorites filter")
        XCTAssertFalse(app.buttons["Hibiscus"].exists, "A finished painting that is no favorite still shows")
        attachScreenshot(of: app, named: "favorites-filter")

        lighthouse.press(forDuration: 1.5)
        let unfavorite = app.buttons["Unfavorite"]
        XCTAssertTrue(unfavorite.waitForExistence(timeout: 5), "The favorite's menu has no Unfavorite")
        unfavorite.tap()
        XCTAssertTrue(app.staticTexts["No Favorites"].waitForExistence(timeout: 5), "No empty state without favorites")
        attachScreenshot(of: app, named: "no-favorites")

        chooseShow("All", in: app)
        XCTAssertTrue(app.buttons["Parrots"].firstMatch.waitForExistence(timeout: 5), "All didn't bring the paintings back")
    }

    @MainActor
    func testSearchNarrowsToMatchingTitles() {
        let app = launchGallery()
        _ = revealCard("Parrots", in: app)
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10), "The gallery has no search field")
        field.tap()
        field.typeText("re")

        XCTAssertTrue(app.buttons["Red Barn"].firstMatch.waitForExistence(timeout: 5), "“re” didn't find Red Barn")
        XCTAssertTrue(app.buttons["Regatta"].firstMatch.exists, "“re” didn't find Regatta")
        XCTAssertTrue(app.buttons["Parrots"].firstMatch.waitForNonExistence(timeout: 5), "Parrots matches “re”")
        attachScreenshot(of: app, named: "search")

        field.typeText("zzz")
        let none = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'No Results'")).firstMatch
        XCTAssertTrue(none.waitForExistence(timeout: 5), "A query that matches nothing shows no empty state")
        attachScreenshot(of: app, named: "search-empty")
    }

    /// `gallery-search` starts with “re” typed: Red Barn (in progress) and Regatta (finished).
    @MainActor
    func testSearchScenarioShowsTwoResults() {
        let app = launchGallery("gallery-search")
        XCTAssertTrue(app.buttons["Red Barn"].firstMatch.waitForExistence(timeout: 120), "Red Barn never appeared")
        XCTAssertTrue(app.buttons["Regatta"].firstMatch.waitForExistence(timeout: 10), "Regatta never appeared")
        XCTAssertFalse(app.buttons["Parrots"].firstMatch.exists, "Parrots doesn't match the query")
        XCTAssertFalse(app.buttons["Lighthouse"].firstMatch.exists, "Lighthouse doesn't match the query")
    }

    /// `gallery-favorites` lists the two favorites, one in each section.
    @MainActor
    func testFavoritesScenarioShowsOnlyFavorites() {
        let app = launchGallery("gallery-favorites")
        XCTAssertTrue(app.buttons["Lighthouse"].firstMatch.waitForExistence(timeout: 120), "Lighthouse never appeared")
        XCTAssertTrue(app.buttons["Regatta"].firstMatch.waitForExistence(timeout: 10), "Regatta never appeared")
        XCTAssertFalse(app.buttons["Parrots"].firstMatch.exists, "Parrots is not a favorite")
        XCTAssertFalse(app.buttons["Hibiscus"].firstMatch.exists, "Hibiscus is not a favorite")
    }

    /// The demo gallery: six paintings, generated in the background at launch. They are the
    /// retired samples' (`-demoRetiredSamples`), whose titles don't move with the library's curation.
    @MainActor
    private func launchGallery(_ scenario: String = "gallery") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", scenario, "-demoRetiredSamples", "YES"]
        app.launch()
        return app
    }

    /// Picks a choice of the toolbar's Show menu.
    @MainActor
    private func chooseShow(_ choice: String, in app: XCUIApplication) {
        let show = app.buttons["Show"]
        XCTAssertTrue(show.waitForExistence(timeout: 10), "The gallery has no Show menu")
        show.tap()
        let item = app.descendants(matching: .any).matching(identifier: choice).firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 5), "The Show menu has no “\(choice)”")
        item.tap()
    }

    @MainActor
    private func valueOf(_ element: XCUIElement) -> String { element.value as? String ?? "" }

    @MainActor
    private func scrollToTop(_ app: XCUIApplication) {
        for _ in 0..<3 { app.swipeDown() }
    }

    /// Whether `first` sits before `second` in reading order (rows top to bottom, then left to right).
    @MainActor
    private func precedes(_ first: XCUIElement, _ second: XCUIElement) -> Bool {
        guard first.exists, second.exists else { return false }
        let a = first.frame, b = second.frame
        if abs(a.minY - b.minY) > 1 { return a.minY < b.minY }
        return a.minX < b.minX
    }

    @MainActor
    private func waitFor(_ element: XCUIElement, _ predicate: String, timeout: TimeInterval = 5) -> Bool {
        let wait = XCTNSPredicateExpectation(predicate: NSPredicate(format: predicate), object: element)
        return XCTWaiter.wait(for: [wait], timeout: timeout) == .completed
    }

    /// Polls until `condition` holds (card moves animate), up to `timeout` seconds.
    @MainActor
    private func waitUntil(timeout: TimeInterval = 5, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            Thread.sleep(forTimeInterval: 0.25)
        }
        return condition()
    }

    /// Waits for a card to be ready and scrolls it into view (the finished ones sit below the
    /// fold on a phone). Cards are buttons; the placeholder shown while a painting is still
    /// being generated is not, so it can't be mistaken for the card.
    @MainActor
    private func revealCard(_ title: String, in app: XCUIApplication) -> XCUIElement {
        let card = app.buttons[title].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 120), "“\(title)” never appeared")
        // Cards still being generated slide the others along as they land: a long press
        // meanwhile can open a neighbour's menu.
        let preparing = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Preparing'")).firstMatch
        XCTAssertTrue(preparing.waitForNonExistence(timeout: 120), "The demo gallery never finished generating")
        for _ in 0..<6 where !card.isHittable { app.swipeUp() }
        if !card.isHittable {
            let tree = XCTAttachment(string: app.debugDescription)
            tree.name = "gallery-tree"
            tree.lifetime = .keepAlways
            add(tree)
        }
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
