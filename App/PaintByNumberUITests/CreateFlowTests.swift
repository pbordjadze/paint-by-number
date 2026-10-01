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
    /// was typed.
    @MainActor
    func testTitleNamesThePainting() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "create-preview"]
        app.launch()

        let start = app.buttons["Start Painting"]
        XCTAssertTrue(start.waitForExistence(timeout: 30))
        expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: start)
        waitForExpectations(timeout: 60)

        let title = app.textFields["painting-title"]
        XCTAssertTrue(title.exists, "The preview has no title field")
        XCTAssertEqual(title.placeholderValue, "Parrots")
        title.tap()
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
            let sample = app.buttons["Sample: Parrots"]
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

        try tapFirstPhoto(app, in: picker.frame)
        let start = app.buttons["Start Painting"]
        let opened = start.waitForExistence(timeout: 60)
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

        try tapFirstPhoto(app, in: picker.frame)
        let reopened = start.waitForExistence(timeout: 60)
        attachScreenshot(app, named: "library-photo-picked-again")
        XCTAssertTrue(reopened, "The same photo couldn't be picked a second time")
    }

    /// Samples (behind a segment on compact widths, beside the picker on wide ones) open their preview.
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
        let parrots = app.buttons["Sample: Parrots"]
        XCTAssertTrue(parrots.waitForExistence(timeout: 10))
        XCTAssertTrue(parrots.isHittable)
        attachScreenshot(app, named: "samples")

        if !isPad {
            // Back to the picker at full height, then to the samples again.
            sourceControl(app).buttons["Photos"].tap()
            XCTAssertTrue(picker.waitForExistence(timeout: 10))
            XCTAssertEqual(picker.frame.height, pickerHeight, accuracy: 1)
            samples.tap()
            XCTAssertTrue(parrots.waitForExistence(timeout: 10))
        }
        parrots.tap()
        XCTAssertTrue(app.buttons["Start Painting"].waitForExistence(timeout: 60), "Picking a sample didn't open its preview")
    }

    /// "Browse All…" presents the full system picker, which dismisses back to the create flow.
    @MainActor
    func testBrowseAllPresentsSystemPickerAndDismisses() throws {
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
        let inlinePhotos = app.images.matching(photoPredicate).allElementsBoundByIndex.map { $0.frame }

        guard let cancel = openBrowseAll(app, sheet: sheet) else { return }
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
            app, in: grid, origin: CGPoint(x: window.minX + inset, y: sheetTop), excluding: inlinePhotos)

        let start = app.buttons["Start Painting"]
        let opened = start.waitForExistence(timeout: 60)
        attachScreenshot(app, named: "browse-all-picked")
        if !opened { attachTree(app, named: "browse-all-pick-tree") }
        XCTAssertTrue(opened, "Picking a photo in Browse All didn't open its preview")
        XCTAssertTrue(poll(timeout: 15) { sheet.dismissFrame == nil }, "The system picker stayed up after a pick")
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
        attachScreenshot(app, named: "browse-all")
        guard shown, let cancel = sheet.dismissFrame else {
            attachTree(app, named: "browse-all-tree")
            XCTFail("Browse All didn't present the system picker")
            return nil
        }
        return cancel
    }

    /// Taps the first library photo that is fully visible inside `area` (window coordinates).
    /// The picker runs out of process and its photos may report frames in its own coordinates
    /// (relative to `origin`, the picker's top-left corner in the window) rather than the
    /// window's. A photo whose reported frame passes XCUITest's hit test is in window
    /// coordinates; otherwise the picker-relative reading is used. Photos at the `excluding`
    /// frames (as reported) belong to another picker and are skipped.
    @MainActor
    private func tapFirstPhoto(
        _ app: XCUIApplication, in area: CGRect, origin: CGPoint? = nil, excluding: [CGRect] = []
    ) throws {
        let photos = app.images.matching(photoPredicate)
        guard photos.firstMatch.waitForExistence(timeout: 20) else {
            attachTree(app, named: "library-picker-tree")
            throw XCTSkip("The library picker's photos aren't reachable from the UI test")
        }
        let origin = origin ?? area.origin
        var target: CGRect?
        for photo in photos.allElementsBoundByIndex.prefix(60) {
            let frame = photo.frame
            // Thumbnails only (the picker's bar may carry small glyphs with similar labels).
            guard frame.width >= 40, frame.height >= 40, !excluding.contains(frame) else { continue }
            let relative = frame.offsetBy(dx: origin.x, dy: origin.y)
            if area.contains(frame), photo.isHittable {
                target = frame
            } else if area.contains(relative) {
                target = relative
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

    /// The frame of the sheet's dismiss button, nil while no sheet is up.
    var dismissFrame: CGRect? {
        Self.dismissFrames(in: app).first { frame in
            !existing.contains { $0.insetBy(dx: -2, dy: -2).contains(frame) }
        }
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
