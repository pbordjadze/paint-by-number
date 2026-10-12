import XCTest

/// Both sections of the contents page open native reader pages, including at large text sizes;
/// Chapter 6 shows the guardians' pets, and Chapter 1's margin notes carry them beside the words.
final class MarginariumReaderUITests: XCTestCase {
    @MainActor
    func testChapterAndAppendixOpenFromContents() {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "marginarium"]
        app.launch()
        XCTAssertTrue(app.navigationBars["The Marginarium"].waitForExistence(timeout: 15))
        openEntry("lampBrush", in: app)
        XCTAssertTrue(app.navigationBars["The Lamp Picks Up a Brush"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["A Mac arrives, with a plan for the guardians to play."].exists)
        attachScreenshot(of: app, named: "marginarium-reader-chapter")
        app.navigationBars["The Lamp Picks Up a Brush"].buttons.firstMatch.tap()
        openEntry("thirtySixColors", in: app)
        XCTAssertTrue(app.navigationBars["Thirty-Six Colors"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["The Moon struck every name with daylight in it, four times."].exists)
        attachScreenshot(of: app, named: "marginarium-reader-appendix")
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

    @MainActor
    func testChapterOneOpensWithItsRenumberNote() {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "marginarium-chapter1"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Chapter 1: The Marginarium"].waitForExistence(timeout: 15))
        let note = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@",
                                                        "Renumbered on October 11, 2026")).firstMatch
        XCTAssertTrue(note.exists && note.isHittable)
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
            "marginarium-note-", "A proper djinni")).firstMatch
        XCTAssertTrue(note.waitForExistence(timeout: 15))
        XCTAssertTrue(note.label.contains("the narrator"))
        XCTAssertTrue(waitUntil { note.isHittable })
        XCTAssertGreaterThanOrEqual(note.frame.minX, reader.frame.minX)
        XCTAssertLessThanOrEqual(note.frame.maxX, reader.frame.maxX)
        attachScreenshot(of: app, named: "marginarium-chapter1-margin-accessibility-long-text")
    }

    /// The five notes of the second margin group are five guardians'; each has a pet beside it, and
    /// VoiceOver reads only the notes, which already carry the speakers' names.
    @MainActor
    func testGuardiansNotesKeepTheirPetsOutOfVoiceOver() {
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
        XCTAssertEqual(reader.descendants(matching: .any).matching(NSPredicate(
            format: "identifier BEGINSWITH %@", "marginarium-pet-")).count, 0,
            "Margin pets are decorative: the speaker's name is in the note")
        XCTAssertGreaterThanOrEqual(note.frame.minX, reader.frame.minX)
        XCTAssertLessThanOrEqual(note.frame.maxX, reader.frame.maxX)
        attachScreenshot(of: app, named: "marginarium-chapter1-guardians")
    }

    @MainActor
    func testChapterSixOpensFromContentsWithItsPets() {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "marginarium"]
        app.launch()
        XCTAssertTrue(app.navigationBars["The Marginarium"].waitForExistence(timeout: 15))
        openEntry("petsWeMade", in: app)
        XCTAssertTrue(app.navigationBars["The Pets We Actually Made"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Chapter 6: The Pets We Actually Made"].waitForExistence(timeout: 10))
        let reader = app.scrollViews["marginarium-reader"]
        let ram = app.buttons["marginarium-pet-medea"]
        for _ in 0..<12 {
            if ram.exists && ram.isHittable { break }
            reader.swipeUp()
        }
        XCTAssertTrue(ram.waitForExistence(timeout: 10))
        XCTAssertEqual(ram.label, "Medea, Medea's golden ram")
        XCTAssertTrue(ram.isHittable)
        ram.tap()
        attachScreenshot(of: app, named: "marginarium-chapter6-medea")
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
