import XCTest

/// Refine driven for a side-by-side look at two builds (painting-company row 338's review): its
/// fades and landings recorded, and stills of its demo scenarios to compare pixel for pixel.
/// Skipped unless `tools/refine-eye/run_eye.sh` runs it (it sets `TEST_RUNNER_EYE_OUT`), so the
/// UI test runs on CI pass it by.
///
/// How to run (on a Mac, a simulator of your own, an iPad Pro 13-inch):
///   copy this file into each worktree's `App/PaintByNumberUITests/` (the folder is synced), then
///   `tools/refine-eye/run_eye.sh <worktree> <tag> <udid> <out dir> [testEyeCases|testEyeMarkedLook|testEyeStates|testEyeStartFrom|testEyeStills]`
///   for each build, and `tools/refine-eye/eye.py` on what it wrote (its header).
/// Each action is preceded by `eye: <step> <epoch>` in the test's output, which `eye.py` lines up
/// with the recording; `eye-frame <name>: x y w h` gives an element's frame in points for a crop.
/// The drags assume The Great Wave (`create-refine`'s picture, 2048 × 1375).
final class EyeCheckUITests: XCTestCase {
    private var out: String?

    override func setUpWithError() throws {
        out = ProcessInfo.processInfo.environment["EYE_OUT"]
        try XCTSkipIf(out == nil, "Run by tools/refine-eye/run_eye.sh only")
    }

