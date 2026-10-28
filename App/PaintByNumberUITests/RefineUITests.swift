import XCTest

/// The create flow's optional Refine step, as the Toolbox lays it out in Debug builds (its groups:
/// Ink, Cells, Paint, Numbers, See; a rail of every tool on iPad, tabs on iPhone): the pens, the eraser and
/// Make Cell, Writing's text marks, Select, Cell Edge and the Bucket, an area's card, the
/// Eyedropper's hold, the Layers panel, Undo and Redo (the buttons and two- and three-finger taps),
/// full screen, Done and Cancel.
final class RefineUITests: XCTestCase {
    /// The pen draws a line (a change), Undo and Redo step through it as a two-finger tap undoes
    /// and a three-finger tap redoes too, the eraser (with its Size) rubs across it (another change:
    /// an edit that changes nothing is none), Make Cell fills a shape with a tap (a third), the
    /// Layers panel hides the paint and shows it again, a four-finger tap shows the picture alone
    /// and its corner button brings the tools back, Done keeps it all; Shapes draws a rectangle, and
    /// Cancel, once it is confirmed, puts back what Refine opened with.
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
        canvas.tap(withNumberOfTaps: 1, numberOfTouches: 3)
        XCTAssertTrue(waitFor(canvas, toMatch: changes("1 change")), "A three-finger tap didn't redo")

        // The Eraser and the Line Eraser are tools of the Ink group, beside the Pen.
        XCTAssertTrue(app.buttons["refine-tool-smartEraser"].exists, "Refine has no Smart Eraser")
        let eraser = app.buttons["refine-tool-eraser"]
        XCTAssertTrue(eraser.exists, "Refine has no eraser")
        // On iPad a keyboard's E picks it (the canvas's keys); elsewhere its button.
        let keyboard = UIDevice.current.userInterfaceIdiom == .pad
        if keyboard { app.typeKey("e", modifierFlags: []) } else { eraser.tap() }
        XCTAssertTrue(waitFor(eraser, toMatch: NSPredicate(format: "isSelected == true")), "The eraser didn't become the tool")
        XCTAssertTrue(app.sliders["refine-eraser-size"].waitForExistence(timeout: 5), "The eraser has no Size")
        // Across the line just drawn, which runs from (0.25, 0.4) to (0.7, 0.45): rubbing bare paper
        // changes nothing, and so isn't a change.
        drag(on: canvas, from: CGVector(dx: 0.45, dy: 0.3), to: CGVector(dx: 0.5, dy: 0.6))
        XCTAssertTrue(
            waitFor(canvas, toMatch: changes("2 changes")), "Rubbing out didn't count: \(canvas.value ?? "")")
        attachScreenshot(of: app, named: "refine-erased")

        // Make Cell is in the Cells group.
        pickTool("fill", in: "Cells", of: app)
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(waitFor(canvas, toMatch: changes("3 changes")), "The fill didn't count: \(canvas.value ?? "")")
        attachScreenshot(of: app, named: "refine-filled")

        // Refine opens on the painting; the Layers panel hides the paint, so the paper shows, and
        // shows it again.
        attachScreenshot(of: app, named: "refine-painting")
        let paint = layerSwitch("paint", in: app)
        XCTAssertEqual(paint.value as? String, "1", "Refine didn't open with the paint showing")
        XCTAssertTrue(flip(paint, on: false), "The paint layer didn't hide")
        attachScreenshot(of: app, named: "refine-layers")
        XCTAssertTrue(flip(paint, on: true), "The paint layer didn't show again")
        closeLayers(in: app)

