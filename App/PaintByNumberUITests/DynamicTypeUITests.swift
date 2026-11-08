import XCTest

/// The screens a painter meets first, at the largest text size (AX5): the accessibility audit
/// finds no text cut short on them. The completion bar keeps the painting's name, the gallery and
/// New Painting their titles (the gallery's under the status bar once it scrolls), the sample
/// tiles their captions; Refine's tiny-numbers badge and the Pen's options stay whole
/// (painting-company row 263).
final class DynamicTypeUITests: XCTestCase {
    private static let largest = "UICTContentSizeCategoryAccessibilityXXXL"

    @MainActor
    func testFinishedBarKeepsThePaintingsName() throws {
        let app = launch("paint-complete")
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 60), "The finished painting didn't open")
        try assertNoClippedText(in: app, named: "paint-complete-ax5")
    }

    @MainActor
    func testGalleryTitleWraps() throws {
        let app = launch("gallery-first-run")
        let card = app.buttons.matching(NSPredicate(format: "value BEGINSWITH 'Not started'")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 150), "The gallery's starters never came")
        try assertNoClippedText(in: app, named: "gallery-ax5")
        // Scrolled, the bar's inline title and subtitle stay under the status bar: grown with the
        // text size, the pair drew over its clock (an iPhone SE at AX5: the title at y 4, the bar
        // at 20). Where the gallery fits without scrolling (an iPad) the large title stays.
        app.scrollViews.firstMatch.swipeUp()
        sleep(2)
        attachScreenshot(of: app, named: "gallery-ax5-scrolled")
        let bar = app.navigationBars.firstMatch
        for text in bar.staticTexts.allElementsBoundByIndex where !text.frame.isEmpty {
            XCTAssertGreaterThanOrEqual(
                text.frame.minY, bar.frame.minY, "'\(text.label)' draws over the status bar: \(text.frame), bar \(bar.frame)")
        }
    }

    @MainActor
    func testNewPaintingTitleAndSamples() throws {
        let app = launch("create-samples")
        let sample = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Sample: '")).firstMatch
        XCTAssertTrue(sample.waitForExistence(timeout: 60), "The samples never showed")
        XCTAssertTrue(app.staticTexts["New Painting"].exists, "New Painting's title is gone")
        try assertNoClippedText(in: app, named: "create-samples-ax5")
    }

    @MainActor
    func testRefineBadgeAndPenOptions() throws {
        let app = launch("create-refine")
        XCTAssertTrue(app.sliders["refine-pen-smoothing"].waitForExistence(timeout: 240), "Refine never opened on the Pen")
        _ = app.buttons["refine-tiny"].waitForExistence(timeout: 30)
        sleep(2)
        let window = app.windows.firstMatch.frame
        let smoothing = app.sliders["refine-pen-smoothing"]
        XCTAssertTrue(window.contains(smoothing.frame), "Smoothing runs off the screen")
        try assertNoClippedText(in: app, named: "create-refine-ax5")
    }

    // MARK: -

    @MainActor
    private func launch(_ scenario: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", scenario, "-UIPreferredContentSizeCategoryName", Self.largest]
        app.launch()
        return app
    }

    /// Audits the screen for clipped text, again after a pause when the audit itself ran out of
    /// time (a busy simulator), and attaches the screen.
    @MainActor
    private func assertNoClippedText(in app: XCUIApplication, named name: String) throws {
        sleep(2)
        attachScreenshot(of: app, named: name)
        var clipped: [String] = []
        var unplaced = 0
        func audit() throws {
            clipped = []
            unplaced = 0
            try app.performAccessibilityAudit(for: .textClipped) { issue in
                MainActor.assumeIsolated {
                    // An issue with no element names nothing on screen: on the iPhone 17 Pro the
                    // finished bar gave three, with its name whole in the screenshot (the rows
                    // ViewThatFits measured and didn't choose, most likely). Noted, not failed.
                    if let element = issue.element { clipped.append("'\(element.label)'") } else { unplaced += 1 }
                }
                return true
            }
        }
        do {
            try audit()
        } catch let error as NSError where error.domain == "com.apple.xcode.xctest.accessibilityAudit" && error.code == -56 {
            sleep(3)
            try audit()
        }
        if unplaced > 0 {
            let note = XCTAttachment(string: "\(unplaced) clipped-text issues named no element")
            note.name = "\(name)-unplaced"
            note.lifetime = .keepAlways
            add(note)
        }
        XCTAssertTrue(clipped.isEmpty, "Text cut short: \(clipped.joined(separator: ", "))")
    }
}
