import XCTest

/// The create flow's optional Refine step: the pens, the eraser and Fill, no Color Splitter, the
/// text marks, Undo and Redo (the buttons and a two-finger tap), Done and Cancel.
final class RefineUITests: XCTestCase {
    /// The pen draws a line (a change), Undo and Redo step through it as a two-finger tap undoes
    /// too, the eraser rubs across it (another change: an edit that changes nothing is none), Fill
    /// fills a shape with a tap (a third), the painting shows beneath the drawing, Done keeps it
    /// all; Shapes draws a rectangle, and Cancel puts back what Refine opened with.
    @MainActor
    func testRefineDrawsErasesAndKeepsIt() throws {
        let app = launchPreview()
        let start = app.buttons["Start Painting"]
        let refine = app.buttons["refine"]
        XCTAssertTrue(refine.exists, "The preview has no Refine")
        XCTAssertEqual(refine.value as? String, "No changes")
        refine.tap()

        // Tapped while the painting may still be updating: it opens once the final template is made.
        let canvas = app.descendants(matching: .any)["refine-canvas"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 120), "Refine didn't open")
        XCTAssertEqual(canvas.value as? String, "No changes")
        XCTAssertTrue(app.buttons["refine-tool-pen"].isSelected, "Refine doesn't start on the pen")
        XCTAssertTrue(app.buttons["refine-tool-text"].exists, "Refine has no Text tool")
        let undo = app.buttons["refine-undo"], redo = app.buttons["refine-redo"]
        XCTAssertFalse(undo.isEnabled, "Undo is offered before any change")

        drag(on: canvas, from: CGVector(dx: 0.25, dy: 0.4), to: CGVector(dx: 0.7, dy: 0.45))
        XCTAssertTrue(
            waitFor(canvas, toMatch: changes("1 change")), "The line didn't count: \(canvas.value ?? "")")
        XCTAssertTrue(undo.isEnabled)
        attachScreenshot(of: app, named: "refine-drawn")

        undo.tap()
        XCTAssertTrue(waitFor(canvas, toMatch: changes("No changes")), "Undo didn't take the line back")
        XCTAssertTrue(redo.isEnabled)
        redo.tap()
        XCTAssertTrue(waitFor(canvas, toMatch: changes("1 change")), "Redo didn't put the line back")
        canvas.twoFingerTap()
        XCTAssertTrue(waitFor(canvas, toMatch: changes("No changes")), "A two-finger tap didn't undo")
        redo.tap()
        XCTAssertTrue(waitFor(canvas, toMatch: changes("1 change")), "Redo didn't put the line back again")

        // The Eraser is in the Erasers button, with the Smart Eraser.
        let erasers = app.buttons["refine-tool-erasers"]
        XCTAssertTrue(erasers.exists, "Refine has no erasers")
        erasers.tap()
        menuItem("Eraser", in: app).tap()
        XCTAssertTrue(waitFor(erasers, toMatch: NSPredicate(format: "isSelected == true")), "The eraser didn't become the tool")
        XCTAssertEqual(erasers.value as? String, "Eraser")
        // Across the line just drawn, which runs from (0.25, 0.4) to (0.7, 0.45): rubbing bare paper
        // changes nothing, and so isn't a change.
        drag(on: canvas, from: CGVector(dx: 0.45, dy: 0.3), to: CGVector(dx: 0.5, dy: 0.6))
        XCTAssertTrue(
            waitFor(canvas, toMatch: changes("2 changes")), "Rubbing out didn't count: \(canvas.value ?? "")")
        attachScreenshot(of: app, named: "refine-erased")

        let fill = app.buttons["refine-tool-fill"]
        XCTAssertTrue(fill.exists, "Refine has no Fill")
        fill.tap()
        XCTAssertTrue(waitFor(fill, toMatch: NSPredicate(format: "isSelected == true")), "Fill didn't become the tool")
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(waitFor(canvas, toMatch: changes("3 changes")), "The fill didn't count: \(canvas.value ?? "")")
        attachScreenshot(of: app, named: "refine-filled")

        // The photo and the painting beneath the drawing are in one button.
        let backdrop = app.buttons["refine-backdrop"]
        XCTAssertTrue(backdrop.exists, "Refine can't show the painting")
        backdrop.tap()
        menuItem("Painting", in: app).tap()
        XCTAssertTrue(waitFor(backdrop, toMatch: NSPredicate(format: "value == %@", "Painting")), "The painting didn't show")
        XCTAssertTrue(backdrop.isSelected)
        attachScreenshot(of: app, named: "refine-painting")
        backdrop.tap()
        menuItem("Painting", in: app).tap()
        XCTAssertTrue(waitFor(backdrop, toMatch: NSPredicate(format: "value == %@", "Paper")), "The painting didn't go")

        app.buttons["refine-done"].tap()
        XCTAssertTrue(waitFor(refine, toMatch: changes("3 changes")), "Done didn't keep the changes")

