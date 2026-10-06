import XCTest

/// Card menu actions in the gallery: deleting asks first, a time-lapse shows its progress and can be
/// cancelled, favorites sort first and filter, and the search field narrows the cards.
final class GalleryActionsTests: XCTestCase {
    @MainActor
    func testDeleteAsksForConfirmation() {
        let app = launchGallery()
        let card = revealCard("The Great Wave", in: app)
        card.press(forDuration: 1.5)
        let delete = app.buttons["Delete"]
        XCTAssertTrue(delete.waitForExistence(timeout: 5), "The card menu has no Delete")
        delete.tap()

        let message = app.staticTexts.matching(NSPredicate(format: "label MATCHES %@", ".*[0-9]+% painted.*")).firstMatch
        XCTAssertTrue(message.waitForExistence(timeout: 5), "Delete didn't ask for confirmation")
        attachScreenshot(of: app, named: "delete-confirmation")
        XCTAssertTrue(card.exists, "The painting was deleted before confirming")

        app.buttons["Delete “The Great Wave”"].tap()
        let undo = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Undo'")).firstMatch
        XCTAssertTrue(undo.waitForExistence(timeout: 5), "No undo after deleting")
        XCTAssertTrue(card.waitForNonExistence(timeout: 5), "The painting is still in the gallery")
        attachScreenshot(of: app, named: "deleted")
    }

    @MainActor
    func testTimelapseShowsProgressAndCancels() throws {
        let app = launchGallery()
        let card = revealCard("Delicate Arch", in: app)
        card.press(forDuration: 1.5)
        let share = app.buttons["Share Time-lapse"]
        XCTAssertTrue(share.waitForExistence(timeout: 5), "The finished card's menu has no Share Time-lapse")
        share.tap()

        let title = app.staticTexts["Making Your Time-lapse"]
        XCTAssertTrue(title.waitForExistence(timeout: 10), "No time-lapse progress sheet")
        attachScreenshot(of: app, named: "timelapse-progress")
        // The simulator may finish the movie first; then the share sheet is up instead.
        let cancel = app.buttons["Cancel"]
        guard cancel.exists, cancel.isHittable else { throw XCTSkip("The movie was ready before Cancel could be tapped") }
        cancel.tap()
        XCTAssertTrue(title.waitForNonExistence(timeout: 5), "Cancel didn't close the progress sheet")
        XCTAssertTrue(card.exists)
    }

    /// Favorite from the card menu: the card says so (the heart badge is part of its VoiceOver value),
    /// moves ahead of the unmarked ones, and offers Unfavorite next time.
    @MainActor
    func testFavoriteFromTheMenuMarksAndMovesTheCard() {
        let app = launchGallery()
        // The demo gallery's one favorite is Earthrise; The Milkmaid is the last card in progress.
        let milkmaid = revealCard("The Milkmaid", in: app)
        XCTAssertFalse(valueOf(milkmaid).contains("Favorite"), "The Milkmaid starts out as a favorite")
        milkmaid.press(forDuration: 1.5)
        let favorite = app.buttons["Favorite"]
        XCTAssertTrue(favorite.waitForExistence(timeout: 5), "The card menu has no Favorite")
        favorite.tap()

        XCTAssertTrue(waitFor(milkmaid, "value CONTAINS 'Favorite'"), "The card doesn't say it is a favorite")
        scrollToTop(app)
        let wave = app.buttons["The Great Wave"].firstMatch
        XCTAssertTrue(waitUntil { self.precedes(milkmaid, wave) }, "The favorite didn't move ahead of The Great Wave")
        attachScreenshot(of: app, named: "favorite")

        milkmaid.press(forDuration: 1.5)
        let unfavorite = app.buttons["Unfavorite"]
        XCTAssertTrue(unfavorite.waitForExistence(timeout: 5), "A favorite's menu has no Unfavorite")
        unfavorite.tap()
        XCTAssertTrue(waitFor(milkmaid, "NOT (value CONTAINS 'Favorite')"), "Unfavorite left the mark on the card")
        XCTAssertTrue(waitUntil { self.precedes(wave, milkmaid) }, "The card didn't return to its place")
    }

