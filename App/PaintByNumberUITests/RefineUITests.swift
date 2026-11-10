import XCTest

/// The create flow's optional Refine step, as the Toolbox lays it out in Debug builds (its groups:
/// Ink, Cells, Paint, Numbers, See; a rail of every tool on iPad, tabs on iPhone): the pens, the eraser and
/// Make Cell, Writing's text marks, Select, Cell Edge and the Bucket, an area's card, the
/// Eyedropper's hold, the Layers panel, Undo and Redo (the buttons and two- and three-finger taps),
/// full screen, Done and Cancel; and every other tool, with VoiceOver's cells.
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
        assertLayersClearOfTheBar(in: app)
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
            // A key CI's simulator lost while the bars went (November 5, another branch's run):
            // typed again only if nothing was undone at all.
            if !waitFor(canvas, toMatch: changes("2 changes")), canvas.value as? String == "3 changes" {
                retapIfLost("full-screen undo") { app.typeKey("z", modifierFlags: .command) }
            }
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
            .matching(NSPredicate(format: "label CONTAINS %@", "Paint ")).firstMatch
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
        // Away from the card: a popover's dismissal region on iPad; on iPhone, where it opens in
        // Select's bar over nothing of the picture, the bar's Close.
        let outside = app.otherElements["PopoverDismissRegion"]
        if outside.exists { outside.tap() } else { change.tap() }
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
            .matching(NSPredicate(format: "label CONTAINS %@", "Paint ")).firstMatch
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
    /// the sky (a change on the practice picture, none on the painting), Reset puts it back, the
    /// page's link to Cell Edge opens its page on its own canvas, and Done goes back to Refine as
    /// it was.
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
        XCTAssertTrue(app.descendants(matching: .any)["refine-guide-page"].exists, "Merge's page has no words")
        attachScreenshot(of: app, named: "refine-guide")

        // The practice picture is 4 × 3: from the sky into the moon.
        drag(on: pad, from: onPicture(pad, 0.45, 0.2, aspect: 4 / 3), to: onPicture(pad, 0.78, 0.2, aspect: 4 / 3))
        XCTAssertTrue(waitFor(pad, toMatch: changes("1 change")), "The practice merge didn't count: \(pad.value ?? "")")
        let reset = practice.buttons["refine-practice-reset"]
        reset.tap()
        XCTAssertTrue(waitFor(pad, toMatch: changes("No changes")), "Reset didn't put the picture back: \(pad.value ?? "")")

        let link = app.links["Cell Edge"].firstMatch
        XCTAssertTrue(link.waitForExistence(timeout: 5), "Merge's page doesn't link Cell Edge")
        link.tap()
        XCTAssertTrue(app.switches["refine-snap"].waitForExistence(timeout: 60), "Cell Edge's practice has no Snap")

        app.buttons["refine-guide-done"].firstMatch.tap()
        XCTAssertTrue(waitFor(canvas, toMatch: changes("No changes")), "The practice changed the painting: \(canvas.value ?? "")")
    }

    /// The tools no other test reaches, each on The Great Wave's open sky (phase 3 of
    /// painting-company row 143): VoiceOver's cells (the cells in view, each its paint's number and
    /// name, the selected one marked), the Eyedropper's tap, Move Number, Cell Edge then Move Edge
    /// on it, every figure of Shapes (the curve bent by a second drag), the Pen's line then Bend
    /// Line on it, and a look; each a change, and Done keeps them.
    @MainActor
    func testEveryOtherToolChangesThePicture() throws {
        let app = launchPreview()
        let refine = app.buttons["refine"]
        refine.tap()
        let canvas = app.descendants(matching: .any)["refine-canvas"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 120), "Refine didn't open")
        let sky = onPicture(canvas, 0.637, 0.06)

        // VoiceOver's cells: with a cell tool, the cells in view, at most 40.
        pickTool("select", in: "Cells", of: app)
        let cells = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "refine-cell-"))
        XCTAssertTrue(cells.firstMatch.waitForExistence(timeout: 10), "Select offers VoiceOver no cells")
        XCTAssertLessThanOrEqual(cells.count, 40, "VoiceOver is offered more cells than it can swipe through")
        let first = cells.firstMatch
        XCTAssertNotNil(first.label.range(of: #"^\d+ · "#, options: .regularExpression), "A cell doesn't say its paint: \(first.label)")
        XCTAssertFalse((first.value as? String ?? "").isEmpty, "A cell doesn't say where it is")
        canvas.coordinate(withNormalizedOffset: sky).tap()
        let info = app.descendants(matching: .any)["refine-selection"].descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "Paint ")).firstMatch
        XCTAssertTrue(info.waitForExistence(timeout: 10), "Select didn't show the sky's paint")
        let skyPaint = try XCTUnwrap(paintNumber(in: info.label), "Select's bar names no paint: \(info.label)")
        let chosen = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@ AND isSelected == true", "refine-cell-")).firstMatch
        XCTAssertTrue(chosen.waitForExistence(timeout: 5), "VoiceOver's cells don't mark the selected one")
        XCTAssertTrue(chosen.label.hasPrefix("\(skyPaint) · "), "The selected cell says another paint: \(chosen.label)")
        // The cell's element is at its roomiest number.
        let number = CGPoint(x: chosen.frame.midX, y: chosen.frame.midY)
        attachScreenshot(of: app, named: "refine-select-sky")

        // The Eyedropper's tap: the sky's paint becomes the current one, nothing changes.
        pickTool("bucket", in: "Paint", of: app)
        let other = app.buttons["refine-paint-\(skyPaint == 1 ? 2 : 1)"]
        XCTAssertTrue(other.waitForExistence(timeout: 5), "The palette has no other paint")
        other.tap()
        XCTAssertTrue(waitFor(other, toMatch: NSPredicate(format: "isSelected == true")), "The paint didn't become current")
        pickTool("eyedropper", in: "Paint", of: app)
        canvas.coordinate(withNormalizedOffset: sky).tap()
        XCTAssertTrue(
            waitFor(app.buttons["refine-paint-\(skyPaint)"], toMatch: NSPredicate(format: "isSelected == true")),
            "The Eyedropper's tap didn't pick the sky's paint")
        XCTAssertEqual(canvas.value as? String, "No changes", "The Eyedropper changed the picture")

        // Move Number: the sky's number a little to the left.
        pickTool("moveNumber", in: "Numbers", of: app)
        let origin = app.coordinate(withNormalizedOffset: .zero)
        origin.withOffset(CGVector(dx: number.x, dy: number.y))
            .press(forDuration: 0.05, thenDragTo: origin.withOffset(CGVector(dx: number.x - 12, dy: number.y)))
        XCTAssertTrue(waitFor(canvas, toMatch: changes("1 change")), "Move Number didn't count: \(canvas.value ?? "")")

        // Cell Edge down through the cloud and the open sky below it, then Move Edge bends it to the right.
        pickTool("cellEdge", in: "Cells", of: app)
        drag(on: canvas, from: onPicture(canvas, 0.80, 0.06), to: onPicture(canvas, 0.80, 0.675))
        XCTAssertTrue(waitFor(canvas, toMatch: changes("2 changes")), "The cell edge didn't count: \(canvas.value ?? "")")
        pickTool("moveEdge", in: "Cells", of: app)
        drag(on: canvas, from: onPicture(canvas, 0.80, 0.45), to: onPicture(canvas, 0.83, 0.45))
        XCTAssertTrue(waitFor(canvas, toMatch: changes("3 changes")), "Move Edge didn't count: \(canvas.value ?? "")")
        attachScreenshot(of: app, named: "refine-move-edge")

        // Every figure of Shapes, in the open sky between the wave and the cell edge.
        let shapes = pickTool("shapes", in: "Ink", of: app)
        let figures: [(name: String, from: (CGFloat, CGFloat), to: (CGFloat, CGFloat))] = [
            ("Line", (0.62, 0.40), (0.68, 0.40)), ("Oval", (0.70, 0.38), (0.75, 0.44)),
            ("Hexagon", (0.55, 0.44), (0.60, 0.50)), ("Star", (0.62, 0.44), (0.67, 0.50)),
        ]
        var count = 3
        for figure in figures {
            let button = app.buttons[figure.name]
            XCTAssertTrue(button.waitForExistence(timeout: 5), "Shapes offers no \(figure.name)")
            button.tap()
            XCTAssertTrue(
                waitFor(shapes, toMatch: NSPredicate(format: "value == %@", figure.name)), "\(figure.name) didn't become the figure")
            drag(on: canvas, from: onPicture(canvas, figure.from.0, figure.from.1), to: onPicture(canvas, figure.to.0, figure.to.1))
            count += 1
            XCTAssertTrue(waitFor(canvas, toMatch: changes("\(count) changes")), "The \(figure.name) didn't count: \(canvas.value ?? "")")
        }
        // A curve: a drag for its ends, a second to bend it.
        app.buttons["Curve"].tap()
        XCTAssertTrue(waitFor(shapes, toMatch: NSPredicate(format: "value == %@", "Curve")), "Curve didn't become the figure")
        drag(on: canvas, from: onPicture(canvas, 0.69, 0.48), to: onPicture(canvas, 0.76, 0.48))
        XCTAssertTrue(app.staticTexts["refine-hint"].waitForExistence(timeout: 5), "The curve doesn't say it waits to be bent")
        drag(on: canvas, from: onPicture(canvas, 0.725, 0.48), to: onPicture(canvas, 0.725, 0.45))
        count += 1
        XCTAssertTrue(waitFor(canvas, toMatch: changes("\(count) changes")), "The curve didn't count: \(canvas.value ?? "")")
        attachScreenshot(of: app, named: "refine-shapes")

        // The Pen's line in the open sky under the crest, then Bend Line bows it, free at both
        // ends, to the right across the sky's paints (a bend crosses those, re-cutting them, and
        // one that would reach ink, the crest's spray, goes as far as it can). The drag is 4% of
        // the picture, never under 12 points, which on an iPhone a pan never began from (CI run
        // 825).
        pickTool("pen", in: "Ink", of: app)
        drag(on: canvas, from: onPicture(canvas, 0.44, 0.44), to: onPicture(canvas, 0.44, 0.52))
        count += 1
        XCTAssertTrue(waitFor(canvas, toMatch: changes("\(count) changes")), "The line didn't count: \(canvas.value ?? "")")
        pickTool("bendLine", in: "Ink", of: app)
        let pictureWidth = min(canvas.frame.width, canvas.frame.height * 2048 / 1375)
        drag(on: canvas, from: onPicture(canvas, 0.44, 0.48), to: onPicture(canvas, 0.44 + max(0.04, 12 / pictureWidth), 0.48))
        count += 1
        XCTAssertTrue(waitFor(canvas, toMatch: changes("\(count) changes")), "Bend Line didn't count: \(canvas.value ?? "")")
        attachScreenshot(of: app, named: "refine-bend")

        // A look over every paint.
        pickTool("looks", in: "Paint", of: app)
        let look = app.buttons["refine-look-moonlit"]
        XCTAssertTrue(look.waitForExistence(timeout: 5), "Looks offers no Moonlit")
        look.tap()
        count += 1
        XCTAssertTrue(waitFor(canvas, toMatch: changes("\(count) changes")), "The look didn't count: \(canvas.value ?? "")")
        attachScreenshot(of: app, named: "refine-look")

        app.buttons["refine-done"].tap()
        XCTAssertTrue(waitFor(refine, toMatch: changes("\(count) changes")), "Done didn't keep the changes")
    }

    /// Edit Paint: a swatch dragged onto another makes the two one paint (a change). iPad only:
    /// the system's drag and drop, which synthesized touches drive there.
    @MainActor
    func testEditPaintMergesASwatchIntoAnother() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "A swatch's drag and drop is driven on iPad")
        let app = launchPreview()
        app.buttons["refine"].tap()
        let canvas = app.descendants(matching: .any)["refine-canvas"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 120), "Refine didn't open")
        pickTool("editPaint", in: "Paint", of: app)
        let from = app.buttons["refine-paint-2"], onto = app.buttons["refine-paint-3"]
        XCTAssertTrue(from.waitForExistence(timeout: 5) && onto.exists, "The palette has no paints 2 and 3")
        let swatches = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@ AND identifier != %@", "refine-paint-", "refine-paint-new"))
        let paints = swatches.count
        let dragged = { from.press(forDuration: 1.0, thenDragTo: onto, withVelocity: .slow, thenHoldForDuration: 1.0) }
        dragged()
        // A drag CI's simulator lost while Refine was still opening (October 28): the palette as it
        // was, and the second drag merged the two. Dragged again only if nothing changed at all.
        if !waitFor(canvas, toMatch: changes("1 change"), timeout: 20), canvas.value as? String == "No changes" {
            retapIfLost("swatch drag", dragged)
        }
        XCTAssertTrue(waitFor(canvas, toMatch: changes("1 change")), "Merging two paints didn't count: \(canvas.value ?? "")")
        // The change is the merge, not paint poured on the picture: one paint fewer.
        let merged = XCTNSPredicateExpectation(predicate: NSPredicate(format: "count == %@", NSNumber(value: paints - 1)), object: swatches)
        XCTAssertEqual(XCTWaiter.wait(for: [merged], timeout: 10), .completed, "The palette still has \(swatches.count) paints of \(paints)")
        attachScreenshot(of: app, named: "refine-edit-paint-merged")
    }

    /// A painter's edits survive a base made again (painting-company row 278): a repaint (Edit
    /// Paint's swatch dropped on another, on iPad; a look on iPhone, where a swatch isn't dragged),
    /// a merge, a rub of the Eraser and an Only This Area from an area's card, then a Writing mark,
    /// which makes the base again: the count still says every change, none is said to be left
    /// out, and Done keeps them all.
    @MainActor
    func testEditsSurviveAWritingMark() throws {
        let app = launchPreview()
        let refine = app.buttons["refine"]
        refine.tap()
        let canvas = app.descendants(matching: .any)["refine-canvas"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 120), "Refine didn't open")

        if UIDevice.current.userInterfaceIdiom == .pad {
            pickTool("editPaint", in: "Paint", of: app)
            let from = app.buttons["refine-paint-2"], onto = app.buttons["refine-paint-3"]
            XCTAssertTrue(from.waitForExistence(timeout: 5) && onto.exists, "The palette has no paints 2 and 3")
            let dragged = { from.press(forDuration: 1.0, thenDragTo: onto, withVelocity: .slow, thenHoldForDuration: 1.0) }
            dragged()
            if !waitFor(canvas, toMatch: changes("1 change"), timeout: 20), canvas.value as? String == "No changes" {
                retapIfLost("swatch drag", dragged)
            }
        } else {
            pickTool("looks", in: "Paint", of: app)
            let look = app.buttons["refine-look-moonlit"]
            XCTAssertTrue(look.waitForExistence(timeout: 5), "Looks offers no Moonlit")
            look.tap()
        }
        XCTAssertTrue(waitFor(canvas, toMatch: changes("1 change")), "The repaint didn't count: \(canvas.value ?? "")")

        // From the open sky down into the band of sea under it (the sky is one area already).
        pickTool("merge", in: "Cells", of: app)
        drag(on: canvas, from: onPicture(canvas, 0.75, 0.3), to: onPicture(canvas, 0.75, 0.64))
        XCTAssertTrue(waitFor(canvas, toMatch: changes("2 changes")), "The merge didn't count: \(canvas.value ?? "")")

        // Across little Fuji's outline.
        let eraser = app.buttons["refine-tool-eraser"]
        pickTool("eraser", in: "Ink", of: app)
        XCTAssertTrue(eraser.isSelected)
        drag(on: canvas, from: onPicture(canvas, 0.637, 0.6), to: onPicture(canvas, 0.637, 0.72))
        XCTAssertTrue(waitFor(canvas, toMatch: changes("3 changes")), "The rub didn't count: \(canvas.value ?? "")")

        // Only This Area: the sky left of the crest, another paint from its card.
        pickTool("select", in: "Cells", of: app)
        canvas.coordinate(withNormalizedOffset: onPicture(canvas, 0.3, 0.08)).tap()
        let change = app.buttons["refine-selection-color"]
        XCTAssertTrue(change.waitForExistence(timeout: 10), "Select didn't offer Change Color")
        change.tap()
        let card = app.descendants(matching: .any)["refine-card"]
        XCTAssertTrue(card.waitForExistence(timeout: 10), "Change Color didn't open the area's card")
        let paint = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "refine-card-paint-")).firstMatch
        XCTAssertTrue(paint.waitForExistence(timeout: 5), "The card offers no other paint")
        paint.tap()
        XCTAssertTrue(waitFor(canvas, toMatch: changes("4 changes")), "Only This Area didn't count: \(canvas.value ?? "")")
        let outside = app.otherElements["PopoverDismissRegion"]
        if outside.exists { outside.tap() } else { change.tap() }
        XCTAssertTrue(waitFor(card, toMatch: NSPredicate(format: "exists == false")), "The card didn't close")
        attachScreenshot(of: app, named: "refine-remake-before")

        // A Writing mark: the base is made again, the four edits laid on it.
        pickTool("text", in: "See", of: app)
        drag(on: canvas, from: CGVector(dx: 0.2, dy: 0.55), to: CGVector(dx: 0.55, dy: 0.6))
        let updating = app.staticTexts["Updating…"]
        _ = updating.waitForExistence(timeout: 10)
        XCTAssertTrue(waitFor(updating, toMatch: NSPredicate(format: "exists == false"), timeout: 180), "The base was never made again")
        XCTAssertTrue(
            waitFor(canvas, toMatch: changes("5 changes")), "An edit was left out of the base made again: \(canvas.value ?? "")")
        let note = app.descendants(matching: .any)["refine-note"]
        XCTAssertFalse(
            note.exists && note.label.contains("left out"), "Refine said edits were left out: \(note.label)")
        attachScreenshot(of: app, named: "refine-remake-after")

        app.buttons["refine-done"].tap()
        XCTAssertTrue(waitFor(refine, toMatch: changes("5 changes")), "Done didn't keep the changes")
    }

    /// The Tool Guide opened on its last page shows that page's row whole in the list, where it
    /// was cut in half under the sidebar's bottom edge (QA, November 7). iPad: a sidebar.
    @MainActor
    func testTheGuideShowsTheRowOfThePageItOpensOn() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "A phone's guide opens on the page, not the list")
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "create-refine-guide-writing"]
        app.launch()
        let page = app.descendants(matching: .any)["refine-guide-page"]
        XCTAssertTrue(page.waitForExistence(timeout: 120), "The guide didn't open on Writing")
        let row = app.descendants(matching: .any)["refine-guide-topic-text"]
        XCTAssertTrue(row.waitForExistence(timeout: 10), "The list has no Writing row")
        XCTAssertTrue(
            waitUntil(timeout: 10) { app.windows.firstMatch.frame.contains(row.frame) && row.isHittable },
            "Writing's row isn't whole on screen: \(row.frame)")
        attachScreenshot(of: app, named: "refine-guide-writing-row")
    }

    /// The Layers panel opens below the bar, clear of Done, Undo, Redo and its own button, in
    /// both appearances: hung from the button in the bar, it grew out of it over all four (QA,
    /// November 7).
    @MainActor
    func testTheLayersPanelOpensBelowTheBar() throws {
        defer { XCUIDevice.shared.appearance = .light }
        for (scenario, appearance) in [("create-refine-layers", XCUIDevice.Appearance.light), ("create-refine-layers-dark", .dark)] {
            XCUIDevice.shared.appearance = appearance
            let app = XCUIApplication()
            app.launchArguments = ["-demo", scenario]
            app.launch()
            let panel = app.descendants(matching: .any)["refine-layers-panel"]
            XCTAssertTrue(panel.waitForExistence(timeout: 150), "\(scenario) didn't open the Layers panel")
            assertLayersClearOfTheBar(in: app)
            attachScreenshot(of: app, named: scenario)
            app.terminate()
        }
    }

    /// An area's card: a tap on the words of its Only This Area row opens the color picker, as a
    /// tap on its well does (only the well did, though VoiceOver read the row as the button: QA,
    /// November 7); on iPhone the picker opens at half height, the picture above it undimmed, to
    /// be seen as the color lands (its sheet covered the area), the card under it.
    @MainActor
    func testOnlyThisAreaRowOpensThePicker() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "create-refine-card"]
        app.launch()
        let card = app.descendants(matching: .any)["refine-card"]
        XCTAssertTrue(card.waitForExistence(timeout: 180), "The area's card didn't open")
        let row = app.buttons["refine-card-color"]
        XCTAssertTrue(row.waitForExistence(timeout: 10), "The card has no Only This Area")
        XCTAssertEqual(row.label, "Only This Area", "The row isn't one button named Only This Area")
        // The card's popover (iPad) or band (iPhone) settles before it takes a tap.
        XCTAssertTrue(waitUntil(timeout: 10) { row.isHittable }, "Only This Area can't be tapped")
        sleep(1)
        // The words, at the row's leading end, far from the well at its trailing end.
        row.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.5)).tap()
        let picker = app.otherElements["UIColorPicker"]
        // The picker's own process starts cold on a freshly booted simulator and its first
        // presentation never shows (the Mac's Refine round 2): a second tap asks again, as a
        // painter would, and must open it.
        if !picker.waitForExistence(timeout: 10) {
            attachScreenshot(of: app, named: "refine-card-picker-first-tap")
            // Unless it came just now: a tap outside a picker that is up would close it.
            if !picker.exists { row.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.5)).tap() }
        }
        XCTAssertTrue(picker.waitForExistence(timeout: 15), "Taps on the words didn't open the color picker")
        sleep(1)
        attachScreenshot(of: app, named: "refine-card-picker")
        XCTAssertTrue(card.exists, "The picker closed the card")
        if UIDevice.current.userInterfaceIdiom == .phone {
            let grabber = app.buttons["Sheet Grabber"].firstMatch
            XCTAssertTrue(grabber.exists, "The picker isn't a sheet")
            XCTAssertGreaterThanOrEqual(
                grabber.frame.minY, app.windows.firstMatch.frame.height * 0.45,
                "The color picker opened over most of the screen: its top at \(grabber.frame.minY)")
        }
    }

    /// iPhone: the picture keeps its place and size as the groups change, as Select picks a cell
    /// and as the cell's card opens in Select's band (each moved and shrank it once: QA, November 7).
    @MainActor
    func testThePictureKeepsItsPlaceAcrossTools() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .phone, "The iPad's rail holds every group at once")
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "create-refine"]
        app.launch()
        XCTAssertTrue(app.sliders["refine-pen-smoothing"].waitForExistence(timeout: 180), "Refine never opened on the Pen")
        let canvas = app.descendants(matching: .any)["refine-canvas"]
        sleep(1)
        let opened = canvas.frame
        func kept(_ step: String) {
            XCTAssertTrue(
                waitUntil(timeout: 3) { canvas.frame == opened },
                "The picture moved at \(step): \(canvas.frame), opened at \(opened)")
        }
        for group in ["Cells", "Paint", "Numbers", "See", "Ink"] {
            groupTab(group, of: app).tap()
            kept(group)
        }
        pickTool("select", in: "Cells", of: app)
        canvas.coordinate(withNormalizedOffset: onPicture(canvas, 0.637, 0.06)).tap()
        let change = app.buttons["refine-selection-color"]
        XCTAssertTrue(change.waitForExistence(timeout: 10), "Select didn't offer Change Color")
        kept("Select's cell")
        change.tap()
        XCTAssertTrue(app.descendants(matching: .any)["refine-card"].waitForExistence(timeout: 10), "The card didn't open")
        kept("the card")
        attachScreenshot(of: app, named: "refine-card-in-band")
    }

    /// iPhone: Draw Your Own Lines hangs from the top of the Pen's options, over the picture,
    /// leaving Snap, Color from Photo, the groups and the Pen clear (it hung from the Pen and
    /// covered them: QA, November 7).
    @MainActor
    func testTheDrawTipLeavesThePensOptionsClear() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .phone, "The iPad's tip hangs beside the Pen in the rail")
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "create-refine--tip-refineDraw"]
        app.launch()
        let tip = app.staticTexts["Draw Your Own Lines"].firstMatch
        XCTAssertTrue(tip.waitForExistence(timeout: 180), "The tip never came up")
        sleep(1)
        attachScreenshot(of: app, named: "refine-draw-tip")
        let popover = app.popovers.firstMatch
        let tipFrame = popover.exists ? popover.frame : tip.frame
        for id in ["refine-snap", "refine-pen-colors", "refine-groups", "refine-tool-pen"] {
            let control = app.descendants(matching: .any)[id].firstMatch
            XCTAssertTrue(control.exists, "Refine has no \(id)")
            XCTAssertFalse(tipFrame.intersects(control.frame), "The tip covers \(id): tip \(tipFrame), \(id) \(control.frame)")
        }
    }

    /// iPhone on its side: the picture takes most of the screen's height, and the tools, Start From
    /// and the tiny-numbers badge stand beside it, covering none of it, Done within reach, with the
    /// Pen, with Select's cell and its card, with the looks, and Layers opens: under the tools it
    /// was about 190 × 130 points, the badge over its corner, and gone with the looks (QA,
    /// November 7 and 9).
    @MainActor
    func testThePictureFillsAPhoneOnItsSide() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .phone, "An iPad on its side keeps its rail")
        continueAfterFailure = true
        XCUIDevice.shared.orientation = .landscapeLeft
        addTeardownBlock { @MainActor in XCUIDevice.shared.orientation = .portrait }
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "create-refine"]
        app.launch()
        XCTAssertTrue(app.sliders["refine-pen-smoothing"].waitForExistence(timeout: 180), "Refine never opened on the Pen")
        let canvas = app.descendants(matching: .any)["refine-canvas"]
        sleep(2)
        func clear(_ step: String) {
            let window = app.windows.firstMatch.frame, frame = canvas.frame
            let aspect: CGFloat = 2048 / 1375
            let width = min(frame.width, frame.height * aspect), height = width / aspect
            let picture = CGRect(x: frame.midX - width / 2, y: frame.midY - height / 2, width: width, height: height)
            XCTAssertGreaterThanOrEqual(
                height, window.height * 0.6, "At \(step) the picture is \(picture.size) on a \(window.size) screen")
            for id in ["refine-groups", "refine-tiny", "refine-start", "refine-snap", "refine-selection-color", "refine-card"] {
                let control = app.descendants(matching: .any)[id].firstMatch
                guard control.exists else { continue }
                XCTAssertFalse(control.frame.intersects(picture), "At \(step) \(id) covers the picture: \(control.frame) over \(picture)")
            }
            XCTAssertTrue(app.buttons["refine-done"].isHittable, "At \(step) Done is out of reach")
            holdForScreenshot("landscape-\(step)")
        }
        // Whether the picture has tiny numbers at all is the generator's: CI's iPhone 17 Pro made the
        // demo's picture with none, this Mac's simulators with one (painting-company row 276).
        // Upright, with the Pen and no note, the badge shows whenever there are any: missing beside
        // the picture, it must be missing upright too (else the column gave it way or lost it).
        if !app.buttons["refine-tiny"].waitForExistence(timeout: 10) {
            XCUIDevice.shared.orientation = .portrait
            XCTAssertFalse(
                app.buttons["refine-tiny"].waitForExistence(timeout: 10),
                "The tiny-numbers badge shows upright but isn't beside the picture on its side")
            XCUIDevice.shared.orientation = .landscapeLeft
            XCTAssertTrue(
                waitUntil(timeout: 10) { canvas.frame.width > canvas.frame.height }, "Refine didn't turn back on its side")
            sleep(1)
        }
        clear("pen")
        pickTool("select", in: "Cells", of: app)
        canvas.coordinate(withNormalizedOffset: onPicture(canvas, 0.637, 0.06)).tap()
        let change = app.buttons["refine-selection-color"]
        if change.waitForExistence(timeout: 10) {
            change.tap()
            XCTAssertTrue(app.descendants(matching: .any)["refine-card"].waitForExistence(timeout: 10), "The card didn't open")
            sleep(1)
        } else {
            XCTFail("Select didn't offer Change Color")
        }
        clear("card")
        // The card takes the groups' room beside the picture: closed, they are back.
        if change.exists { change.tap() }
        XCTAssertTrue(app.buttons["Paint"].waitForExistence(timeout: 5), "The groups didn't come back after the card")
        pickTool("looks", in: "Paint", of: app)
        sleep(1)
        clear("looks")
        app.buttons["refine-layers"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["refine-layers-panel"].waitForExistence(timeout: 10), "Layers didn't open")
        sleep(1)
        holdForScreenshot("landscape-layers")
    }

    /// Names the moment and holds it, for a screenshot taken from outside (`xcrun simctl io
    /// <udid> screenshot` on the line `refine-shot: <name>` in the test's output): on its side,
    /// the app's and the screen's own screenshots come out as the upright screen cropped to the
    /// side's shape (iOS 27.2).
    @MainActor
    private func holdForScreenshot(_ name: String) {
        print("refine-shot: \(name)")
        fflush(stdout)
        sleep(4)
    }

    // MARK: - Helpers

    /// The open Layers panel, popover and all, covers none of the bar's Done, Undo, Redo and
    /// Layers buttons, and they are all still there to tap.
    @MainActor
    private func assertLayersClearOfTheBar(in app: XCUIApplication) {
        let panel = app.descendants(matching: .any)["refine-layers-panel"]
        XCTAssertTrue(panel.waitForExistence(timeout: 5), "The Layers panel isn't open")
        let popover = app.popovers.firstMatch
        let covering = popover.exists ? panel.frame.union(popover.frame) : panel.frame
        for control in ["refine-done", "refine-undo", "refine-redo", "refine-layers"] {
            let button = app.buttons[control].firstMatch
            guard button.exists else {
                XCTFail("\(control) is gone under the Layers panel")
                continue
            }
            XCTAssertFalse(button.frame.intersects(covering), "The Layers panel covers \(control): \(covering) over \(button.frame)")
        }
    }

    /// Picks a tool: in the rail where it stands (iPad), else in its group's row (iPhone).
    @MainActor
    @discardableResult
    private func pickTool(_ id: String, in group: String, of app: XCUIApplication) -> XCUIElement {
        let button = app.buttons["refine-tool-\(id)"]
        if !button.exists { groupTab(group, of: app).tap() }
        XCTAssertTrue(button.waitForExistence(timeout: 5), "Refine has no \(id)")
        let selected = NSPredicate(format: "isSelected == true")
        button.tap()
        // A tap CI's simulator lost (October 28, Writing's): picking the tool again changes
        // nothing if the first tap landed after all.
        if !waitFor(button, toMatch: selected) { retapIfLost(id) { button.tap() } }
        XCTAssertTrue(waitFor(button, toMatch: selected, timeout: 5), "\(id) didn't become the tool")
        return button
    }

    /// A group's tab on iPhone, in Refine's own chooser (the segmented control upright, the
    /// column's buttons on its side, both `refine-groups`): the gallery's Paint (+) lies under
    /// Refine and answers to the Paint group's name too (Paint Now, November 9).
    @MainActor
    private func groupTab(_ group: String, of app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["refine-groups"].firstMatch.buttons[group]
    }

    /// The paint's number in "…Paint 3 · 2 areas".
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
