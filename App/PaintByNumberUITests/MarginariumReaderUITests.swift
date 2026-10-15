import XCTest

/// The contents page's chapters and appendices open native reader pages, including at large text
/// sizes; Chapter 2 shows the guardians' drawings, and Chapter 1's margin notes carry them beside
/// the words, in a margin column beside the story where the page has room.
final class MarginariumReaderUITests: XCTestCase {
    @MainActor
    func testAppendicesOpenFromContents() {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "marginarium"]
        app.launch()
        XCTAssertTrue(app.navigationBars["The Marginarium"].waitForExistence(timeout: 15))
        // B, then C below it: the contents keeps its place, so the second only scrolls on.
        openEntry("thirtySixColors", in: app)
        XCTAssertTrue(app.navigationBars["Thirty-Six Colors"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["The Moon struck every name with daylight in it, four times."].exists)
        attachScreenshot(of: app, named: "marginarium-reader-appendix")
        app.navigationBars["Thirty-Six Colors"].buttons.firstMatch.tap()
        openEntry("lampBrush", in: app)
        XCTAssertTrue(app.navigationBars["The Lamp Picks Up a Brush"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["A Mac arrives, with a plan for the guardians to play."].exists)
        attachScreenshot(of: app, named: "marginarium-reader-former-chapter")
    }

    @MainActor
    func testChapterPetsAreVisibleAndRespondToTaps() {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "marginarium-chapter"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Two More Pets"].waitForExistence(timeout: 15))
        let pip = app.buttons["marginarium-pet-pip"]
        XCTAssertTrue(pip.waitForExistence(timeout: 10))
        XCTAssertEqual(pip.label, "Pip, Codex's teapot")
        XCTAssertTrue(pip.isHittable)
        pip.tap()
        attachScreenshot(of: app, named: "marginarium-reader-pip")
        let moth = app.buttons["marginarium-pet-colophon"]
        let reader = app.scrollViews["marginarium-reader"]
        for _ in 0..<5 {
            if moth.exists && moth.isHittable { break }
            reader.swipeUp()
        }
        XCTAssertEqual(moth.label, "Colophon, Claude's moth")
        XCTAssertTrue(moth.isHittable)
        moth.tap()
        attachScreenshot(of: app, named: "marginarium-reader-colophon")
    }

    @MainActor
    func testReaderAtAccessibilitySizeWithLongText() {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "marginarium-chapter-long-text", "-NSDoubleLocalizedStrings", "YES",
                               "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        let reader = app.scrollViews["marginarium-reader"]
        XCTAssertTrue(reader.waitForExistence(timeout: 15))
        // At this size the title itself wraps; scrolling must still reach the quotation.
        let pip = app.buttons["marginarium-pet-pip"]
        for _ in 0..<12 {
            if pip.exists && pip.isHittable { break }
            reader.swipeUp()
        }
        XCTAssertTrue(pip.exists && pip.isHittable)
        attachScreenshot(of: app, named: "marginarium-reader-pet-accessibility-long-text")
        let passage = reader.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "The checkers catch what a person would miss")).firstMatch
        for _ in 0..<12 {
            if passage.exists && passage.isHittable { break }
            reader.swipeUp()
        }
        XCTAssertTrue(passage.exists)
        XCTAssertTrue(passage.isHittable)
        attachScreenshot(of: app, named: "marginarium-reader-accessibility-long-text")
    }

    /// Chapter 1 opens on its one-line welcome; the renumbering note waits at the chapter's end.
    @MainActor
    func testChapterOneOpensWithItsWelcomeLine() {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "marginarium-chapter1"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Chapter 1: The Marginarium"].waitForExistence(timeout: 15))
        let welcome = app.staticTexts["One long night of ideas, with the Lamp in the margins."]
        XCTAssertTrue(welcome.exists && welcome.isHittable)
        let note = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@",
                                                        "Renumbered on October 11, 2026")).firstMatch
        XCTAssertFalse(note.exists && note.isHittable)
        attachScreenshot(of: app, named: "marginarium-chapter1-top")
    }

    @MainActor
    func testMarginNotesKeepTheirSignaturesAtAccessibilitySize() {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "marginarium-chapter1-margin-long-text", "-NSDoubleLocalizedStrings", "YES",
                               "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        let reader = app.scrollViews["marginarium-reader"]
        let note = reader.descendants(matching: .any).matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND label CONTAINS %@",
            "marginarium-note-", "Somebody is now")).firstMatch
        XCTAssertTrue(note.waitForExistence(timeout: 15))
        XCTAssertTrue(note.label.contains("Bart"))
        XCTAssertTrue(waitUntil { note.isHittable })
        XCTAssertGreaterThanOrEqual(note.frame.minX, reader.frame.minX)
        XCTAssertLessThanOrEqual(note.frame.maxX, reader.frame.maxX)
        attachScreenshot(of: app, named: "marginarium-chapter1-margin-accessibility-long-text")
    }

    /// The five notes of the second margin group are five guardians'; each has a pet beside it.
    @MainActor
    func testGuardiansNotesShowTheirPets() {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "marginarium-chapter1-guardians"]
        app.launch()
        let reader = app.scrollViews["marginarium-reader"]
        let note = reader.descendants(matching: .any).matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND label CONTAINS %@",
            "marginarium-note-", "Each figure paints one stage")).firstMatch
        XCTAssertTrue(note.waitForExistence(timeout: 15))
        XCTAssertTrue(note.label.contains("the Enchanted Workshop"))
        XCTAssertTrue(waitUntil { note.isHittable })
        // The pets are hidden from VoiceOver (the note names its speaker), but XCUITest's tree
        // still lists them (CI found 15), so this checks what a sighted reader gets: the
        // Enchanted Workshop's brush beside its note, and a tap that doesn't disturb the note.
        let brush = reader.descendants(matching: .any)["marginarium-pet-enchanted-workshop"]
        XCTAssertTrue(brush.waitForExistence(timeout: 10), "The Enchanted Workshop's note has no pet beside it")
        XCTAssertGreaterThan(brush.frame.minX, note.frame.minX, "The pet isn't beside the note")
        brush.tap()
        XCTAssertTrue(note.exists)
        XCTAssertGreaterThanOrEqual(note.frame.minX, reader.frame.minX)
        XCTAssertLessThanOrEqual(note.frame.maxX, reader.frame.maxX)
        attachScreenshot(of: app, named: "marginarium-chapter1-guardians")
    }

    /// On a page wide enough for a margin column (the iPad), a margin note stands beside the story
    /// it annotates; on a narrower one (the iPhone) the demo has opened it under its words, which
    /// come after the story's first paragraph.
    @MainActor
    func testMarginNotesStandBesideTheStoryWhereThereIsRoom() {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "marginarium-chapter1-guardians"]
        app.launch()
        let reader = app.scrollViews["marginarium-reader"]
        let note = reader.descendants(matching: .any).matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND label CONTAINS %@",
            "marginarium-note-", "Each figure paints one stage")).firstMatch
        XCTAssertTrue(note.waitForExistence(timeout: 15))
        XCTAssertTrue(waitUntil { note.isHittable })
        let story = reader.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@",
                                                            "The first request of the night sounded small")).firstMatch
        if reader.frame.width - 40 >= 700 {
            XCTAssertTrue(story.exists)
            XCTAssertGreaterThanOrEqual(note.frame.minX, story.frame.maxX, "The note isn't in a margin beside the story")
            XCTAssertLessThan(note.frame.minY, story.frame.maxY, "The note isn't beside the story it annotates")
        } else if story.exists {
            // Scrolled to the notes, the story above them may already have left the lazy stack.
            XCTAssertGreaterThanOrEqual(note.frame.minY, story.frame.maxY, "The note doesn't follow its story")
        }
        XCTAssertLessThanOrEqual(note.frame.maxX, reader.frame.maxX)
        attachScreenshot(of: app, named: "marginarium-chapter1-margin-column")
    }

    /// Highlighted words are links to the notes about them: on the iPhone a tap opens the notes in a
    /// card under the words, which closes again; beside a margin column they are already there.
    @MainActor
    func testTappingHighlightedWordsOpensTheirNotes() {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "marginarium-chapter1"]
        app.launch()
        let reader = app.scrollViews["marginarium-reader"]
        XCTAssertTrue(reader.waitForExistence(timeout: 15))
        let words = reader.links["writes in the margins"]
        XCTAssertTrue(words.waitForExistence(timeout: 10), "The narrator's highlighted words aren't a link")
        for _ in 0..<6 {
            if words.isHittable { break }
            reader.swipeUp()
        }
        let note = reader.descendants(matching: .any).matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND label CONTAINS %@",
            "marginarium-note-", "That is what a marginarium is")).firstMatch
        let card = reader.descendants(matching: .any)["marginarium-note-card"]
        if reader.frame.width - 40 < 700 {
            // XCUITest gives a link in a paragraph the frame of the whole lines it runs on (CI: the
            // text's full width, two lines tall), so the words are found by tapping along those
            // lines until their notes open. The rest of the paragraph is plain text: a miss is inert.
            search: for dy in [0.25, 0.75] {
                for dx in [0.5, 0.3, 0.7, 0.1, 0.9] {
                    words.coordinate(withNormalizedOffset: CGVector(dx: dx, dy: dy)).tap()
                    if card.waitForExistence(timeout: 1) { break search }
                }
            }
        } else {
            words.tap()
        }
        XCTAssertTrue(note.waitForExistence(timeout: 5))
        XCTAssertTrue(waitUntil { note.isHittable })
        if reader.frame.width - 40 >= 700 {
            XCTAssertFalse(card.exists, "Beside a margin column the notes need no card")
            XCTAssertGreaterThan(note.frame.minX, words.frame.maxX, "The note isn't beside its words")
            attachScreenshot(of: app, named: "marginarium-highlight-beside")
        } else {
            XCTAssertTrue(card.exists)
            XCTAssertGreaterThanOrEqual(note.frame.minY, words.frame.maxY, "The note didn't open under its words")
            attachScreenshot(of: app, named: "marginarium-highlight-open")
            app.buttons["marginarium-note-card-close"].tap()
            XCTAssertTrue(waitUntil { !card.exists }, "The card didn't close")
        }
    }

    @MainActor
    func testChapterTwoOpensFromContentsWithItsPets() {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "marginarium"]
        app.launch()
        XCTAssertTrue(app.navigationBars["The Marginarium"].waitForExistence(timeout: 15))
        openEntry("petsWeMade", in: app)
        XCTAssertTrue(app.navigationBars["The Drawings We Actually Made"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Chapter 2: The Drawings We Actually Made"].waitForExistence(timeout: 10))
        let reader = app.scrollViews["marginarium-reader"]
        let ram = app.buttons["marginarium-pet-medea"]
        for _ in 0..<12 {
            if ram.exists && ram.isHittable { break }
            reader.swipeUp()
        }
        XCTAssertTrue(ram.waitForExistence(timeout: 10))
        XCTAssertEqual(ram.label, "Medea")
        XCTAssertTrue(ram.isHittable)
        ram.tap()
        attachScreenshot(of: app, named: "marginarium-chapter2-medea")
    }

    @MainActor
    func testTableReadsByRowAndFitsTheReadingWidth() {
        checkChapterOneTable(longText: false)
    }

    @MainActor
    func testTableStacksAtAccessibilitySizeWithLongText() {
        checkChapterOneTable(longText: true)
    }

    @MainActor
    private func checkChapterOneTable(longText: Bool) {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", longText ? "marginarium-chapter1-table-long-text" : "marginarium-chapter1-table"]
        if longText {
            app.launchArguments += ["-NSDoubleLocalizedStrings", "YES", "-UIPreferredContentSizeCategoryName",
                                    "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        app.launch()
        let reader = app.scrollViews["marginarium-reader"]
        XCTAssertTrue(reader.waitForExistence(timeout: 15))
        let row = reader.descendants(matching: .any).matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND label CONTAINS %@",
            "marginarium-table-row-", "Medea")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        // A VoiceOver element contains the name followed by what that guardian keeps.
        XCTAssertTrue(row.label.contains("magic is a craft of renewal and care"))
        XCTAssertTrue(row.label.hasPrefix("Medea"))
        let layout = longText || reader.frame.width - 40 < 480
            ? "marginarium-table-stacked" : "marginarium-table-columns"
        XCTAssertTrue(reader.descendants(matching: .any)[layout].exists)
        for _ in 0..<6 {
            if row.isHittable { break }
            reader.swipeUp()
        }
        XCTAssertTrue(row.isHittable)
        XCTAssertGreaterThanOrEqual(row.frame.minX, reader.frame.minX)
        XCTAssertLessThanOrEqual(row.frame.maxX, reader.frame.maxX)
        attachScreenshot(of: app, named: longText ? "marginarium-chapter1-table-accessibility-long-text" : "marginarium-chapter1-table")
    }

    @MainActor
    private func openEntry(_ id: String, in app: XCUIApplication) {
        let contents = app.scrollViews["marginarium-contents"]
        XCTAssertTrue(contents.waitForExistence(timeout: 10))
        let link = app.buttons["marginarium-entry-\(id)"]
        for _ in 0..<15 {
            if link.exists && link.isHittable { break }
            contents.swipeUp()
        }
        XCTAssertTrue(link.exists && link.isHittable, "Contents entry isn't reachable: \(id)")
        link.tap()
        XCTAssertTrue(app.scrollViews["marginarium-reader"].waitForExistence(timeout: 10))
    }
}