    /// The Show menu lists favorites only; with none left the gallery explains how to add one.
    @MainActor
    func testShowMenuFiltersFavorites() {
        let app = launchGallery()
        let earthrise = revealCard("Earthrise", in: app)
        let wave = app.buttons["The Great Wave"].firstMatch
        XCTAssertTrue(wave.exists)

        chooseShow("Favorites", in: app)
        XCTAssertTrue(wave.waitForNonExistence(timeout: 5), "The Great Wave is not a favorite but still shows")
        XCTAssertTrue(earthrise.exists, "The favorite disappeared under the Favorites filter")
        XCTAssertFalse(app.buttons["Delicate Arch"].exists, "A finished painting that is no favorite still shows")
        attachScreenshot(of: app, named: "favorites-filter")

        earthrise.press(forDuration: 1.5)
        let unfavorite = app.buttons["Unfavorite"]
        XCTAssertTrue(unfavorite.waitForExistence(timeout: 5), "The favorite's menu has no Unfavorite")
        unfavorite.tap()
        XCTAssertTrue(app.staticTexts["No Favorites"].waitForExistence(timeout: 5), "No empty state without favorites")
        attachScreenshot(of: app, named: "no-favorites")

        chooseShow("All", in: app)
        XCTAssertTrue(app.buttons["The Great Wave"].firstMatch.waitForExistence(timeout: 5), "All didn't bring the paintings back")
    }

    @MainActor
    func testSearchNarrowsToMatchingTitles() {
        let app = launchGallery()
        _ = revealCard("The Great Wave", in: app)
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10), "The gallery has no search field")
        field.tap()
        field.typeText("re")

        XCTAssertTrue(app.buttons["Red Fox in Snow"].firstMatch.waitForExistence(timeout: 5), "“re” didn't find Red Fox in Snow")
        XCTAssertTrue(app.buttons["Red Fuji"].firstMatch.exists, "“re” didn't find Red Fuji")
        XCTAssertTrue(app.buttons["The Great Wave"].firstMatch.waitForNonExistence(timeout: 5), "The Great Wave matches “re”")
        attachScreenshot(of: app, named: "search")

        field.typeText("zzz")
        let none = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'No Results'")).firstMatch
        XCTAssertTrue(none.waitForExistence(timeout: 5), "A query that matches nothing shows no empty state")
        attachScreenshot(of: app, named: "search-empty")
    }

    /// `gallery-search` starts with “re” typed: Red Fox in Snow (in progress) and Red Fuji (finished).
    @MainActor
    func testSearchScenarioShowsTwoResults() {
        let app = launchGallery("gallery-search")
        XCTAssertTrue(app.buttons["Red Fox in Snow"].firstMatch.waitForExistence(timeout: 120), "Red Fox in Snow never appeared")
        XCTAssertTrue(app.buttons["Red Fuji"].firstMatch.waitForExistence(timeout: 10), "Red Fuji never appeared")
        XCTAssertFalse(app.buttons["The Great Wave"].firstMatch.exists, "The Great Wave doesn't match the query")
        XCTAssertFalse(app.buttons["Earthrise"].firstMatch.exists, "Earthrise doesn't match the query")
    }

    /// `gallery-favorites` lists the two favorites, one in each section.
    @MainActor
    func testFavoritesScenarioShowsOnlyFavorites() {
        let app = launchGallery("gallery-favorites")
        XCTAssertTrue(app.buttons["Earthrise"].firstMatch.waitForExistence(timeout: 120), "Earthrise never appeared")
        XCTAssertTrue(app.buttons["Red Fuji"].firstMatch.waitForExistence(timeout: 10), "Red Fuji never appeared")
        XCTAssertFalse(app.buttons["The Great Wave"].firstMatch.exists, "The Great Wave is not a favorite")
        XCTAssertFalse(app.buttons["Delicate Arch"].firstMatch.exists, "Delicate Arch is not a favorite")
    }

    /// The demo gallery: six paintings, generated in the background at launch. They are the
    /// demo's fixed pictures (`-demoFixedPictures`), whose titles don't move with the library's order.
    @MainActor
    private func launchGallery(_ scenario: String = "gallery") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", scenario, "-demoFixedPictures", "YES"]
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
        if !card.isHittable { attachTree(of: app, named: "gallery-tree") }
        XCTAssertTrue(card.isHittable, "“\(title)” couldn't be scrolled into view")
        return card
    }
}
