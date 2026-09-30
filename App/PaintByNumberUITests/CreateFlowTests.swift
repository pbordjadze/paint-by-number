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

    /// The inline picker is the page's primary content and no scroll view contains it: its pan
    /// runs out of process and can't be arbitrated against an in-process ancestor's pan.
    @MainActor
    func testLibraryFillsTheScreenOutsideAnyScrollView() throws {
        let app = launch("create")
        let picker = app.descendants(matching: .any).matching(pickerPredicate).firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 20))
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
        let app = launch("create")
        let picker = app.descendants(matching: .any).matching(pickerPredicate).firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 20))

        try tapFirstPhoto(app, in: picker)
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

        try tapFirstPhoto(app, in: picker)
        let reopened = start.waitForExistence(timeout: 60)
        attachScreenshot(app, named: "library-photo-picked-again")
        XCTAssertTrue(reopened, "The same photo couldn't be picked a second time")
    }

    /// Samples (behind a segment on compact widths, beside the picker on wide ones) open their preview.
    @MainActor
    func testSamplesOpenPreview() throws {
        let app = launch("create")
        let picker = app.descendants(matching: .any).matching(pickerPredicate).firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 20))
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
        let app = launch("create")
        let picker = app.descendants(matching: .any).matching(pickerPredicate).firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 20))
        // The sheet is recognised by a hittable Cancel/Close button that wasn't on the page
        // before: the page keeps its own Close, the inline picker's bar may bring its own, and a
        // modal sheet may hide the page from accessibility, so neither names nor counts identify
        // it. (On iPad the form sheet overlaps the inline picker, so position can't either.)
        let existing = dismissButtons(app).allElementsBoundByIndex.map { $0.frame }
        func sheetDismissButton() -> XCUIElement? {
            dismissButtons(app).allElementsBoundByIndex.first { button in
                let frame = button.frame
                return button.isHittable && !existing.contains { $0.insetBy(dx: -2, dy: -2).contains(frame) }
            }
        }
        XCTAssertNil(sheetDismissButton())

        app.buttons["Browse All…"].tap()
        let shown = poll(timeout: 15) { sheetDismissButton() != nil }
        attachScreenshot(app, named: "browse-all")
        guard shown, let cancel = sheetDismissButton() else {
            attachTree(app, named: "browse-all-tree")
            XCTFail("Browse All didn't present the system picker")
            return
        }
        cancel.tap()
        let dismissed = poll(timeout: 15) { sheetDismissButton() == nil }
        if !dismissed { attachTree(app, named: "browse-all-dismiss-tree") }
        XCTAssertTrue(dismissed, "The system picker didn't dismiss")
        XCTAssertTrue(picker.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["Start Painting"].exists)
    }

    // MARK: - Helpers

    private var pickerPredicate: NSPredicate { NSPredicate(format: "identifier == 'library-picker'") }

    /// Portrait CI devices: the iPad is wide (1032 pt), the iPhone compact (402 pt).
    @MainActor
    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    @MainActor
    private func launch(_ scenario: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", scenario]
        app.launch()
        // First use explains limited library access.
        let ok = app.buttons["OK"]
        if ok.waitForExistence(timeout: 10) { ok.tap() }
        return app
    }

    /// The Photos/Samples segmented control, whatever element type carries its identifier.
    /// Segments are always looked up inside it: the picker has its own Photos/Albums switcher.
    @MainActor
    private func sourceControl(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "photo-source").firstMatch
    }

    @MainActor
    private func dismissButtons(_ app: XCUIApplication) -> XCUIElementQuery {
        app.buttons.matching(NSPredicate(format: "label IN {'Cancel', 'Close'}"))
    }

    /// Taps the first library photo that is fully visible inside the picker. The picker runs
    /// out of process and its photos may report frames in its own coordinates rather than the
    /// window's, so both readings are tried; a photo frame that is fully inside the picker in
    /// window coordinates can't be picker-relative, since the picker is inset from the window.
    @MainActor
    private func tapFirstPhoto(_ app: XCUIApplication, in picker: XCUIElement) throws {
        let photos = app.images.matching(NSPredicate(format: "label BEGINSWITH 'Photo'"))
        guard photos.firstMatch.waitForExistence(timeout: 20) else {
            attachTree(app, named: "library-picker-tree")
            throw XCTSkip("The library picker's photos aren't reachable from the UI test")
        }
        let area = picker.frame
        var target: CGRect?
        for photo in photos.allElementsBoundByIndex.prefix(30) {
            let frame = photo.frame
            // Thumbnails only (the picker's bar may carry small glyphs with similar labels).
            guard frame.width >= 40, frame.height >= 40 else { continue }
            let relative = frame.offsetBy(dx: area.minX, dy: area.minY)
            if area.contains(frame) {
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

    @MainActor
    private func attachScreenshot(_ app: XCUIApplication, named name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
