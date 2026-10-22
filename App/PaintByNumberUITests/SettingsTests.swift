import XCTest

/// Settings: About (version, acknowledgements), Paper, Line Weight, Tips, Music, Painting Length,
/// Preview, The Marginarium, The Making-of and Unlimited Paintings.
final class SettingsTests: XCTestCase {
    @MainActor
    func testAboutShowsTheVersion() throws {
        let app = openSettings()
        let version = app.descendants(matching: .any)["about-version"]
        scroll(app, to: version)
        attachScreenshot(of: app, named: "settings-about")
        XCTAssertTrue(version.exists, "Settings has no version row")
        let text = "\(version.label) \(version.value as? String ?? "")"
        XCTAssertNotNil(
            text.range(of: #"\d+(\.\d+)* \(\d+\)"#, options: .regularExpression),
            "The version row doesn't read like \"1.0 (1)\": \(text)")
    }

    /// Acknowledgements opens on the sample pictures' credits; the algorithm ports follow them.
    @MainActor
    func testAcknowledgementsListTheAlgorithmPorts() throws {
        let app = openSettings()
        let row = app.descendants(matching: .any)["about-acknowledgements"]
        scroll(app, to: row)
        XCTAssertTrue(row.exists, "Settings has no Acknowledgements row")
        row.tap()

        XCTAssertTrue(app.navigationBars["Acknowledgements"].waitForExistence(timeout: 10))
        let pictures = app.descendants(matching: .any).matching(NSPredicate(format: "label ==[c] 'Pictures'")).firstMatch
        XCTAssertTrue(pictures.waitForExistence(timeout: 5), "Acknowledgements doesn't open on the Pictures section")
        for credit in ["mapbox/earcut", "mapbox/polylabel", "Peter Selinger"] {
            let entry = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", credit)).firstMatch
            // Past every picture's credit.
            scroll(app, to: entry, maxDrags: 30)
            XCTAssertTrue(entry.exists, "Acknowledgements doesn't credit \(credit)")
        }
        attachScreenshot(of: app, named: "acknowledgements")
    }

    /// Settings › Paper offers Light, Dark and Automatic, starts on Light and keeps the choice.
    @MainActor
    func testPaperPickerChangesTheValue() throws {
        let app = openSettings()
        let picker = app.descendants(matching: .any)["paper-appearance"]
        XCTAssertTrue(picker.waitForExistence(timeout: 10), "Settings has no Paper picker")
        XCTAssertTrue(describe(picker).contains("Light"), "Paper doesn't start on Light: \(describe(picker))")
        picker.tap()
        for choice in ["Light", "Dark", "Automatic"] {
            XCTAssertTrue(app.buttons[choice].waitForExistence(timeout: 5), "The Paper picker has no \(choice)")
        }
        app.buttons["Dark"].firstMatch.tap()
        XCTAssertTrue(shows(picker, "Dark"), "Choosing Dark didn't change the picker: \(describe(picker))")
        attachScreenshot(of: app, named: "settings-paper-dark")
        // The choice is stored in the simulator's defaults: put it back for the other tests.
        picker.tap()
        XCTAssertTrue(app.buttons["Light"].waitForExistence(timeout: 5))
        app.buttons["Light"].firstMatch.tap()
        XCTAssertTrue(shows(picker, "Light"), "Choosing Light didn't change the picker: \(describe(picker))")
    }

    /// Settings › Line Weight offers Fine, Regular and Bold, starts on Regular and keeps the choice.
    @MainActor
    func testLineWeightPickerChangesTheValue() throws {
        let app = openSettings()
        let picker = app.descendants(matching: .any)["settings-line-weight"]
        scroll(app, to: picker)
        XCTAssertTrue(picker.exists, "Settings has no Line Weight picker")
        XCTAssertTrue(describe(picker).contains("Regular"), "Line Weight doesn't start on Regular: \(describe(picker))")
        picker.tap()
        for choice in ["Fine", "Regular", "Bold"] {
            XCTAssertTrue(app.buttons[choice].waitForExistence(timeout: 5), "The Line Weight picker has no \(choice)")
        }
        app.buttons["Bold"].firstMatch.tap()
        XCTAssertTrue(shows(picker, "Bold"), "Choosing Bold didn't change the picker: \(describe(picker))")
        attachScreenshot(of: app, named: "settings-line-weight-bold")
        // The choice is stored in the simulator's defaults: put it back for the other tests.
        picker.tap()
        XCTAssertTrue(app.buttons["Regular"].waitForExistence(timeout: 5))
        app.buttons["Regular"].firstMatch.tap()
        XCTAssertTrue(shows(picker, "Regular"), "Choosing Regular didn't change the picker: \(describe(picker))")
    }

    /// Settings › Music offers Sun, Moon and Auto in one row, starts on Auto, keeps the choice and
    /// says when Auto brings the Sun and the Moon, by the painter's clock, only while it is on Auto.
    @MainActor
    func testMusicPickerChangesTheChoice() throws {
        let app = openSettings()
        let picker = app.descendants(matching: .any)["settings-music"]
        scroll(app, to: picker)
        XCTAssertTrue(picker.exists, "Settings has no Music picker")
        XCTAssertTrue(describe(picker).contains("Auto"), "Music doesn't start on Auto: \(describe(picker))")
        let footer = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "your time")).firstMatch
        scroll(app, to: footer)
        XCTAssertTrue(footer.exists, "Music's footer doesn't say when Auto brings the Sun and the Moon")
        picker.tap()
        for choice in ["Sun", "Moon", "Auto"] {
            XCTAssertTrue(app.buttons[choice].waitForExistence(timeout: 5), "The Music picker has no \(choice)")
        }
        app.buttons["Moon"].firstMatch.tap()
        XCTAssertTrue(shows(picker, "Moon"), "Choosing Moon didn't change the picker: \(describe(picker))")
        XCTAssertTrue(footer.waitForNonExistence(timeout: 5), "Auto's hours stayed under Moon")
        attachScreenshot(of: app, named: "settings-music-moon")
        // The choice is stored in the simulator's defaults: back to Auto for the other tests.
        picker.tap()
        XCTAssertTrue(app.buttons["Auto"].waitForExistence(timeout: 5))
        app.buttons["Auto"].firstMatch.tap()
        XCTAssertTrue(shows(picker, "Auto"), "Choosing Auto didn't change the picker: \(describe(picker))")
        XCTAssertTrue(footer.waitForExistence(timeout: 5), "Auto's hours didn't come back with Auto")
    }

    /// Settings › Painting Length offers Quick, Relaxed and Detailed, starts on Relaxed, keeps
    /// the choice and says what it aims for.
    @MainActor
    func testPaintingLengthPickerChangesTheValue() throws {
        let app = openSettings()
        let picker = app.descendants(matching: .any)["painting-length"]
        scroll(app, to: picker)
        XCTAssertTrue(picker.exists, "Settings has no Painting Length picker")
        XCTAssertTrue(describe(picker).contains("Relaxed"), "Painting Length doesn't start on Relaxed: \(describe(picker))")
        // The footer sits below the picker: a list only builds the rows it has scrolled to.
        let footer = app.staticTexts["painting-length-footer"]
        scroll(app, to: footer)
        XCTAssertTrue(footer.label.hasPrefix("Suggested settings aim for about half an hour"), "Relaxed footer: \(footer.label)")
        picker.tap()
        for choice in ["Quick", "Relaxed", "Detailed"] {
            XCTAssertTrue(app.buttons[choice].waitForExistence(timeout: 5), "The Painting Length picker has no \(choice)")
        }
        app.buttons["Quick"].firstMatch.tap()
        XCTAssertTrue(shows(picker, "Quick"), "Choosing Quick didn't change the picker: \(describe(picker))")
        let quickFooter = NSPredicate(format: "label == 'Suggested settings aim for about 15 minutes of painting.'")
        XCTAssertEqual(
            XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: quickFooter, object: footer)], timeout: 5), .completed,
            "Quick footer: \(footer.label)")
        attachScreenshot(of: app, named: "settings-painting-length-quick")

        // Back to the default, so later create-flow tests and screenshots aim for Relaxed.
        picker.tap()
        XCTAssertTrue(app.buttons["Relaxed"].waitForExistence(timeout: 5))
        app.buttons["Relaxed"].firstMatch.tap()
        XCTAssertTrue(shows(picker, "Relaxed"))
    }

    /// Settings › Preview offers Painting and Line Art, starts on Painting and keeps the choice.
    @MainActor
    func testPreviewPickerChangesTheValue() throws {
        let app = openSettings()
        let picker = app.descendants(matching: .any)["settings-preview"]
        scroll(app, to: picker)
        XCTAssertTrue(picker.exists, "Settings has no Preview picker")
        XCTAssertTrue(describe(picker).contains("Painting"), "Preview doesn't start on Painting: \(describe(picker))")
        picker.tap()
        for choice in ["Painting", "Line Art"] {
            XCTAssertTrue(app.buttons[choice].waitForExistence(timeout: 5), "The Preview picker has no \(choice)")
        }
        app.buttons["Line Art"].firstMatch.tap()
        XCTAssertTrue(shows(picker, "Line Art"), "Choosing Line Art didn't change the picker: \(describe(picker))")
        attachScreenshot(of: app, named: "settings-preview-line-art")
        // The choice is stored in the simulator's defaults: put it back for the other tests.
        picker.tap()
        XCTAssertTrue(app.buttons["Painting"].waitForExistence(timeout: 5))
        app.buttons["Painting"].firstMatch.tap()
        XCTAssertTrue(shows(picker, "Painting"), "Choosing Painting didn't change the picker: \(describe(picker))")
    }

    /// The Marginarium is hidden until its switch puts the book in the gallery's toolbar.
    @MainActor
    func testMarginariumSwitchShowsTheBook() throws {
        let app = openSettings()
        let book = app.buttons["The Marginarium"]
        let toggle = app.switches["settings-marginarium"]
        scroll(app, to: toggle)
        XCTAssertTrue(toggle.exists, "Settings has no Marginarium switch")
        XCTAssertEqual(toggle.value as? String, "0", "The Marginarium doesn't start hidden")
        XCTAssertTrue(flip(toggle, on: true), "The Marginarium didn't switch on: \(toggle.value ?? "")")
        attachScreenshot(of: app, named: "settings-marginarium")
        app.navigationBars["Settings"].buttons["Done"].tap()
        XCTAssertTrue(book.waitForExistence(timeout: 10), "The gallery's toolbar has no Marginarium once it is on")
        book.tap()
        XCTAssertTrue(app.navigationBars["The Marginarium"].waitForExistence(timeout: 10), "The book didn't open the Marginarium")
        // Stored in the simulator's defaults: hidden again for the other tests.
        app.terminate()
        let again = openSettings()
        let off = again.switches["settings-marginarium"]
        scroll(again, to: off)
        XCTAssertTrue(flip(off, on: false), "The Marginarium didn't switch off: \(off.value ?? "")")
        again.navigationBars["Settings"].buttons["Done"].tap()
        XCTAssertTrue(again.buttons["Settings"].waitForExistence(timeout: 10))
        XCTAssertFalse(again.buttons["The Marginarium"].exists, "The book stayed in the toolbar once hidden")
    }

    /// The Making-of starts off and switches on (Start then plays the show: `MakingOfUITests`).
    @MainActor
    func testMakingOfSwitchStartsOffAndTurnsOn() throws {
        let app = openSettings()
        let toggle = app.switches["settings-making-of"]
        scroll(app, to: toggle)
        // Below the Marginarium's: a row the list has made can still be under the fold.
        for _ in 0..<3 where toggle.exists && !toggle.isHittable { app.swipeUp() }
        XCTAssertTrue(toggle.exists, "Settings has no Making-of switch")
        XCTAssertEqual(toggle.value as? String, "0", "The Making-of doesn't start off")
        XCTAssertTrue(flip(toggle, on: true), "The Making-of didn't switch on: \(toggle.value ?? "")")
        attachScreenshot(of: app, named: "settings-making-of")
        // Stored in the simulator's defaults: off again for the other tests.
        XCTAssertTrue(flip(toggle, on: false), "The Making-of didn't switch off: \(toggle.value ?? "")")
    }

    /// Unlimited Paintings: the free paintings left, and the unlock's sheet, which buys it (the
    /// App Store is the Debug stub) and leaves the row saying it is unlocked.
    @MainActor
    func testUnlimitedPaintingsShowsTheFreeOnesAndUnlocks() throws {
        let app = openSettings(arguments: ["-demoFreePaintings", "2"])
        let free = app.descendants(matching: .any)["settings-free-paintings"]
        scroll(app, to: free)
        for _ in 0..<3 where free.exists && !free.isHittable { app.swipeUp() }
        XCTAssertTrue(free.exists, "Settings has no Free Paintings row")
        XCTAssertTrue(describe(free).contains("2 left"), "The Free Paintings row doesn't say 2 left: \(describe(free))")
        let unlimited = app.buttons["settings-unlimited"]
        XCTAssertTrue(unlimited.exists, "Settings offers no Unlimited Paintings")
        unlimited.tap()

        let buy = app.buttons["unlock-buy"]
        XCTAssertTrue(buy.waitForExistence(timeout: 10), "Unlimited Paintings didn't open its sheet")
        XCTAssertTrue(app.buttons["unlock-restore"].exists, "The sheet has no Restore Purchases")
        XCTAssertTrue(waitFor(buy, toMatch: NSPredicate(format: "label CONTAINS '4.99'")), "The buy button never showed the price: \(buy.label)")
        attachScreenshot(of: app, named: "settings-unlock")
        buy.tap()
        XCTAssertTrue(buy.waitForNonExistence(timeout: 10), "Buying didn't close the sheet")
        let unlocked = app.descendants(matching: .any)["settings-unlimited"]
        XCTAssertTrue(waitUntil(timeout: 10) { describe(unlocked).contains("Unlocked") }, "The row doesn't say Unlocked: \(describe(unlocked))")
        XCTAssertFalse(free.exists, "Free Paintings stayed once unlocked")
    }

    /// Settings › Tips is on until it is switched off (the only way to turn tips off), switches off
    /// and on, and says what it is for.
    @MainActor
    func testTipsSwitchStartsOnAndTurnsOffAndOn() throws {
        let app = openSettings()
        let toggle = app.switches["settings-tips"]
        scroll(app, to: toggle)
        for _ in 0..<3 where toggle.exists && !toggle.isHittable { app.swipeUp() }
        XCTAssertTrue(toggle.exists, "Settings has no Tips switch")
        XCTAssertEqual(toggle.value as? String, "1", "Tips doesn't start on")
        let footer = element(
            labeled: "Tips appear beside things as you reach them, one at a time. Turn them off here whenever you like.", in: app)
        XCTAssertTrue(footer.exists, "The Tips section has no footer")
        XCTAssertTrue(flip(toggle, on: false), "Tips didn't switch off: \(toggle.value ?? "")")
        attachScreenshot(of: app, named: "settings-tips-off")
        XCTAssertTrue(flip(toggle, on: true), "Tips didn't switch on: \(toggle.value ?? "")")
    }

    /// Show Tips Again turns Tips on again after the switch was turned off, and says so; turning
    /// Tips off makes it usable again.
    @MainActor
    func testShowTipsAgainTurnsTipsOn() throws {
        let app = openSettings()
        let toggle = app.switches["settings-tips"]
        let again = app.buttons["settings-show-tips-again"]
        scroll(app, to: toggle)
        for _ in 0..<3 where toggle.exists && !toggle.isHittable { app.swipeUp() }
        XCTAssertTrue(again.exists, "Settings has no Show Tips Again")
        XCTAssertEqual(again.label, "Show Tips Again")
        XCTAssertTrue(flip(toggle, on: false), "Tips didn't switch off: \(toggle.value ?? "")")
        again.tap()
        XCTAssertTrue(
            waitFor(toggle, toMatch: NSPredicate(format: "value == '1'")),
            "Show Tips Again didn't turn Tips on: \(toggle.value ?? "")")
        XCTAssertTrue(
            waitFor(again, toMatch: NSPredicate(format: "label == 'Tips Will Show Again'")),
            "Show Tips Again doesn't say that tips will show again: \(again.label)")
        attachScreenshot(of: app, named: "settings-show-tips-again")
        XCTAssertFalse(again.isEnabled, "Show Tips Again can be tapped again at once")
        XCTAssertTrue(flip(toggle, on: false), "Tips didn't switch off: \(toggle.value ?? "")")
        XCTAssertTrue(
            waitFor(again, toMatch: NSPredicate(format: "label == 'Show Tips Again' AND enabled == true")),
            "Show Tips Again stayed spent once Tips was turned off: \(again.label)")
    }

    /// The picker's label and value together: how a menu picker's row reads.
    @MainActor
    private func describe(_ element: XCUIElement) -> String {
        "\(element.label) \(element.value as? String ?? "")"
    }

    /// Waits for a menu picker's row to read `choice` (in its label or its value, see `describe`),
    /// reading the row afresh each time: a predicate expectation over it timed out on CI with the
    /// row already reading Bold (main, Oct 18), as the menu's dismissal kept the app busy.
    @MainActor
    private func shows(_ picker: XCUIElement, _ choice: String) -> Bool {
        waitUntil(timeout: 10) { describe(picker).contains(choice) }
    }

    /// The form is a lazy list: rows below the fold exist once they are scrolled into view. Each
    /// drag moves the list by four fifths of its frame, less than what shows below the navigation
    /// bar, and rests before lifting, so it can't fling past a row and leaves nothing to settle:
    /// swipes, with a second's wait for the row before each, took 138 s to reach the end of
    /// Acknowledgements on iPad (a form sheet), past every picture's credit and license text.
    @MainActor
    private func scroll(_ app: XCUIApplication, to element: XCUIElement, maxDrags: Int = 6) {
        let list = app.collectionViews.firstMatch
        let dragsList = list.exists
        var drags = 0
        while !element.exists && drags < maxDrags {
            if dragsList {
                list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9)).press(
                    forDuration: 0.05, thenDragTo: list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1)),
                    withVelocity: .default, thenHoldForDuration: 0.1)
            } else {
                app.swipeUp()
            }
            drags += 1
        }
        _ = element.waitForExistence(timeout: 2)
        // A row the list has made can still peek out under its bottom edge: it reads as hittable,
        // but a tap at its middle lands below the sheet and closes Settings (on iPad, the Music
        // list left the Making-of's row there). Short drags bring it wholly into the list.
        for _ in 0..<3 where dragsList && element.exists && element.frame.maxY > list.frame.maxY {
            list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7)).press(
                forDuration: 0.05, thenDragTo: list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)),
                withVelocity: .default, thenHoldForDuration: 0.1)
        }
    }
}