        // Four fingers: the picture alone, then the tools again from the corner.
        canvas.tap(withNumberOfTaps: 1, numberOfTouches: 4)
        let exit = app.buttons["refine-exit-full-screen"]
        XCTAssertTrue(exit.waitForExistence(timeout: 5), "A four-finger tap didn't show the picture alone")
        XCTAssertTrue(
            waitFor(app.buttons["refine-done"], toMatch: NSPredicate(format: "exists == false")), "The bar still shows in full screen")
        attachScreenshot(of: app, named: "refine-full-screen")
        // In the full screen the bar's Undo is the canvas's ⌘Z (on iPad, a keyboard's).
        if keyboard {
            app.typeKey("z", modifierFlags: .command)
            XCTAssertTrue(waitFor(canvas, toMatch: changes("2 changes")), "⌘Z didn't undo in the full screen")
            app.typeKey("z", modifierFlags: [.command, .shift])
            XCTAssertTrue(waitFor(canvas, toMatch: changes("3 changes")), "⇧⌘Z didn't redo in the full screen")
        }
        exit.tap()
        XCTAssertTrue(app.buttons["refine-done"].waitForExistence(timeout: 5), "The bar didn't come back")

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
        // With a change to lose, Cancel asks first.
        let discard = app.buttons["Discard Changes"]
        XCTAssertTrue(discard.waitForExistence(timeout: 5), "Cancel didn't ask before discarding the change")
        discard.tap()
        XCTAssertTrue(
            waitFor(refine, toMatch: changes("3 changes")),
            "Cancel didn't put back what Refine opened with: \(refine.value ?? "")")
        XCTAssertTrue(
            waitFor(start, toMatch: NSPredicate(format: "isEnabled == true"), timeout: 120), "The refined preview can't be started")
    }

    /// The Pen's line down the sky divides it. Text marks a line of text dragged across; there are no
    /// detail brushes. Done keeps both.
    @MainActor
    func testPenSplitAndTextCorrections() throws {
        let app = launchPreview()
        let refine = app.buttons["refine"]
        refine.tap()
        let canvas = app.descendants(matching: .any)["refine-canvas"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 120), "Refine didn't open")
        XCTAssertFalse(app.buttons["refine-tool-more"].exists, "Refine still has the More Detail brush")

        let pen = app.buttons["refine-tool-pen"]
        XCTAssertTrue(waitFor(pen, toMatch: NSPredicate(format: "isSelected == true")), "Refine doesn't start on the pen")
        // Down the open sky of The Great Wave, from above the wave's outline to inside little Fuji:
        // crossing a line at each end, it divides the sky between them.
        drag(on: canvas, from: onPicture(canvas, 0.637, 0.06), to: onPicture(canvas, 0.637, 0.675))
        XCTAssertTrue(
            waitFor(canvas, toMatch: changes("1 change")), "The line didn't count: \(canvas.value ?? "")")
        attachScreenshot(of: app, named: "refine-pen-split")

        pickTool("text", in: "See", of: app)
        drag(on: canvas, from: CGVector(dx: 0.2, dy: 0.55), to: CGVector(dx: 0.55, dy: 0.6))
        XCTAssertTrue(
            waitFor(canvas, toMatch: changes("2 changes")), "Dragging with Text didn't mark a line: \(canvas.value ?? "")")

        app.buttons["refine-done"].tap()
        XCTAssertTrue(waitFor(refine, toMatch: changes("2 changes")), "Done didn't keep the changes")
    }

    /// A touch held on an area is the Eyedropper, whatever the tool: it makes the area's paint the
    /// current one and draws nothing. Select's Change Color opens the area's card; one of the
    /// painting's paints there gives the area that paint (a change), and Done keeps it.
    @MainActor
    func testHoldPicksAndTheCardGivesAnAreaAnotherPaint() throws {
        let app = launchPreview()
        let refine = app.buttons["refine"]
        refine.tap()
        let canvas = app.descendants(matching: .any)["refine-canvas"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 120), "Refine didn't open")

        // Select tells the sky's paint: the open sky of The Great Wave, above the wave.
        let skyPoint = onPicture(canvas, 0.637, 0.06)
        pickTool("select", in: "Cells", of: app)
        canvas.coordinate(withNormalizedOffset: skyPoint).tap()
        let info = app.descendants(matching: .any)["refine-selection"].descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "of the picture")).firstMatch
        XCTAssertTrue(info.waitForExistence(timeout: 10), "Select didn't show the sky's paint")
        let sky = try XCTUnwrap(paintNumber(in: info.label), "Select's bar names no paint: \(info.label)")

        // With the Bucket in hand and another paint current, a hold on the sky picks the sky's.
        pickTool("bucket", in: "Paint", of: app)
        let other = app.buttons["refine-paint-\(sky == 1 ? 2 : 1)"]
        XCTAssertTrue(other.waitForExistence(timeout: 5), "The palette has no other paint")
        other.tap()
        XCTAssertTrue(waitFor(other, toMatch: NSPredicate(format: "isSelected == true")), "The paint didn't become current")
        canvas.coordinate(withNormalizedOffset: skyPoint).press(forDuration: 1.2)
        XCTAssertTrue(
            waitFor(app.buttons["refine-paint-\(sky)"], toMatch: NSPredicate(format: "isSelected == true")),
            "A hold didn't pick the sky's paint")
        XCTAssertEqual(canvas.value as? String, "No changes", "A hold drew or painted something")
        XCTAssertTrue(app.buttons["refine-tool-bucket"].isSelected, "A hold changed the tool")

        pickTool("select", in: "Cells", of: app)
        canvas.coordinate(withNormalizedOffset: skyPoint).tap()
        let change = app.buttons["refine-selection-color"]
        XCTAssertTrue(change.waitForExistence(timeout: 10), "Select didn't offer Change Color")
        change.tap()
        let card = app.descendants(matching: .any)["refine-card"]
        XCTAssertTrue(card.waitForExistence(timeout: 10), "Change Color didn't open the area's card")
        XCTAssertEqual(canvas.value as? String, "No changes", "Opening the card drew something")
        attachScreenshot(of: app, named: "refine-card")
        let paint = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "refine-card-paint-")).firstMatch
        XCTAssertTrue(paint.waitForExistence(timeout: 5), "The card offers no other paint")
        paint.tap()
        XCTAssertTrue(waitFor(canvas, toMatch: changes("1 change")), "The paint didn't count: \(canvas.value ?? "")")
        // Away from the card: a popover's dismissal region on iPad, the sheet swiped down on iPhone.
        let outside = app.otherElements["PopoverDismissRegion"]
        if outside.exists { outside.tap() } else { card.swipeDown() }
        XCTAssertTrue(waitFor(card, toMatch: NSPredicate(format: "exists == false")), "The card didn't close")
        app.buttons["refine-done"].tap()
        XCTAssertTrue(waitFor(refine, toMatch: changes("1 change")), "Done didn't keep the change")
    }

    /// Select picks the open sky and shows its paint; Cell Edge divides the sky with no line (a
    /// change); the Bucket gives one side another paint from the palette (a second); Merge joins
    /// the two again (a third); the Paint Brush paints a stroke of the sky (a fourth); the Layers
    /// panel shows the photo under the painting, each with its opacity; Done keeps the four changes.
    @MainActor
    func testToolboxSelectsDividesAndPaints() throws {
        let app = launchPreview()
        let refine = app.buttons["refine"]
        refine.tap()
        let canvas = app.descendants(matching: .any)["refine-canvas"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 120), "Refine didn't open")

        pickTool("select", in: "Cells", of: app)
        canvas.coordinate(withNormalizedOffset: onPicture(canvas, 0.637, 0.06)).tap()
        let selection = app.descendants(matching: .any)["refine-selection"]
        XCTAssertTrue(selection.waitForExistence(timeout: 10), "Select didn't show the area")
        let info = selection.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "of the picture")).firstMatch
        XCTAssertTrue(info.waitForExistence(timeout: 5), "Select's bar doesn't say the area's paint")
        let sky = paintNumber(in: info.label)
        XCTAssertNotNil(sky, "Select's bar names no paint: \(info.label)")
        XCTAssertEqual(canvas.value as? String, "No changes", "Selecting changed something")
        attachScreenshot(of: app, named: "refine-select")

        // Down the open sky, from above the wave's outline to inside little Fuji.
        pickTool("cellEdge", in: "Cells", of: app)
        drag(on: canvas, from: onPicture(canvas, 0.637, 0.06), to: onPicture(canvas, 0.637, 0.675))
        XCTAssertTrue(waitFor(canvas, toMatch: changes("1 change")), "The cell edge didn't count: \(canvas.value ?? "")")

        pickTool("bucket", in: "Paint", of: app)
        let other = app.buttons["refine-paint-\(sky == 1 ? 2 : 1)"]
        XCTAssertTrue(other.waitForExistence(timeout: 5), "The palette has no other paint")
        other.tap()
        XCTAssertTrue(waitFor(other, toMatch: NSPredicate(format: "isSelected == true")), "The paint didn't become current")
        canvas.coordinate(withNormalizedOffset: onPicture(canvas, 0.6, 0.06)).tap()
        XCTAssertTrue(waitFor(canvas, toMatch: changes("2 changes")), "The bucket didn't count: \(canvas.value ?? "")")
        attachScreenshot(of: app, named: "refine-bucket")

        pickTool("merge", in: "Cells", of: app)
        // From the area the Bucket painted out into the cloud beside it.
        drag(on: canvas, from: onPicture(canvas, 0.6, 0.06), to: onPicture(canvas, 0.85, 0.25))
        XCTAssertTrue(waitFor(canvas, toMatch: changes("3 changes")), "The merge didn't count: \(canvas.value ?? "")")

        pickTool("brush", in: "Paint", of: app)
        XCTAssertTrue(app.sliders["refine-brush-size"].waitForExistence(timeout: 5), "The brush has no Size")
        // Another paint than the merged sky's, so the stroke changes something.
        let fresh = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND isSelected == false", "refine-paint-")).firstMatch
        XCTAssertTrue(fresh.waitForExistence(timeout: 5), "The palette has no other paint")
        fresh.tap()
        drag(on: canvas, from: onPicture(canvas, 0.3, 0.08), to: onPicture(canvas, 0.45, 0.1))
        XCTAssertTrue(waitFor(canvas, toMatch: changes("4 changes")), "The brush didn't count: \(canvas.value ?? "")")
        attachScreenshot(of: app, named: "refine-brush")

        // The photo under the painting, for tracing: its layer on, its opacity a slider.
        let photo = layerSwitch("photo", in: app)
        XCTAssertEqual(photo.value as? String, "0", "Refine opened with the photo showing")
        XCTAssertTrue(flip(photo, on: true), "The photo layer didn't show")
        XCTAssertTrue(app.sliders["refine-layer-paint-opacity"].exists, "The paint layer has no opacity")
        XCTAssertTrue(app.sliders["refine-layer-photo-opacity"].isEnabled, "The photo layer's opacity is off")
        attachScreenshot(of: app, named: "refine-photo-behind")
        closeLayers(in: app)

        app.buttons["refine-done"].tap()
        XCTAssertTrue(waitFor(refine, toMatch: changes("4 changes")), "Done didn't keep the changes")
    }

    /// The Tool Guide opens on the tool in hand (Merge): its practice canvas merges the moon into
    /// the sky (a change on the practice picture, none on the painting), Reset puts it back, Goes
    /// Well With opens Cell Edge's page on its own canvas, and Done goes back to Refine as it was.
    @MainActor
    func testToolGuidePracticesAndResets() throws {
        let app = launchPreview()
        app.buttons["refine"].tap()
        let canvas = app.descendants(matching: .any)["refine-canvas"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 120), "Refine didn't open")
        pickTool("merge", in: "Cells", of: app)
        app.buttons["refine-guide"].tap()

        let practice = app.descendants(matching: .any)["refine-practice"]
        XCTAssertTrue(practice.waitForExistence(timeout: 60), "The guide didn't open on a practice canvas")
        let pad = practice.descendants(matching: .any)["refine-canvas"]
        XCTAssertTrue(pad.waitForExistence(timeout: 60), "The practice canvas didn't show")
        // The palette shows once the practice picture's template is on the canvas.
        XCTAssertTrue(practice.buttons["refine-paint-1"].waitForExistence(timeout: 60), "The practice picture didn't load")
        XCTAssertTrue(app.descendants(matching: .any)["refine-guide-try"].exists, "Merge's page has no Try This")
        attachScreenshot(of: app, named: "refine-guide")

        // The practice picture is 4 × 3: from the sky into the moon.
        drag(on: pad, from: onPicture(pad, 0.45, 0.2, aspect: 4 / 3), to: onPicture(pad, 0.78, 0.2, aspect: 4 / 3))
        XCTAssertTrue(waitFor(pad, toMatch: changes("1 change")), "The practice merge didn't count: \(pad.value ?? "")")
        let reset = practice.buttons["refine-practice-reset"]
        reset.tap()
        XCTAssertTrue(waitFor(pad, toMatch: changes("No changes")), "Reset didn't put the picture back: \(pad.value ?? "")")

        let related = app.buttons["refine-guide-related-cellEdge"]
        XCTAssertTrue(related.waitForExistence(timeout: 5), "Merge's page doesn't link Cell Edge")
        related.tap()
        XCTAssertTrue(app.switches["refine-snap"].waitForExistence(timeout: 60), "Cell Edge's practice has no Snap")

        app.buttons["refine-guide-done"].firstMatch.tap()
        XCTAssertTrue(waitFor(canvas, toMatch: changes("No changes")), "The practice changed the painting: \(canvas.value ?? "")")
    }

    // MARK: - Helpers

    /// Picks a tool: in the rail where it stands (iPad), else in its group's row (iPhone).
    @MainActor
    @discardableResult
    private func pickTool(_ id: String, in group: String, of app: XCUIApplication) -> XCUIElement {
        let button = app.buttons["refine-tool-\(id)"]
        if !button.exists { app.buttons[group].tap() }
        XCTAssertTrue(button.waitForExistence(timeout: 5), "Refine has no \(id)")
        let selected = NSPredicate(format: "isSelected == true")
        button.tap()
        // A tap CI's simulator lost (October 28, Writing's): picking the tool again changes
        // nothing if the first tap landed after all.
        if !waitFor(button, toMatch: selected) { retapIfLost(id) { button.tap() } }
        XCTAssertTrue(waitFor(button, toMatch: selected, timeout: 5), "\(id) didn't become the tool")
        return button
    }

    /// The paint's number in "…Paint 3 · 2 areas · 40% of the picture".
    private func paintNumber(in label: String) -> Int? {
        guard let range = label.range(of: #"Paint (\d+)"#, options: .regularExpression) else { return nil }
        return Int(label[range].dropFirst("Paint ".count))
    }

    /// A layer's switch in the Layers panel, which this opens.
    @MainActor
    private func layerSwitch(_ layer: String, in app: XCUIApplication) -> XCUIElement {
        let toggle = app.switches["refine-layer-\(layer)"]
        if !toggle.exists { app.buttons["refine-layers"].tap() }
        XCTAssertTrue(toggle.waitForExistence(timeout: 5), "The Layers panel has no \(layer)")
        return toggle
    }

    /// Closes the Layers panel: a popover's dismissal region.
    @MainActor
    private func closeLayers(in app: XCUIApplication) {
        let outside = app.otherElements["PopoverDismissRegion"]
        if outside.exists { outside.tap() }
        let panel = app.descendants(matching: .any)["refine-layers-panel"]
        XCTAssertTrue(waitFor(panel, toMatch: NSPredicate(format: "exists == false")), "The Layers panel didn't close")
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

    /// A point of the picture (fractions of its width and height) as an offset in the canvas,
    /// the whole surface, where the picture is fitted in the middle: by default The Great Wave
    /// (2048 × 1375), `create-preview`'s picture.
    @MainActor
    private func onPicture(_ canvas: XCUIElement, _ x: CGFloat, _ y: CGFloat, aspect: CGFloat = 2048 / 1375) -> CGVector {
        let size = canvas.frame.size
        let width = min(size.width, size.height * aspect), height = width / aspect
        return CGVector(
            dx: ((size.width - width) / 2 + x * width) / size.width,
            dy: ((size.height - height) / 2 + y * height) / size.height)
    }

    /// One finger dragged across `element`, as a line is drawn.
    @MainActor
    private func drag(on element: XCUIElement, from: CGVector, to: CGVector) {
        element.coordinate(withNormalizedOffset: from)
            .press(forDuration: 0.05, thenDragTo: element.coordinate(withNormalizedOffset: to))
    }
}
