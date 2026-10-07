import XCTest

/// The create flow's optional Refine step: brushing, Undo and Redo, marking text, Done and Cancel.
final class RefineUITests: XCTestCase {
    /// One finger brushes the template (a change), Undo and Redo step through it, the Text tool
    /// marks a line dragged across, Done keeps it all; Cancel puts back what Refine opened with.
    @MainActor
    func testRefineBrushesMarksTextAndKeepsIt() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "create-preview", "-demoFixedPictures", "YES"]
        app.launch()
        let start = app.buttons["Start Painting"]
        XCTAssertTrue(start.waitForExistence(timeout: 30), "The preview didn't open")
        XCTAssertTrue(
            waitFor(start, toMatch: NSPredicate(format: "isEnabled == true"), timeout: 120),
            "The preview never finished choosing its settings")

        let refine = app.buttons["refine"]
        XCTAssertTrue(refine.exists, "The preview has no Refine")
        XCTAssertEqual(refine.value as? String, "No changes")
        refine.tap()

        let canvas = app.descendants(matching: .any)["refine-canvas"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 10), "Refine didn't open")
        XCTAssertEqual(canvas.value as? String, "No changes")
        XCTAssertTrue(app.buttons["refine-tool-more"].isSelected, "Refine doesn't start on More Detail")
        let undo = app.buttons["refine-undo"], redo = app.buttons["refine-redo"]
        XCTAssertFalse(undo.isEnabled, "Undo is offered before any change")

        drag(on: canvas, from: CGVector(dx: 0.3, dy: 0.42), to: CGVector(dx: 0.6, dy: 0.5))
        XCTAssertTrue(
            waitFor(canvas, toMatch: NSPredicate(format: "value == %@", "1 change")),
            "The brush stroke didn't count: \(canvas.value ?? "")")
        XCTAssertTrue(undo.isEnabled)
        attachScreenshot(of: app, named: "refine-brushed")

        undo.tap()
        XCTAssertTrue(waitFor(canvas, toMatch: NSPredicate(format: "value == %@", "No changes")), "Undo didn't take the stroke back")
        XCTAssertTrue(redo.isEnabled)
        redo.tap()
        XCTAssertTrue(waitFor(canvas, toMatch: NSPredicate(format: "value == %@", "1 change")), "Redo didn't put the stroke back")

        let text = app.buttons["refine-tool-text"]
        XCTAssertTrue(text.exists, "Refine has no Text tool")
        text.tap()
        XCTAssertTrue(waitFor(text, toMatch: NSPredicate(format: "isSelected == true")), "Text didn't become the tool")
        drag(on: canvas, from: CGVector(dx: 0.2, dy: 0.55), to: CGVector(dx: 0.55, dy: 0.6))
        XCTAssertTrue(
            waitFor(canvas, toMatch: NSPredicate(format: "value == %@", "2 changes")),
            "Dragging with Text didn't mark a line: \(canvas.value ?? "")")
        attachScreenshot(of: app, named: "refine-text-marked")

        app.buttons["refine-done"].tap()
        XCTAssertTrue(waitFor(refine, toMatch: NSPredicate(format: "value == %@", "2 changes")), "Done didn't keep the changes")

        // Cancel puts back what Refine opened with.
        refine.tap()
        XCTAssertTrue(canvas.waitForExistence(timeout: 10), "Refine didn't open again")
        drag(on: canvas, from: CGVector(dx: 0.4, dy: 0.45), to: CGVector(dx: 0.7, dy: 0.45))
        XCTAssertTrue(waitFor(canvas, toMatch: NSPredicate(format: "value == %@", "3 changes")), "The second stroke didn't count")
        app.buttons["refine-cancel"].tap()
        XCTAssertTrue(
            waitFor(refine, toMatch: NSPredicate(format: "value == %@", "2 changes")),
            "Cancel didn't put back what Refine opened with: \(refine.value ?? "")")
        XCTAssertTrue(
            waitFor(start, toMatch: NSPredicate(format: "isEnabled == true"), timeout: 120), "The refined preview can't be started")
    }

    /// One finger dragged across `element`, as a brush stroke is.
    @MainActor
    private func drag(on element: XCUIElement, from: CGVector, to: CGVector) {
        element.coordinate(withNormalizedOffset: from)
            .press(forDuration: 0.05, thenDragTo: element.coordinate(withNormalizedOffset: to))
    }
}
