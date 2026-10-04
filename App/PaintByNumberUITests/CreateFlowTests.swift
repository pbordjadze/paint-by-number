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
        sleep(1)
        attachScreenshot(app, named: "compare-after-drag")
        XCTAssertNotEqual(compare.value as? String, "50 percent photo", "The divider didn't follow the drag")
    }

    /// The preview's title field offers the sample's name and names the painting with what
    /// was typed. (On a retired sample, whose title doesn't move with the library's curation.)
    @MainActor
    func testTitleNamesThePainting() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "create-preview", "-demoRetiredSamples", "YES"]
        app.launch()

        let start = app.buttons["Start Painting"]
        XCTAssertTrue(start.waitForExistence(timeout: 30))
        expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: start)
        waitForExpectations(timeout: 60)

        let title = app.textFields["painting-title"]
        XCTAssertTrue(title.exists, "The preview has no title field")
        XCTAssertEqual(title.placeholderValue, "Parrots")
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
        title.typeText("Jungle Birds\n")
        XCTAssertEqual(title.value as? String, "Jungle Birds")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "create-title-typed"
        shot.lifetime = .keepAlways
        add(shot)

        start.tap()
        XCTAssertTrue(
            app.staticTexts["Jungle Birds, 0 percent painted"].waitForExistence(timeout: 90),
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
        attachScreenshot(app, named: "create-custom-settings")

        reset.tap()
        let restored = NSPredicate(format: "value == %@", suggested)
        XCTAssertEqual(
            XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: restored, object: detail)], timeout: 10), .completed,
            "Reset didn't bring Detail back to \(suggested)")
        XCTAssertEqual(chip.value as? String, "Suggested for this photo")
        XCTAssertFalse(reset.exists, "Reset is still offered after resetting")
        attachScreenshot(app, named: "create-suggested-settings")
    }

    /// The inline picker is the page's primary content and no scroll view contains it: its pan
    /// runs out of process and can't be arbitrated against an in-process ancestor's pan.
    @MainActor
    func testLibraryFillsTheScreenOutsideAnyScrollView() throws {
        let (app, picker) = launchToPicker("create")
        XCTAssertTrue(picker.exists, "No library picker")
        attachTree(app, named: "library-layout-tree")

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
        }
        attachScreenshot(app, named: "library-layout")
    }

    /// A single tap on a library photo opens its preview; after going back, the same photo can
    /// be picked again (the selection is reset after each pick).
    @MainActor
    func testLibraryPhotoOpensPreviewAndCanBePickedAgain() throws {
        let (app, picker) = launchToPicker("create")
        XCTAssertTrue(picker.exists, "No library picker")

        let start = app.buttons["Start Painting"]
        let opened = try pickFirstInlinePhoto(app, picker: picker, opens: start)
        attachScreenshot(app, named: "library-photo-picked")
        XCTAssertTrue(opened, "Picking a library photo didn't open its preview")
        guard opened else { return }

        let back = app.navigationBars.buttons.matching(NSPredicate(format: "label IN {'New Painting', 'Back'}")).firstMatch
        guard back.waitForExistence(timeout: 10) else {
            attachTree(app, named: "preview-back-tree")
            XCTFail("No back button on the preview")
            return
        }
        back.tap()
        let returned = poll(timeout: 10) { !start.exists }
        XCTAssertTrue(returned, "Back didn't return to the photo step")
        XCTAssertTrue(picker.waitForExistence(timeout: 20))

        let reopened = try pickFirstInlinePhoto(app, picker: picker, opens: start)
        attachScreenshot(app, named: "library-photo-picked-again")
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
            XCTAssertTrue(samples.isSelected)
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
        attachScreenshot(app, named: "samples")

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
        attachScreenshot(app, named: "samples-largest-text")
        let window = app.windows.firstMatch.frame
        XCTAssertGreaterThanOrEqual(first.frame.minX, window.minX - 1, "The first sample runs off the screen")
        XCTAssertLessThanOrEqual(first.frame.maxX, window.maxX + 1, "The first sample runs off the screen")
    }

    /// "Browse All…" presents the full system picker, which dismisses back to the create flow.
    @MainActor
    func testBrowseAllPresentsSystemPickerAndDismisses() throws {
        try skipOnPhoneSimulator()
        let (app, picker) = launchToPicker("create")
        XCTAssertTrue(picker.exists, "No library picker")
        let sheet = settledSheetDetector(app)
        XCTAssertNil(sheet.dismissFrame)

        guard let cancel = openBrowseAll(app, sheet: sheet) else { return }
        tap(app, at: cancel)
        let dismissed = poll(timeout: 15) { sheet.dismissFrame == nil }
        if !dismissed { attachTree(app, named: "browse-all-dismiss-tree") }
        XCTAssertTrue(dismissed, "The system picker didn't dismiss")
        XCTAssertTrue(picker.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["Start Painting"].exists)
    }

    /// A photo picked in the full system picker opens its preview: the push happens while the
    /// sheet dismisses, which must not stall either transition.
    @MainActor
    func testBrowseAllPickOpensPreview() throws {
        let (app, picker) = launchToPicker("create")
        XCTAssertTrue(picker.exists, "No library picker")
        let sheet = settledSheetDetector(app)

        guard openBrowseAll(app, sheet: sheet) != nil else { return }
        // The sheet can open on a blank "Loading…" page whose Close sits left of the loaded
        // sheet's Cancel: wait for its photos, then read the bar of the sheet they are in.
        let sheetPhotosShown = poll(timeout: 30) {
            app.images.matching(photoPredicate).count > picker.images.matching(photoPredicate).count
        }
        if sheetPhotosShown { sleep(1) }
        guard sheetPhotosShown, let cancel = sheet.dismissFrame else {
            attachTree(app, named: "browse-all-loading-tree")
            XCTFail("The system picker showed no photos")
            return
        }
        // The sheet's grid lies below its top bar. Sheets are centred horizontally, and the
        // Cancel button sits at the sheet's leading edge, so mirroring its inset bounds an area
        // inside the sheet on both device classes (the sheet reaches at least as far down).
        let window = app.windows.firstMatch.frame
        let bar = cancel
        let inset = max(0, bar.minX - window.minX - 20)
        let sheetTop = max(window.minY, bar.minY - 12)
        let grid = CGRect(
            x: window.minX + inset, y: bar.maxY + 8,
            width: window.width - 2 * inset, height: window.maxY - (sheetTop - window.minY) - bar.maxY - 8)
        try tapFirstPhoto(
            app, in: grid, origin: CGPoint(x: window.minX + inset, y: sheetTop), excluding: picker)

        let start = app.buttons["Start Painting"]
        let opened = start.waitForExistence(timeout: 60)
        attachScreenshot(app, named: "browse-all-picked")
        if !opened { attachTree(app, named: "browse-all-pick-tree") }
        XCTAssertTrue(opened, "Picking a photo in Browse All didn't open its preview")
        XCTAssertTrue(poll(timeout: 15) { sheet.dismissFrame == nil }, "The system picker stayed up after a pick")
    }

    // MARK: - Helpers

    /// On the iPhone simulator the system photo picker ignores synthesized taps on its photos
    /// and its sheet's Cancel (screen recordings show the taps landing on them; the same flows
    /// pass on iPad). These paths are verified on iPad and on a device.
    @MainActor
    private func skipOnPhoneSimulator() throws {
        try XCTSkipIf(!isPad, "The system photo picker ignores synthesized taps on the iPhone simulator")
    }

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

    /// A sheet detector made once the inline picker has loaded (its photos are up, or it had
    /// as long as the demo gives it): a Cancel/Close its bar brought in after the snapshot would
    /// otherwise pass for the sheet's.
    @MainActor
    private func settledSheetDetector(_ app: XCUIApplication) -> SheetDetector {
        _ = app.images.matching(photoPredicate).firstMatch.waitForExistence(timeout: 10)
        sleep(1)
        return SheetDetector(app)
    }

    /// Taps "Browse All…" and returns the frame of the presented sheet's dismiss button, or
    /// fails the test (with diagnostics) and returns nil when no sheet appears.
    @MainActor
    private func openBrowseAll(_ app: XCUIApplication, sheet: SheetDetector) -> CGRect? {
        app.buttons["Browse All…"].tap()
        let shown = poll(timeout: 15) { sheet.dismissFrame != nil }
        // Read again once the sheet has slid into place: a frame read mid-animation misses.
        if shown { sleep(1) }
        attachScreenshot(app, named: "browse-all")
        guard shown, let cancel = sheet.dismissFrame else {
            attachTree(app, named: "browse-all-tree")
            XCTFail("Browse All didn't present the system picker")
            return nil
        }
        return cancel
    }

    /// Picks the inline picker's first photo and waits for `opens`. On a phone the picker's
    /// accessibility tree can lag its screen (it listed a banner that wasn't showing), so when
    /// the tap by reported frames opens nothing, it taps where the first photo sits.
    @MainActor
    private func pickFirstInlinePhoto(_ app: XCUIApplication, picker: XCUIElement, opens: XCUIElement) throws -> Bool {
        try tapFirstPhoto(app, in: picker.frame)
        if opens.waitForExistence(timeout: 15) { return true }
        // What the tap did: a selection badge without a preview says it reached the picker.
        attachScreenshot(app, named: "inline-tap-missed")
        attachTree(app, named: "inline-tap-missed-tree")
        picker.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.25)).tap()
        return opens.waitForExistence(timeout: 60)
    }

    /// Taps the first library photo that is fully visible inside `area` (window coordinates).
    /// The picker runs out of process and its photos may report frames in its own coordinates
    /// (relative to `origin`, the picker's top-left corner in the window) rather than the
    /// window's. For the inline picker (no `origin`) the grid's left edge tells which; for a
    /// sheet, a photo that passes XCUITest's hit test is in window coordinates, otherwise the
    /// picker-relative reading is used if it fits, else the reported frame. Photos of the
    /// `excluding` picker are skipped, matched by the frames they report now: frames read
    /// earlier miss once its grid has moved, and a missed one passed for a sheet photo.
    @MainActor
    private func tapFirstPhoto(
        _ app: XCUIApplication, in area: CGRect, origin: CGPoint? = nil, excluding other: XCUIElement? = nil
    ) throws {
        let photos = app.images.matching(photoPredicate)
        guard photos.firstMatch.waitForExistence(timeout: 20) else {
            attachTree(app, named: "library-picker-tree")
            throw XCTSkip("The library picker's photos aren't reachable from the UI test")
        }
        let excluding = other?.images.matching(photoPredicate).allElementsBoundByIndex.map { $0.frame } ?? []
        // Thumbnails only (the picker's bar may carry small glyphs with similar labels).
        let thumbnails = photos.allElementsBoundByIndex.prefix(60)
            .map { (element: $0, frame: $0.frame) }
            .filter { $0.frame.width >= 40 && $0.frame.height >= 40 && !excluding.contains($0.frame) }
        // When `area` is the picker itself, a grid in the picker's own coordinates starts at
        // x ≈ 0, left of the picker in the window. (Hit testing misled here: on the phone the
        // photos failed it in window coordinates, which sent the tap below the grid.)
        let inlineRelative: Bool? = origin == nil
            ? (thumbnails.map { $0.frame.minX }.min() ?? 0) < area.minX - 1 : nil
        let origin = origin ?? area.origin
        var target: CGRect?
        for (photo, frame) in thumbnails {
            let relative = frame.offsetBy(dx: origin.x, dy: origin.y)
            if let inlineRelative {
                let candidate = inlineRelative ? relative : frame
                if area.contains(candidate) { target = candidate }
            } else if area.contains(frame), photo.isHittable {
                target = frame
            } else if area.contains(relative) {
                target = relative
            } else if area.contains(frame) {
                // Hit testing can fail where the window frame is right (the iPad sheet's photos).
                target = frame
            }
            if target != nil { break }
        }
        guard let target else {
            attachTree(app, named: "library-picker-tree")
            throw XCTSkip("No library photo is fully visible inside the picker")
        }
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: target.midX, dy: target.midY)).tap()
    }

    /// Polls a condition on the UI (queries are synchronous, so the main thread may block).
    @MainActor
    private func poll(timeout: TimeInterval, until condition: () -> Bool) -> Bool {
        let deadline = Date.now.addingTimeInterval(timeout)
        while !condition() {
            guard Date.now < deadline else { return false }
            usleep(250_000)
        }
        return true
    }

    @MainActor
    private func attachTree(_ app: XCUIApplication, named name: String) {
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = name
        tree.lifetime = .keepAlways
        add(tree)
    }

    /// Taps the middle of `frame` (window coordinates).
    @MainActor
    private func tap(_ app: XCUIApplication, at frame: CGRect) {
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: frame.midX, dy: frame.midY)).tap()
    }

    @MainActor
    private func attachScreenshot(_ app: XCUIApplication, named name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}