        // Cancel puts back what Refine opened with. This time Shapes draws a rectangle.
        refine.tap()
        XCTAssertTrue(canvas.waitForExistence(timeout: 10), "Refine didn't open again")
        let shapes = app.buttons["refine-tool-shapes"]
        XCTAssertTrue(shapes.exists, "Refine has no Shapes")
        // No line under the tools says how they work: their VoiceOver hints do, and a tip once.
        XCTAssertFalse(app.staticTexts["refine-hint"].exists, "Refine still explains its tools under them")
        shapes.tap()
        let rectangle = app.buttons["Rectangle"]
        XCTAssertTrue(rectangle.waitForExistence(timeout: 5), "Shapes offers no rectangle")
        rectangle.tap()
        XCTAssertTrue(
            waitFor(shapes, toMatch: NSPredicate(format: "isSelected == true AND value == %@", "Rectangle")),
            "Shapes didn't become the tool with the rectangle")
        drag(on: canvas, from: CGVector(dx: 0.4, dy: 0.3), to: CGVector(dx: 0.7, dy: 0.5))
        XCTAssertTrue(waitFor(canvas, toMatch: changes("4 changes")), "The rectangle didn't count")
        attachScreenshot(of: app, named: "refine-rectangle")
        app.buttons["refine-cancel"].tap()
        XCTAssertTrue(
            waitFor(refine, toMatch: changes("3 changes")),
            "Cancel didn't put back what Refine opened with: \(refine.value ?? "")")
        XCTAssertTrue(
            waitFor(start, toMatch: NSPredicate(format: "isEnabled == true"), timeout: 120), "The refined preview can't be started")
    }

    /// The toolbar has no Color Splitter for now (`RefineView.offersSplitter`): the Pen's line
    /// down the sky divides it instead. Text marks a line of text dragged across; there are no
    /// detail brushes. Done keeps both.
    @MainActor
    func testPenSplitAndTextCorrections() throws {
        let app = launchPreview()
        let refine = app.buttons["refine"]
        refine.tap()
        let canvas = app.descendants(matching: .any)["refine-canvas"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 120), "Refine didn't open")
        XCTAssertFalse(app.buttons["refine-tool-more"].exists, "Refine still has the More Detail brush")
        XCTAssertFalse(app.buttons["refine-tool-splitter"].exists, "Refine still offers the Color Splitter")

        let pen = app.buttons["refine-tool-pen"]
        XCTAssertTrue(waitFor(pen, toMatch: NSPredicate(format: "isSelected == true")), "Refine doesn't start on the pen")
        // Down the open sky of The Great Wave, from above the wave's outline to inside little Fuji:
        // crossing a line at each end, it divides the sky between them.
        drag(on: canvas, from: onPicture(canvas, 0.637, 0.06), to: onPicture(canvas, 0.637, 0.675))
        XCTAssertTrue(
            waitFor(canvas, toMatch: changes("1 change")), "The line didn't count: \(canvas.value ?? "")")
        attachScreenshot(of: app, named: "refine-pen-split")

        let text = app.buttons["refine-tool-text"]
        XCTAssertTrue(text.exists, "Refine has no Text tool")
        text.tap()
        XCTAssertTrue(waitFor(text, toMatch: NSPredicate(format: "isSelected == true")), "Text didn't become the tool")
        drag(on: canvas, from: CGVector(dx: 0.2, dy: 0.55), to: CGVector(dx: 0.55, dy: 0.6))
        XCTAssertTrue(
            waitFor(canvas, toMatch: changes("2 changes")), "Dragging with Text didn't mark a line: \(canvas.value ?? "")")

        app.buttons["refine-done"].tap()
        XCTAssertTrue(waitFor(refine, toMatch: changes("2 changes")), "Done didn't keep the changes")
    }

    // MARK: - Helpers

    /// An item of the open menu: a button, or a toggle's switch.
    @MainActor
    private func menuItem(_ label: String, in app: XCUIApplication) -> XCUIElement {
        let button = app.buttons[label]
        if button.waitForExistence(timeout: 5) { return button }
        return app.switches[label]
    }

    /// The Great Wave's preview once its settings are chosen.
    @MainActor
    private func launchPreview() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "create-preview", "-demoFixedPictures", "YES"]
        app.launch()
        let start = app.buttons["Start Painting"]
        XCTAssertTrue(start.waitForExistence(timeout: 30), "The preview didn't open")
        XCTAssertTrue(
            waitFor(start, toMatch: NSPredicate(format: "isEnabled == true"), timeout: 120),
            "The preview never finished choosing its settings")
        // Refine is on once the settings are chosen; a tap before the final template is made waits
        // for it (the tests wait for Refine to open).
        XCTAssertTrue(
            waitFor(app.buttons["refine"], toMatch: NSPredicate(format: "isEnabled == true"), timeout: 120),
            "Refine never came on")
        return app
    }

    private func changes(_ value: String) -> NSPredicate { NSPredicate(format: "value == %@", value) }

    /// One finger dragged across `element`, as a line is drawn.
    @MainActor
    /// A point of the picture (fractions of its width and height) as an offset in the canvas,
    /// the whole surface, where the picture is fitted in the middle: The Great Wave (2048 × 1375),
    /// `create-preview`'s picture.
    private func onPicture(_ canvas: XCUIElement, _ x: CGFloat, _ y: CGFloat) -> CGVector {
        let size = canvas.frame.size, aspect: CGFloat = 2048 / 1375
        let width = min(size.width, size.height * aspect), height = width / aspect
        return CGVector(
            dx: ((size.width - width) / 2 + x * width) / size.width,
            dy: ((size.height - height) / 2 + y * height) / size.height)
    }

    private func drag(on element: XCUIElement, from: CGVector, to: CGVector) {
        element.coordinate(withNormalizedOffset: from)
            .press(forDuration: 0.05, thenDragTo: element.coordinate(withNormalizedOffset: to))
    }
}
