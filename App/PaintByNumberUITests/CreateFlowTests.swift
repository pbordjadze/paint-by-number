import UIKit
import XCTest

final class CreateFlowTests: XCTestCase {
    /// The before/after divider follows a drag that starts on its knob.
    @MainActor
    func testCompareDividerFollowsDrag() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "create-preview"]
        app.launch()

        let start = app.buttons["Start Painting"]
        XCTAssertTrue(start.waitForExistence(timeout: 30))
        // The divider appears with the first template.
        expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: start)
        waitForExpectations(timeout: 60)

        let compare = app.descendants(matching: .any)["Comparison of photo and template"]
        XCTAssertTrue(compare.exists)
        XCTAssertEqual(compare.value as? String, "50 percent photo")
        compare.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.1, thenDragTo: compare.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5)))
        let moved = waitFor(compare, toMatch: NSPredicate(format: "value != nil AND value != %@", "50 percent photo"))
        attachScreenshot(of: app, named: "compare-after-drag")
        XCTAssertTrue(moved, "The divider didn't follow the drag")

        // A double tap zooms both layers in; a drag then pans them, leaving the divider where it
        // is; another double tap fits them again.
        let split = try XCTUnwrap(compare.value as? String)
        compare.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.3)).doubleTap()
        let zoomed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value CONTAINS %@", "zoomed"), object: compare)
        XCTAssertEqual(XCTWaiter.wait(for: [zoomed], timeout: 5), .completed, "A double tap didn't zoom in")
        compare.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.7))
            .press(forDuration: 0.1, thenDragTo: compare.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)))
        attachScreenshot(of: app, named: "compare-zoomed")
        compare.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.3)).doubleTap()
        let fitted = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", split), object: compare)
        XCTAssertEqual(
            XCTWaiter.wait(for: [fitted], timeout: 5), .completed,
            "Panning moved the divider, or a second double tap didn't fit the layers again")
    }

    /// The preview's title field offers the sample's name and names the painting with what
    /// was typed. (On the demo's fixed pictures, whose titles don't move with the library's order.)
    @MainActor
    func testTitleNamesThePainting() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "create-preview", "-demoFixedPictures", "YES"]
        app.launch()

        let start = app.buttons["Start Painting"]
        XCTAssertTrue(start.waitForExistence(timeout: 30))
        expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: start)
        waitForExpectations(timeout: 60)

        let title = app.textFields["painting-title"]
        XCTAssertTrue(title.exists, "The preview has no title field")
        XCTAssertEqual(title.placeholderValue, "The Great Wave")
        // The first tap can land while the preview is still settling: type only once focused.
        let focused = NSPredicate(format: "hasKeyboardFocus == true")
        let unfocusedFrame = title.frame
        for _ in 0..<3 where !focused.evaluate(with: title) {
            title.tap()
            _ = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: focused, object: title)], timeout: 3)
        }
        // The keyboard shrinks the view; the layout must not switch (stacked ↔ side by side).
        XCTAssertEqual(title.frame.minX, unfocusedFrame.minX, accuracy: 1, "The preview changed layout when the keyboard showed")
        XCTAssertEqual(title.frame.width, unfocusedFrame.width, accuracy: 1, "The preview changed layout when the keyboard showed")
        title.typeText("Big Wave\n")
        XCTAssertTrue(waitFor(title, toMatch: NSPredicate(format: "value == %@", "Big Wave")), "The title reads \(title.value ?? "")")
        attachScreenshot(of: app, named: "create-title-typed")

        start.tap()
        XCTAssertTrue(
            app.staticTexts["Big Wave, 0 percent painted"].waitForExistence(timeout: 90),
            "The painting didn't open with the typed title")
    }

    /// A sample opens on settings suggested for it; moving Detail makes them custom, and
    /// Reset to Suggested brings the slider back.
    @MainActor
    func testSuggestedSettingsChipAndReset() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "create-preview"]
        app.launch()

        let start = app.buttons["Start Painting"]
        XCTAssertTrue(start.waitForExistence(timeout: 30))
        // Start waits for the suggestion.
        expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: start)
        waitForExpectations(timeout: 90)

        let chip = app.descendants(matching: .any)["settings-origin"]
        XCTAssertTrue(chip.waitForExistence(timeout: 10), "The preview has no settings chip")
        XCTAssertEqual(chip.value as? String, "Suggested for this photo")
        XCTAssertEqual(chip.label, "Settings")

        let detail = app.sliders["Detail"]
        XCTAssertTrue(detail.exists, "No Detail slider")
        // The book's lines on a slider of their own.
        XCTAssertEqual(app.sliders["Lines"].value as? String, "Balanced")
        XCTAssertTrue(detail.isEnabled, "The Detail slider still waits for the suggestion")
        let suggested = try XCTUnwrap(detail.value as? String)
        // Far from the suggestion, so the slider's word changes.
        let target: CGFloat = ["Simple", "Moderate"].contains(suggested) ? 0.95 : 0.05
        detail.adjust(toNormalizedSliderPosition: target)

        let reset = app.buttons["settings-origin"]
        XCTAssertTrue(reset.waitForExistence(timeout: 10), "Moving Detail didn't offer Reset to Suggested")
        XCTAssertEqual(reset.label, "Reset to Suggested")
        XCTAssertEqual(reset.value as? String, "Custom")
        XCTAssertNotEqual(detail.value as? String, suggested)
        attachScreenshot(of: app, named: "create-custom-settings")

        reset.tap()
        let restored = NSPredicate(format: "value == %@", suggested)
        XCTAssertEqual(
            XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: restored, object: detail)], timeout: 10), .completed,
            "Reset didn't bring Detail back to \(suggested)")
        XCTAssertEqual(chip.value as? String, "Suggested for this photo")
        XCTAssertFalse(reset.exists, "Reset is still offered after resetting")
        attachScreenshot(of: app, named: "create-suggested-settings")
    }

    /// The inline picker is the page's primary content and no scroll view contains it: its pan
    /// runs out of process and can't be arbitrated against an in-process ancestor's pan.
    @MainActor
    func testLibraryFillsTheScreenOutsideAnyScrollView() throws {
        let (app, picker) = launchToPicker("create")
        XCTAssertTrue(picker.exists, "No library picker")
        attachTree(of: app, named: "library-layout-tree")

        XCTAssertEqual(app.scrollViews.containing(pickerPredicate).count, 0, "The library picker is inside a scroll view")
        let window = app.windows.firstMatch.frame
        XCTAssertGreaterThanOrEqual(picker.frame.height, 0.6 * window.height, "The library picker doesn't fill the page")
        if isPad {
            XCTAssertFalse(sourceControl(app).exists, "Wide windows show photos and samples side by side")
            let share = picker.frame.width / window.width
            XCTAssertTrue((0.5...0.68).contains(share), "The picker takes \(share) of the width")
            let sample = firstSample(app)
            XCTAssertTrue(sample.exists)
            XCTAssertGreaterThanOrEqual(sample.frame.minX, picker.frame.maxX, "Samples should sit beside the picker")
        } else {
            XCTAssertTrue(sourceControl(app).exists)
            XCTAssertTrue(sourceControl(app).buttons["Photos"].isSelected)
            // Edge to edge: inset from the left and the top, the picker's grid ignores taps on
            // iPhone for its first seconds.
            XCTAssertEqual(picker.frame.minX, window.minX, accuracy: 1, "The picker isn't flush with the window's left edge")
            XCTAssertEqual(picker.frame.width, window.width, accuracy: 1, "The picker doesn't span the window")
        }
        attachScreenshot(of: app, named: "library-layout")
    }

    /// A single tap on a library photo opens its preview; after going back, the same photo can
    /// be picked again (the selection is reset after each pick).
    @MainActor
    func testLibraryPhotoOpensPreviewAndCanBePickedAgain() throws {
        let (app, picker) = launchToPicker("create")
        XCTAssertTrue(picker.exists, "No library picker")

        let start = app.buttons["Start Painting"]
        let opened = try pickFirstInlinePhoto(app, picker: picker, opens: start)
        attachScreenshot(of: app, named: "library-photo-picked")
        XCTAssertTrue(opened, "Picking a library photo didn't open its preview")
        guard opened else { return }
        // Back once the photo's settings are chosen: until then its models and candidates keep
        // every core busy, and on CI's simulators a Back tapped then was lost twice (the preview
        // stayed, finishing its suggestion).
        XCTAssertTrue(
            waitFor(start, toMatch: NSPredicate(format: "isEnabled == true"), timeout: 120),
            "The preview never finished choosing its settings")

        // By the system's identifier: the gallery's New Painting button, under the create flow,
        // carries the back button's label too.
        let back = app.navigationBars.buttons.matching(identifier: "BackButton").firstMatch
        guard back.waitForExistence(timeout: 10) else {
            attachTree(of: app, named: "preview-back-tree")
            XCTFail("No back button on the preview")
            return
        }
        back.tap()
        let returned = waitUntil(timeout: 30) { !start.exists }
        if !returned { attachTree(of: app, named: "preview-back-missed-tree") }
        XCTAssertTrue(returned, "Back didn't return to the photo step")
        XCTAssertTrue(picker.waitForExistence(timeout: 20))

        let reopened = try pickFirstInlinePhoto(app, picker: picker, opens: start)
        attachScreenshot(of: app, named: "library-photo-picked-again")
        XCTAssertTrue(reopened, "The same photo couldn't be picked a second time")
    }

    /// Samples (behind a segment on compact widths, beside the picker on wide ones) sit in a
    /// Paintings and a Photographs section, tell VoiceOver who made them, and open their preview.
    @MainActor
    func testSamplesOpenPreview() throws {
        let (app, picker) = launchToPicker("create")
        XCTAssertTrue(picker.exists, "No library picker")
        let pickerHeight = picker.frame.height
        let samples = sourceControl(app).buttons["Samples"]
        if !isPad {
            XCTAssertTrue(samples.waitForExistence(timeout: 10))
            samples.tap()
            XCTAssertTrue(waitFor(samples, toMatch: NSPredicate(format: "isSelected == true")), "Samples didn't become selected")
        }
        let first = firstSample(app)
        XCTAssertTrue(first.waitForExistence(timeout: 10))
        XCTAssertTrue(first.isHittable)
        for section in ["Paintings", "Photographs"] {
            XCTAssertTrue(app.staticTexts[section].exists, "The samples have no \(section) section")
        }
        let paintings = app.staticTexts["Paintings"]
        XCTAssertGreaterThan(first.frame.minY, paintings.frame.maxY, "The first sample isn't under the Paintings title")
        // "Sample: <title>, <creator>"
        XCTAssertTrue(first.label.dropFirst("Sample: ".count).contains(", "), "The sample's label doesn't name its creator: \(first.label)")
        attachScreenshot(of: app, named: "samples")

        if !isPad {
            // Back to the picker at full height, then to the samples again.
            sourceControl(app).buttons["Photos"].tap()
            XCTAssertTrue(picker.waitForExistence(timeout: 10))
            XCTAssertEqual(picker.frame.height, pickerHeight, accuracy: 1)
            samples.tap()
            XCTAssertTrue(first.waitForExistence(timeout: 10))
        }
        first.tap()
        XCTAssertTrue(app.buttons["Start Painting"].waitForExistence(timeout: 60), "Picking a sample didn't open its preview")
    }

    /// At the largest text size the sample tiles widen for their captions (one column) but stay
    /// inside the window.
    @MainActor
    func testSampleTilesFitAtTheLargestTextSize() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-demo", "create-samples", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
        ]
        app.launch()
        let ok = app.buttons["OK"]
        if ok.waitForExistence(timeout: 5) { ok.tap() }
        let first = firstSample(app)
        XCTAssertTrue(first.waitForExistence(timeout: 20), "The Samples pane shows no sample")
        sleep(1)
        attachScreenshot(of: app, named: "samples-largest-text")
        let window = app.windows.firstMatch.frame
        XCTAssertGreaterThanOrEqual(first.frame.minX, window.minX - 1, "The first sample runs off the screen")
        XCTAssertLessThanOrEqual(first.frame.maxX, window.maxX + 1, "The first sample runs off the screen")
    }

    // MARK: - Helpers

    private var pickerPredicate: NSPredicate { NSPredicate(format: "identifier == 'library-picker'") }

    /// Library photos as the picker exposes them to UI tests.
    private var photoPredicate: NSPredicate { NSPredicate(format: "label BEGINSWITH 'Photo'") }

    /// Portrait CI devices: the iPad is wide (1032 pt), the iPhone compact (402 pt).
    @MainActor
    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    /// Launches a create scenario and waits for the library picker (not asserted here, so each
    /// test reports its own failure).
    @MainActor
    private func launchToPicker(_ scenario: String) -> (XCUIApplication, XCUIElement) {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", scenario]
        app.launch()
        let picker = app.descendants(matching: .any).matching(pickerPredicate).firstMatch
        _ = picker.waitForExistence(timeout: 20)
        // First use may explain limited library access. It is up by the time the picker is, so
        // a short wait suffices; the usual case, no alert, then costs little per test.
        let ok = app.buttons["OK"]
        if ok.waitForExistence(timeout: 2) { ok.tap() }
        return (app, picker)
    }

    /// The Photos/Samples segmented control, whatever element type carries its identifier.
    /// Segments are always looked up inside it: the picker has its own Photos/Albums switcher.
    @MainActor
    private func sourceControl(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "photo-source").firstMatch
    }

    /// The first sample tile, the library's first painting, whatever the library's curation.
    @MainActor
    private func firstSample(_ app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Sample: '")).firstMatch
    }

    /// Picks the inline picker's first photo and waits for `opens`. A tap that opens nothing is
    /// kept as a screenshot and tree (a selection badge without a preview says it reached the
    /// picker) and tried once more at the same point: a picker inset from the window's left and
    /// top edge takes its first seconds to accept taps on iPhone; the edge-to-edge layout avoids
    /// that, and the retry stays as a safety net.
    @MainActor
    private func pickFirstInlinePhoto(_ app: XCUIApplication, picker: XCUIElement, opens: XCUIElement) throws -> Bool {
        let point = try tapFirstPhoto(app, in: picker.frame)
        if opens.waitForExistence(timeout: 15) { return true }
        attachScreenshot(of: app, named: "inline-tap-missed")
        attachTree(of: app, named: "inline-tap-missed-tree")
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: point.x, dy: point.y)).tap()
        return opens.waitForExistence(timeout: 30)
    }

    /// Taps the first library photo that is fully visible inside `area` (the inline picker's
    /// frame, window coordinates) and returns the point tapped.
    /// The picker runs out of process and its photos may report frames in its own coordinates
    /// (relative to its top-left corner) rather than the window's: the grid's left edge tells which.
    @MainActor
    private func tapFirstPhoto(_ app: XCUIApplication, in area: CGRect) throws -> CGPoint {
        let photos = app.images.matching(photoPredicate)
        guard photos.firstMatch.waitForExistence(timeout: 20) else {
            attachTree(of: app, named: "library-picker-tree")
            throw XCTSkip("The library picker's photos aren't reachable from the UI test")
        }
        // Thumbnails only (the picker's bar may carry small glyphs with similar labels).
        let frames = photos.allElementsBoundByIndex.prefix(60).map { $0.frame }
            .filter { $0.width >= 40 && $0.height >= 40 }
        // A grid in the picker's own coordinates starts at x ≈ 0, left of the picker in the
        // window. (Hit testing misled here: on the phone the photos failed it in window
        // coordinates, which sent the tap below the grid.)
        let relative = (frames.map { $0.minX }.min() ?? 0) < area.minX - 1
        let candidates = frames.map { relative ? $0.offsetBy(dx: area.minX, dy: area.minY) : $0 }
        guard let target = candidates.first(where: { area.contains($0) }) else {
            attachTree(of: app, named: "library-picker-tree")
            throw XCTSkip("No library photo is fully visible inside the picker")
        }
        let point = CGPoint(x: target.midX, y: target.midY)
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: point.x, dy: point.y)).tap()
        return point
    }
}
