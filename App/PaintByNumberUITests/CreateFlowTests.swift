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

        let compare = app.descendants(matching: .any)["Comparison of photo and painting"]
        XCTAssertTrue(compare.exists)
        // The divider sweeps in from the trailing edge with the first picture and rests in the middle.
        XCTAssertTrue(
            waitFor(compare, toMatch: NSPredicate(format: "value == %@", "50 percent photo"), timeout: 5),
            "The divider didn't come to rest in the middle: \(compare.value ?? "")")
        compare.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.1, thenDragTo: compare.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5)))
        let moved = waitFor(compare, toMatch: NSPredicate(format: "value != nil AND value != %@", "50 percent photo"))
        attachScreenshot(of: app, named: "compare-after-drag")
        XCTAssertTrue(moved, "The divider didn't follow the drag")

        // A double tap zooms both layers in; a drag then pans them, leaving the divider where it
        // is; another double tap fits them again.
        let split = try XCTUnwrap(compare.value as? String)
        let zoom = {
            compare.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.3)).doubleTap()
        }
        let zoomed = NSPredicate(format: "value CONTAINS %@", "zoomed")
        zoom()
        // CI sometimes loses the first double tap, leaving the divider unzoomed. Recheck before
        // retrying once: a late zoom must not be double-tapped back to fit.
        if !waitFor(compare, toMatch: zoomed) {
            retapIfLost("comparison-zoom") {
                if !zoomed.evaluate(with: compare) { zoom() }
            }
        }
        XCTAssertTrue(waitFor(compare, toMatch: zoomed), "A double tap didn't zoom in")
        compare.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.7))
            .press(forDuration: 0.1, thenDragTo: compare.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)))
        attachScreenshot(of: app, named: "compare-zoomed")
        compare.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.3)).doubleTap()
        let fitted = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", split), object: compare)
        XCTAssertEqual(
            XCTWaiter.wait(for: [fitted], timeout: 5), .completed,
            "Panning moved the divider, or a second double tap didn't fit the layers again")
    }

    /// Start Painting tapped before the painting is made says Preparing…, and the painting opens by
    /// itself once it is (SideStore and Debug builds). `-slowFullResolution` keeps the full
    /// resolution waiting, as a phone's does.
    @MainActor
    func testStartTappedEarlyStartsByItself() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "create-preview", "-demoFixedPictures", "YES", "-slowFullResolution", "20"]
        app.launch()

        let start = app.buttons["Start Painting"]
        XCTAssertTrue(start.waitForExistence(timeout: 30))
        XCTAssertTrue(waitFor(start, toMatch: NSPredicate(format: "isEnabled == true"), timeout: 90), "Start Painting never enabled")
        start.tap()
        XCTAssertTrue(
            waitFor(start, toMatch: NSPredicate(format: "value == %@", "Preparing…"), timeout: 5),
            "Start tapped before the painting was made doesn't say Preparing…")
        attachScreenshot(of: app, named: "create-start-preparing")
        XCTAssertTrue(
            app.staticTexts["The Great Wave, 0 percent painted"].waitForExistence(timeout: 180),
            "The painting didn't open by itself once it was made")
    }

    /// A slider touched while an early Start waits calls it off: Start Painting comes back, and no
    /// painting opens.
    @MainActor
    func testASliderCallsOffAnEarlyStart() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "create-preview", "-demoFixedPictures", "YES", "-slowFullResolution", "30"]
        app.launch()

        let start = app.buttons["Start Painting"]
        XCTAssertTrue(start.waitForExistence(timeout: 30))
        XCTAssertTrue(waitFor(start, toMatch: NSPredicate(format: "isEnabled == true"), timeout: 90), "Start Painting never enabled")
        // The suggestion first, so the slider moved is the painter's and not under way.
        XCTAssertTrue(waitForSuggestion(in: app), "The preview never chose its settings")
        start.tap()
        XCTAssertTrue(
            waitFor(start, toMatch: NSPredicate(format: "value == %@", "Preparing…"), timeout: 5),
            "Start tapped before the painting was made doesn't say Preparing…")
        let detail = settingSlider("Detail", in: app)
        XCTAssertTrue(detail.waitForExistence(timeout: 10), "The preview has no Detail slider")
        detail.adjust(toNormalizedSliderPosition: 0.9)
        XCTAssertTrue(
            waitFor(start, toMatch: NSPredicate(format: "isEnabled == true AND value != %@", "Preparing…"), timeout: 10),
            "Touching a slider didn't call the early Start off")
        sleep(5)
        XCTAssertFalse(app.staticTexts["The Great Wave, 0 percent painted"].exists, "A called-off Start opened the painting")
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
        // Start works from the first draft: what is timed below is a start from settings chosen.
        XCTAssertTrue(waitForSuggestion(in: app), "The preview never chose its settings")

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
        XCTAssertTrue(waitForSuggestion(in: app), "The preview has no settings chip")
        XCTAssertEqual(chip.value as? String, "Suggested for this picture")
        XCTAssertEqual(chip.label, "Settings")

        // The book's lines on a slider of their own.
        XCTAssertEqual(settingSlider("Lines", in: app).value as? String, "Balanced")
        let detail = settingSlider("Detail", in: app)
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
        attachScreenshot(of: app, named: "create-custom-settings")

        reset.tap()
        let restored = NSPredicate(format: "value == %@", suggested)
        XCTAssertEqual(
            XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: restored, object: detail)], timeout: 10), .completed,
            "Reset didn't bring Detail back to \(suggested)")
        XCTAssertEqual(chip.value as? String, "Suggested for this picture")
        XCTAssertFalse(reset.exists, "Reset is still offered after resetting")
        attachScreenshot(of: app, named: "create-suggested-settings")
    }

    /// The Paint page is one scroll: Tonight’s Picture, Your Own and The Library, whose Paintings
    /// and Photographs sections hold tiles that tell VoiceOver who made them.
    @MainActor
    func testPaintPageShowsItsSections() throws {
        let app = launchPaintPage("create")
        XCTAssertTrue(app.staticTexts["Tonight’s Picture"].waitForExistence(timeout: 30), "The page has no Tonight’s Picture")
        XCTAssertTrue(app.buttons["tonights-picture"].exists, "Tonight’s Picture has no picture")
        XCTAssertTrue(app.staticTexts["Your Own"].exists, "The page has no Your Own")
        XCTAssertTrue(app.buttons["choose-photo"].exists, "Your Own has no A Photo")
        let first = firstLibrarySample(app)
        XCTAssertTrue(first.waitForExistence(timeout: 30), "The Library shows no sample")
        XCTAssertTrue(reveal(first, in: app), "The first library painting can't be reached")
        XCTAssertTrue(app.staticTexts["The Library"].exists, "The page has no The Library")
        for section in ["Paintings", "Photographs"] {
            XCTAssertTrue(app.staticTexts[section].exists, "The Library has no \(section) section")
        }
        let paintings = app.staticTexts["Paintings"]
        XCTAssertGreaterThan(first.frame.minY, paintings.frame.maxY, "The first library sample isn't under the Paintings title")
        // "<title>, <creator>"
        XCTAssertTrue(first.label.contains(", "), "The picture's label doesn't name its creator: \(first.label)")
        attachScreenshot(of: app, named: "paint-page")
    }

    /// A library painting picked on the Paint page opens as a painting by itself: the page shows
    /// Tonight’s Picture, Your Own and The Library, and the preview's Start Painting never appears.
    @MainActor
    func testPickingALibraryPaintingOpensItWithoutStart() throws {
        let app = launchPaintPage("create")
        for heading in ["Tonight’s Picture", "Your Own", "The Library"] {
            XCTAssertTrue(app.staticTexts[heading].waitForExistence(timeout: 30), "The Paint page has no \(heading) heading")
        }
        let first = firstLibrarySample(app)
        XCTAssertTrue(first.waitForExistence(timeout: 30), "The Library shows no painting")
        XCTAssertTrue(reveal(first, in: app), "The first library painting can't be reached")
        first.tap()

        let opened = waitForPaintingWithoutStart(in: app)
        attachScreenshot(of: app, named: "library-painting-opened")
        if !opened { attachTree(of: app, named: "library-painting-opened-tree") }
        XCTAssertTrue(opened, "Picking a library painting didn't open the painting")
        XCTAssertFalse(app.buttons["Start Painting"].exists)
    }

    /// A swipe right across the preview's settings stays on the preview: iOS 26's swipe back from
    /// anywhere on a pushed screen took the sliders' drags and left for the photo step. On the
    /// demo's preview, the flow's first page (a picture picked on the Paint page has no sliders),
    /// so there is no page behind it for an edge swipe to go back to.
    @MainActor
    func testSwipeAcrossSettingsStaysOnPreview() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "create-preview", "-demoFixedPictures", "YES"]
        app.launch()
        let start = app.buttons["Start Painting"]
        XCTAssertTrue(start.waitForExistence(timeout: 60), "The demo didn't open its preview")
        XCTAssertTrue(
            app.descendants(matching: .any)["settings-origin"].waitForExistence(timeout: 10), "The preview has no settings")
        let detail = settingSlider("Detail", in: app)
        XCTAssertTrue(detail.waitForExistence(timeout: 10), "The preview has no Detail slider")

        // Along the slider from its leading end (the thumb is rarely there), then from its title.
        let window = app.windows.firstMatch
        let across = CGVector(dx: window.frame.width * 0.6, dy: 0)
        let track = detail.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.5))
        track.press(forDuration: 0.05, thenDragTo: track.withOffset(across))
        let title = detail.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: -0.8))
        title.press(forDuration: 0.05, thenDragTo: title.withOffset(across))
        sleep(1)
        attachScreenshot(of: app, named: "preview-after-swipes")
        XCTAssertTrue(start.exists && start.isHittable, "A swipe across the settings left the preview")
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
        XCTAssertTrue(first.waitForExistence(timeout: 20), "The Paint page shows no sample")
        sleep(1)
        attachScreenshot(of: app, named: "samples-largest-text")
        let window = app.windows.firstMatch.frame
        XCTAssertGreaterThanOrEqual(first.frame.minX, window.minX - 1, "The first sample runs off the screen")
        XCTAssertLessThanOrEqual(first.frame.maxX, window.maxX + 1, "The first sample runs off the screen")
    }

    /// A Photo presents the full system picker, which dismisses back to the Paint page.
    @MainActor
    func testAPhotoPresentsSystemPickerAndDismisses() throws {
        try skipOnPhoneSimulator()
        let app = launchPaintPage("create")
        let sheet = settledSheetDetector(app)
        XCTAssertNil(sheet.dismissFrame)

        guard let cancel = openPhotoPicker(app, sheet: sheet) else { return }
        tap(app, at: cancel)
        let dismissed = waitUntil(timeout: 15) { sheet.dismissFrame == nil }
        if !dismissed { attachTree(of: app, named: "photo-picker-dismiss-tree") }
        XCTAssertTrue(dismissed, "The system picker didn't dismiss")
        XCTAssertTrue(app.buttons["choose-photo"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["Start Painting"].exists)
    }

    /// A photo picked in the system picker opens as a painting, with no preview and no Start
    /// Painting: the push happens while the sheet dismisses, which must not stall either
    /// transition.
    @MainActor
    func testPickedPhotoOpensAsPainting() throws {
        try XCTSkipIf(isPad, "The system picker sheet's photos aren't reachable on the iPad simulator (no fully visible photo)")
        let app = launchPaintPage("create")
        let sheet = settledSheetDetector(app)

        guard openPhotoPicker(app, sheet: sheet) != nil else { return }
        // The sheet can open on a blank "Loading…" page whose Close sits left of the loaded
        // sheet's Cancel: wait for its photos, then read the bar of the sheet they are in.
        let sheetPhotosShown = waitUntil(timeout: 30) { app.images.matching(photoPredicate).count > 0 }
        if sheetPhotosShown { sleep(1) }
        guard sheetPhotosShown, let cancel = sheet.dismissFrame else {
            attachTree(of: app, named: "photo-picker-loading-tree")
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
        try tapFirstPhoto(app, in: grid, origin: CGPoint(x: window.minX + inset, y: sheetTop))

        let opened = waitForPaintingWithoutStart(in: app)
        attachScreenshot(of: app, named: "photo-picker-picked")
        if !opened { attachTree(of: app, named: "photo-picker-pick-tree") }
        XCTAssertTrue(opened, "Picking a photo didn't open its painting")
        XCTAssertTrue(waitUntil(timeout: 15) { sheet.dismissFrame == nil }, "The system picker stayed up after a pick")
    }

    // MARK: - Helpers

    /// On the iPhone simulator the system picker's sheet ignores a synthesized tap on its Cancel
    /// (screen recordings show the tap landing on it; the same flow passes on iPad). Verified on
    /// iPad and on a device.
    @MainActor
    private func skipOnPhoneSimulator() throws {
        try XCTSkipIf(!isPad, "The system photo picker ignores synthesized taps on the iPhone simulator")
    }

    /// Library photos as the picker exposes them to UI tests.
    private var photoPredicate: NSPredicate { NSPredicate(format: "label BEGINSWITH 'Photo'") }

    /// Portrait CI devices: the iPad is wide (1032 pt), the iPhone compact (402 pt).
    @MainActor
    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    /// Launches a create scenario and waits for the Paint page (A Photo is its first Your Own tile;
    /// not asserted here, so each test reports its own failure).
    @MainActor
    private func launchPaintPage(_ scenario: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", scenario]
        app.launch()
        _ = app.buttons["choose-photo"].waitForExistence(timeout: 20)
        // First use may explain limited library access. It is up by the time the page is, so
        // a short wait suffices; the usual case, no alert, then costs little per test.
        let ok = app.buttons["OK"]
        if ok.waitForExistence(timeout: 2) { ok.tap() }
        return app
    }

    /// The first tile of The Library, the library's first painting, whatever the library's curation
    /// (Tonight’s Picture is a sample too, and is left out).
    @MainActor
    private func firstLibrarySample(_ app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(identifier: "library-picture").firstMatch
    }

    /// The first sample tile on the page, Tonight’s Picture.
    @MainActor
    private func firstSample(_ app: XCUIApplication) -> XCUIElement {
        app.buttons["tonights-picture"]
    }

    /// A sheet detector made once the page's A Photo tile is ready for a tap: a Cancel/Close that
    /// comes after the snapshot is the sheet's.
    @MainActor
    private func settledSheetDetector(_ app: XCUIApplication) -> SheetDetector {
        let photo = app.buttons["choose-photo"]
        XCTAssertTrue(waitUntil(timeout: 10) { photo.isHittable }, "A Photo isn't ready for a tap")
        return SheetDetector(app)
    }

    /// Taps A Photo and returns the frame of the presented sheet's dismiss button, or
    /// fails the test (with diagnostics) and returns nil when no sheet appears. A tap that
    /// brings up no sheet is kept as a screenshot and tree and made once more: the out-of-process
    /// picker's cold start can swallow the first (CI, iPad, October 23: no sheet within the wait
    /// and no main-thread stall, then the test's rerun saw it at once), as the tile's
    /// first tap can. A button a late sheet has covered isn't tapped again.
    @MainActor
    private func openPhotoPicker(_ app: XCUIApplication, sheet: SheetDetector) -> CGRect? {
        let browse = app.buttons["choose-photo"]
        browse.tap()
        var cancel: CGRect?
        if !waitUntil(timeout: 15, { cancel = sheet.dismissFrame; return cancel != nil }) {
            attachScreenshot(of: app, named: "photo-picker-tap-missed")
            attachTree(of: app, named: "photo-picker-tap-missed-tree")
            if browse.isHittable { browse.tap() }
            _ = waitUntil(timeout: 25) { cancel = sheet.dismissFrame; return cancel != nil }
        }
        if cancel != nil {
            // Read again once the sheet has slid into place: a frame read mid-animation misses.
            // The out-of-process sheet can be missing from a snapshot then (CI, iPhone, Oct 17:
            // seen, then gone a second later on its Loading page), so the last frame seen stands.
            sleep(1)
            _ = waitUntil(timeout: 10) {
                if let frame = sheet.dismissFrame { cancel = frame; return true }
                return false
            }
        }
        attachScreenshot(of: app, named: "photo-picker")
        guard let cancel else {
            attachTree(of: app, named: "photo-picker-tree")
            XCTFail("A Photo didn't present the system picker")
            return nil
        }
        return cancel
    }

    /// Taps the first photo of the system picker's sheet that is fully visible inside `area`
    /// (window coordinates) and returns the point tapped.
    /// The picker runs out of process and its photos may report frames in its own coordinates
    /// (relative to `origin`, the sheet's top-left corner in the window) rather than the
    /// window's: a photo that passes XCUITest's hit test is in window coordinates, otherwise the
    /// picker-relative reading is used if it fits, else the reported frame.
    @MainActor
    @discardableResult
    private func tapFirstPhoto(_ app: XCUIApplication, in area: CGRect, origin: CGPoint) throws -> CGPoint {
        let photos = app.images.matching(photoPredicate)
        guard photos.firstMatch.waitForExistence(timeout: 20) else {
            attachTree(of: app, named: "photo-picker-tree")
            throw XCTSkip("The system picker's photos aren't reachable from the UI test")
        }
        // Thumbnails only (the picker's bar may carry small glyphs with similar labels), read one
        // at a time and only as far as the first usable one: the full picker's sheet lists photos
        // it can't then resolve by index ("No matches found for Element at index 6"), so one that
        // doesn't exist is passed over rather than read.
        let thumbnails = photos.allElementsBoundByIndex.prefix(60).lazy
            .filter { $0.exists }
            .map { (element: $0, frame: $0.frame) }
            .filter { $0.frame.width >= 40 && $0.frame.height >= 40 }
        var target: CGRect?
        for (photo, frame) in thumbnails {
            let relative = frame.offsetBy(dx: origin.x, dy: origin.y)
            if area.contains(frame), photo.isHittable {
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
            attachTree(of: app, named: "photo-picker-tree")
            throw XCTSkip("No photo is fully visible inside the system picker")
        }
        let point = CGPoint(x: target.midX, y: target.midY)
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: point.x, dy: point.y)).tap()
        return point
    }

    /// Taps the middle of `frame` (window coordinates).
    @MainActor
    private func tap(_ app: XCUIApplication, at frame: CGRect) {
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: frame.midX, dy: frame.midY)).tap()
    }
}

/// Finds the system picker sheet by an on-screen Cancel/Close button that wasn't on the page
/// when the detector was made: the page keeps its own Close, and a modal sheet may hide the page
/// from accessibility, so neither names nor counts identify it.
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
        // CI's picker can time out enumerating buttons as its sheet changes. Resolve each index
        // inside the throwing snapshot so the caller's polling can retry a failed read.
        return (0..<8).compactMap { index in
            guard let element = try? buttons.element(boundBy: index).snapshot(),
                  element.isEnabled else { return nil }
            let frame = element.frame
            return !frame.isEmpty && screen.contains(CGPoint(x: frame.midX, y: frame.midY)) ? frame : nil
        }
    }
}