/// Finds the system picker sheet by an on-screen Cancel/Close button that wasn't on the page
/// when the detector was made: the page keeps its own Close, the inline picker's bar may bring
/// its own, and a modal sheet may hide the page from accessibility, so neither names nor counts
/// identify it. (On iPad the form sheet overlaps the inline picker, so position can't either.)
@MainActor
private struct SheetDetector {
    private let app: XCUIApplication
    private let existing: [CGRect]

    init(_ app: XCUIApplication) {
        self.app = app
        existing = Self.dismissFrames(in: app)
    }

    /// The frame of the sheet's dismiss button, nil while no sheet is up: the topmost new
    /// one (the sheet's bar sits above the Close of its "Private Access" banner).
    var dismissFrame: CGRect? {
        Self.dismissFrames(in: app)
            .filter { frame in !existing.contains { $0.insetBy(dx: -2, dy: -2).contains(frame) } }
            .min { $0.minY < $1.minY }
    }

    /// Enabled Cancel/Close buttons centred on screen. Each is read through its own snapshot,
    /// which throws when the button is gone: reading a listed button's properties directly
    /// races the sheet's animation and fails the test outright ("no matches for element at
    /// index 1"). A snapshot of the whole app didn't include the system picker's sheet on CI.
    private static func dismissFrames(in app: XCUIApplication) -> [CGRect] {
        let screen = app.windows.firstMatch.frame
        let buttons = app.buttons.matching(NSPredicate(format: "label IN {'Cancel', 'Close'}"))
        return buttons.allElementsBoundByIndex.compactMap { button in
            guard let element = try? button.snapshot(), element.isEnabled else { return nil }
            let frame = element.frame
            return !frame.isEmpty && screen.contains(CGPoint(x: frame.midX, y: frame.midY)) ? frame : nil
        }
    }
}
