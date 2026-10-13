import XCTest

/// The create flow's optional Refine step: the pens, the eraser and Fill, Undo and Redo (the
/// buttons and a two-finger tap), Done and Cancel; with Settings › Detail Brushes, its brushes
/// and text marks too.
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

        let canvas = app.descendants(matching: .any)["refine-canvas"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 10), "Refine didn't open")
        XCTAssertEqual(canvas.value as? String, "No changes")
        XCTAssertTrue(app.buttons["refine-tool-pen"].isSelected, "Refine doesn't start on the pen")
        XCTAssertFalse(app.buttons["refine-tool-more"].exists, "The detail brushes show with Detail Brushes off")
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

        let eraser = app.buttons["refine-tool-eraser"]
        XCTAssertTrue(eraser.exists, "Refine has no eraser")
        eraser.tap()
        XCTAssertTrue(waitFor(eraser, toMatch: NSPredicate(format: "isSelected == true")), "The eraser didn't become the tool")
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

        let painting = app.buttons["refine-painting"]
        XCTAssertTrue(painting.exists, "Refine can't show the painting")
        painting.tap()
        XCTAssertTrue(waitFor(painting, toMatch: NSPredicate(format: "isSelected == true")), "The painting didn't show")
        attachScreenshot(of: app, named: "refine-painting")
        painting.tap()
        XCTAssertTrue(waitFor(painting, toMatch: NSPredicate(format: "isSelected == false")), "The painting didn't go")

        app.buttons["refine-done"].tap()
        XCTAssertTrue(waitFor(refine, toMatch: changes("3 changes")), "Done didn't keep the changes")

        // Cancel puts back what Refine opened with. This time Shapes draws a rectangle.
        refine.tap()
        XCTAssertTrue(canvas.waitForExistence(timeout: 10), "Refine didn't open again")
        let shapes = app.buttons["refine-tool-shapes"]
        XCTAssertTrue(shapes.exists && app.buttons["refine-tool-smart-eraser"].exists, "Refine has no Shapes or Smart Eraser")
        shapes.tap()
        let rectangle = app.buttons["Rectangle"]
        XCTAssertTrue(rectangle.waitForExistence(timeout: 5), "Shapes offers no rectangle")
        rectangle.tap()
        XCTAssertTrue(
            waitFor(app.staticTexts["refine-hint"], toMatch: NSPredicate(format: "label CONTAINS[c] 'rectangle'")),
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

    /// With Settings › Detail Brushes on, Refine also brushes areas for more detail and marks a
    /// line of text dragged across, and Done keeps both.
    @MainActor
    func testDetailBrushesBrushAndMarkText() throws {
        let app = launchPreview(arguments: ["-refineDetailBrushes", "YES"])
        let refine = app.buttons["refine"]
        refine.tap()
        let canvas = app.descendants(matching: .any)["refine-canvas"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 10), "Refine didn't open")
        let more = app.buttons["refine-tool-more"]
        XCTAssertTrue(more.exists, "Detail Brushes on, Refine has no More Detail")
        more.tap()
        drag(on: canvas, from: CGVector(dx: 0.3, dy: 0.42), to: CGVector(dx: 0.6, dy: 0.5))
        XCTAssertTrue(
            waitFor(canvas, toMatch: changes("1 change")), "The brush stroke didn't count: \(canvas.value ?? "")")

        let text = app.buttons["refine-tool-text"]
        XCTAssertTrue(text.exists, "Refine has no Text tool")
        text.tap()
        XCTAssertTrue(waitFor(text, toMatch: NSPredicate(format: "isSelected == true")), "Text didn't become the tool")
        drag(on: canvas, from: CGVector(dx: 0.2, dy: 0.55), to: CGVector(dx: 0.55, dy: 0.6))
        XCTAssertTrue(
            waitFor(canvas, toMatch: changes("2 changes")), "Dragging with Text didn't mark a line: \(canvas.value ?? "")")
        attachScreenshot(of: app, named: "refine-detail-brushes")

        app.buttons["refine-done"].tap()
        XCTAssertTrue(waitFor(refine, toMatch: changes("2 changes")), "Done didn't keep the changes")
    }

    // MARK: - Helpers

    /// The Great Wave's preview once its settings are chosen.
    @MainActor
    private func launchPreview(arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "create-preview", "-demoFixedPictures", "YES"] + arguments
        app.launch()
        let start = app.buttons["Start Painting"]
        XCTAssertTrue(start.waitForExistence(timeout: 30), "The preview didn't open")
        XCTAssertTrue(
            waitFor(start, toMatch: NSPredicate(format: "isEnabled == true"), timeout: 120),
            "The preview never finished choosing its settings")
        // Refine opens on the final template, which can come after the first draft.
        XCTAssertTrue(
            waitFor(app.buttons["refine"], toMatch: NSPredicate(format: "isEnabled == true"), timeout: 120),
            "The preview never became ready to refine")
        return app
    }

    private func changes(_ value: String) -> NSPredicate { NSPredicate(format: "value == %@", value) }

    /// One finger dragged across `element`, as a line is drawn.
    @MainActor
    private func drag(on element: XCUIElement, from: CGVector, to: CGVector) {
        element.coordinate(withNormalizedOffset: from)
            .press(forDuration: 0.05, thenDragTo: element.coordinate(withNormalizedOffset: to))
    }
}