    /// The cases of row 338's review: (a) a hidden layer shown again by its tool and by the panel,
    /// (d) by a touch, (b) a look landing, (e) ordinary use.
    @MainActor
    func testEyeCases() throws {
        let app = launch("create-refine")
        let canvas = app.descendants(matching: .any)["refine-canvas"]
        _ = app.buttons["refine-tiny"].waitForExistence(timeout: 30)
        sleep(3)
        note("canvas", canvas.frame)
        if app.buttons["refine-tiny"].exists { note("tiny", app.buttons["refine-tiny"].frame) }
        mark("ready"); sleep(2)

        // (a) A layer hidden, then its tool picked; then the panel's own switches.
        set("paint", false, app); closeLayers(app); sleep(1)
        mark("a-bucket"); pickTool("bucket", app); sleep(2)
        set("ink", false, app); closeLayers(app); sleep(1)
        mark("a-pen"); pickTool("pen", app); sleep(2)
        mark("a-photo-on"); set("photo", true, app); sleep(2)
        mark("a-photo-off"); set("photo", false, app); sleep(2)
        mark("a-paint-panel-off"); set("paint", false, app); sleep(2)
        mark("a-paint-panel-on"); set("paint", true, app); sleep(2)
        closeLayers(app); sleep(1)

        // (d) The ink hidden while its tool is picked, then a touch brings it back.
        set("ink", false, app); closeLayers(app); sleep(1)
        mark("d-pen-stroke"); drag(canvas, (0.44, 0.44), (0.44, 0.52)); sleep(2)
        pickTool("shapes", app); sleep(1)
        app.buttons["Curve"].tap(); sleep(1)
        set("ink", false, app); closeLayers(app); sleep(1)
        mark("d-curve"); drag(canvas, (0.69, 0.48), (0.76, 0.48)); sleep(2)
        if app.staticTexts["refine-hint"].exists { note("hint", app.staticTexts["refine-hint"].frame) }
        mark("d-curve-bend"); drag(canvas, (0.725, 0.48), (0.725, 0.45)); sleep(2)

        // (b) A look lands.
        pickTool("looks", app); sleep(1)
        mark("b-look"); app.buttons["refine-look-moonlit"].tap(); sleep(3)

        // (e) Ordinary use: Select and a tap, another tool's options, full screen and back.
        mark("e-select"); pickTool("select", app); sleep(2)
        mark("e-select-tap"); canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25)).tap(); sleep(2)
        mark("e-eraser"); pickTool("eraser", app); sleep(2)
        mark("e-fullscreen"); app.typeKey("f", modifierFlags: [.command, .control]); sleep(2)
        mark("e-fullscreen-off"); app.typeKey("f", modifierFlags: [.command, .control]); sleep(2)
        mark("end")
    }

    /// (b) with the tiny badge's mark first: a look lands while a tiny number is marked (the note a
    /// look raises hides the badge, so this starts from a fresh launch).
    @MainActor
    func testEyeMarkedLook() throws {
        let app = launch("create-refine")
        let tiny = app.buttons["refine-tiny"]
        XCTAssertTrue(tiny.waitForExistence(timeout: 60), "No tiny badge")
        sleep(3)
        mark("m-tiny-tap"); tiny.tap(); sleep(3)
        pickTool("looks", app); sleep(2)
        mark("m-look"); app.buttons["refine-look-moonlit"].tap(); sleep(4)
        mark("m-end")
    }

    /// Stills of Refine's demo scenarios, 12 s after each opens, as `<out>/shots/<tag>-<scenario>.png`
    /// (`EYE_BUILD` is the tag), for `eye.py stills` to compare between builds.
    @MainActor
    func testEyeStills() throws {
        for scenario in ["create-refine", "create-refine-colors", "create-refine-card", "create-refine-select", "create-refine-layers"] {
            let app = launch(scenario)
            sleep(12)
            try still(scenario)
            app.terminate()
        }
    }

    /// States a review flagged as never seen changing twice (row 338, round 4), each held for a
    /// still (`<out>/shots/<tag>-state-<n>-<name>.png`) and marked for the recording: the layers
    /// after a landing, the numbers shown and hidden every way, the paint's opacity, the tool
    /// options changing, a landing that renumbers the paints and the badge after it.
    /// (`create-refine` opens with edits made, so Start From is `testEyeStartFrom`'s.)
    @MainActor
    func testEyeStates() throws {
        let app = launch("create-refine")
        let canvas = app.descendants(matching: .any)["refine-canvas"]
        _ = app.buttons["refine-tiny"].waitForExistence(timeout: 30)
        sleep(3)
        var n = 0
        func state(_ name: String) throws {
            sleep(3)
            n += 1
            let shot = String(format: "state-%02d-%@", n, name)
            try still(shot)
            // What the panel shows, if it is open: stills compare only where both builds got here.
            let shown = ["numbers", "ink", "paint", "photo"].map { layer in
                "\(layer)=\(app.switches["refine-layer-\(layer)"].firstMatch.exists ? (app.switches["refine-layer-\(layer)"].value as? String ?? "?") : "-")"
            }
            let opacity = app.sliders["refine-layer-paint-opacity"]
            print("eye-state \(shot): \(shown.joined(separator: " ")) opacity=\(opacity.exists ? (opacity.value as? String ?? "?") : "-")")
        }
        try state("open")

        // A landing first: a line of the Pen's.
        pickTool("pen", app)
        mark("landing"); landing(on: canvas) { drag(canvas, (0.44, 0.44), (0.44, 0.52)) }
        try state("landed")

        // (a) Ink off, on, off again, after the landing.
        mark("a-ink-off"); set("ink", false, app); try state("ink-off")
        mark("a-ink-on"); set("ink", true, app); try state("ink-on")
        mark("a-ink-off-2"); set("ink", false, app); try state("ink-off-2")
        set("ink", true, app)
        // (b) Numbers on, off, on.
        mark("b-numbers-on"); set("numbers", true, app); try state("numbers-on")
        mark("b-numbers-off"); set("numbers", false, app); try state("numbers-off")
        mark("b-numbers-on-2"); set("numbers", true, app); try state("numbers-on-2")
        set("numbers", false, app)
        // (c) The paint's opacity across a half; the photo on with the numbers.
        mark("c-opacity-30"); paintOpacity(30, app); try state("opacity-30")
        mark("c-opacity-70"); paintOpacity(70, app); try state("opacity-70")
        mark("c-opacity-100"); paintOpacity(100, app); try state("opacity-100")
        mark("c-photo-numbers"); set("photo", true, app); set("numbers", true, app); try state("photo-numbers")
        set("photo", false, app); set("numbers", false, app)
        closeLayers(app)

        // (b) The Numbers group chosen and left; the badge's mark, then a touch.
        mark("b-numbers-group"); pickTool("moveNumber", app); try state("numbers-group")
        mark("b-numbers-left"); pickTool("pen", app); try state("numbers-left")
        let tiny = app.buttons["refine-tiny"]
        if tiny.exists {
            mark("b-tiny-mark"); tiny.tap(); try state("tiny-marked")
            mark("b-tiny-touch"); canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15)).tap(); try state("tiny-touched")
        }

        // (e) The tool options: Pen, Eraser, Shapes, Pen.
        mark("e-eraser"); pickTool("eraser", app); try state("eraser")
        mark("e-shapes"); pickTool("shapes", app); try state("shapes")
        mark("e-pen"); pickTool("pen", app); try state("pen")

        // (d) A look makes paints alike, which then share a number: a landing that renumbers;
        // (e) the badge after it, a second landing.
        pickTool("looks", app); sleep(1)
        mark("d-renumber"); landing(on: canvas) { app.buttons["refine-look-moonlit"].tap() }
        sleep(6)  // past the note the look raises
        try state("renumbered")
        mark("end")
    }

    /// (e) Start From, on a Refine opened fresh from the preview: shown, gone with the first
    /// edit, back with its undo, gone with its redo.
    @MainActor
    func testEyeStartFrom() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "create-preview", "-demoFixedPictures", "YES"]
        app.launch()
        let refine = app.buttons["refine"]
        XCTAssertTrue(refine.waitForExistence(timeout: 120), "The preview didn't open")
        let on = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == true"), object: refine)
        XCTAssertEqual(XCTWaiter.wait(for: [on], timeout: 240), .completed, "Refine never came on")
        refine.tap()
        let canvas = app.descendants(matching: .any)["refine-canvas"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 120), "Refine didn't open")
        sleep(5)
        try still("start-1-shown")
        pickTool("pen", app)
        mark("start-gone"); landing(on: canvas) { drag(canvas, (0.44, 0.44), (0.44, 0.52)) }
        sleep(3); try still("start-2-gone")
        mark("start-back"); landing(on: canvas) { app.buttons["refine-undo"].tap() }
        sleep(3); try still("start-3-back")
        mark("start-gone-2"); landing(on: canvas) { app.buttons["refine-redo"].tap() }
        sleep(3); try still("start-4-gone")
        mark("end")
    }

    // MARK: - Helpers

    /// Does what lands an edit and waits for the canvas's count of changes to move; a gesture the
    /// simulator lost (a loaded Mac loses some) is done once more, said as `eye-retry <step>`, so
    /// the two builds still reach the same state and the losses can be counted.
    @MainActor
    private func landing(on canvas: XCUIElement, _ action: () -> Void) {
        let before = canvas.value as? String ?? ""
        let moved = { XCTNSPredicateExpectation(predicate: NSPredicate(format: "value != %@", before), object: canvas) }
        action()
        if XCTWaiter.wait(for: [moved()], timeout: 20) == .completed { return }
        print("eye-retry landing from \(before)")
        action()
        XCTAssertEqual(XCTWaiter.wait(for: [moved()], timeout: 30), .completed, "Nothing landed: still \(before)")
    }

    /// The screen as `<out>/shots/<tag>-<name>.png`.
    @MainActor
    private func still(_ name: String) throws {
        let build = ProcessInfo.processInfo.environment["EYE_BUILD"] ?? "build"
        let shots = URL(fileURLWithPath: try XCTUnwrap(out)).appendingPathComponent("shots")
        try FileManager.default.createDirectory(at: shots, withIntermediateDirectories: true)
        try XCUIScreen.main.screenshot().pngRepresentation.write(to: shots.appendingPathComponent("\(build)-\(name).png"))
    }

    @MainActor
    private func launch(_ scenario: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", scenario]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["refine-canvas"].waitForExistence(timeout: 240), "\(scenario) didn't open")
        return app
    }

    /// The moment just before an action, for the recording.
    private func mark(_ step: String) {
        print(String(format: "eye: %@ %.3f", step, Date().timeIntervalSince1970))
        fflush(stdout)
    }

    /// An element's frame in points (the screen's pixels are twice that on an iPad Pro).
    private func note(_ name: String, _ rect: CGRect) {
        print("eye-frame \(name): \(Int(rect.minX)) \(Int(rect.minY)) \(Int(rect.width)) \(Int(rect.height))")
        fflush(stdout)
    }

    @MainActor
    private func pickTool(_ id: String, _ app: XCUIApplication) {
        let button = app.buttons["refine-tool-\(id)"]
        XCTAssertTrue(button.waitForExistence(timeout: 5), "Refine has no \(id)")
        button.tap()
    }

    /// Sets a layer's switch by its knob (XCUITest's tap on a SwiftUI Toggle lands on its label
    /// and flips nothing), tapping again until it shows `on` (a loaded Mac takes a tap late or
    /// loses it: each tap again is said as `eye-retry`). Opens the Layers panel if it isn't.
    @MainActor
    private func set(_ layer: String, _ on: Bool, _ app: XCUIApplication) {
        let toggle = app.switches["refine-layer-\(layer)"]
        if !toggle.exists { app.buttons["refine-layers"].tap() }
        XCTAssertTrue(toggle.waitForExistence(timeout: 5), "The Layers panel has no \(layer)")
        let wanted = on ? "1" : "0"
        for attempt in 0..<4 {
            if toggle.value as? String == wanted { return }
            if attempt > 0 { print("eye-retry set \(layer) \(wanted)") }
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
            let shows = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", wanted), object: toggle)
            if XCTWaiter.wait(for: [shows], timeout: 10) == .completed { return }
        }
        print("eye-retry set \(layer) gave up")
    }

    /// Moves the paint's opacity to `percent`, again until it says so.
    @MainActor
    private func paintOpacity(_ percent: Int, _ app: XCUIApplication) {
        let slider = app.sliders["refine-layer-paint-opacity"]
        XCTAssertTrue(slider.waitForExistence(timeout: 5), "No paint opacity")
        for attempt in 0..<4 {
            if attempt > 0 { print("eye-retry opacity \(percent)") }
            slider.adjust(toNormalizedSliderPosition: CGFloat(percent) / 100)
            sleep(2)
            if (slider.value as? String)?.hasPrefix("\(percent)") == true { return }
        }
        print("eye-retry opacity gave up at \(slider.value ?? "")")
    }

    @MainActor
    private func closeLayers(_ app: XCUIApplication) {
        let outside = app.otherElements["PopoverDismissRegion"]
        if outside.exists { outside.tap() }
        _ = app.descendants(matching: .any)["refine-layers-panel"].waitForNonExistence(timeout: 5)
    }

    /// One finger dragged between two points of the picture (fractions of its width and height).
    @MainActor
    private func drag(_ canvas: XCUIElement, _ from: (CGFloat, CGFloat), _ to: (CGFloat, CGFloat)) {
        let size = canvas.frame.size, aspect: CGFloat = 2048 / 1375
        let width = min(size.width, size.height * aspect), height = width / aspect
        func at(_ p: (CGFloat, CGFloat)) -> XCUICoordinate {
            canvas.coordinate(withNormalizedOffset: CGVector(
                dx: ((size.width - width) / 2 + p.0 * width) / size.width,
                dy: ((size.height - height) / 2 + p.1 * height) / size.height))
        }
        at(from).press(forDuration: 0.05, thenDragTo: at(to))
    }
}
