import XCTest

/// What every UI test shares: attachments the CI report keys on by name, a polling wait, the way
/// into Settings and the check that a confirmation dialog points at what asked for it.
extension XCTestCase {
    @MainActor
    func attach(_ screenshot: XCUIScreenshot, named name: String) {
        let shot = XCTAttachment(screenshot: screenshot)
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    @MainActor
    func attachScreenshot(of app: XCUIApplication, named name: String) {
        attach(app.screenshot(), named: name)
    }

    /// The app's accessibility tree, for a failure's diagnosis.
    @MainActor
    func attachTree(of app: XCUIApplication, named name: String) {
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = name
        tree.lifetime = .keepAlways
        add(tree)
    }

    /// Polls `condition` four times a second until it holds or `timeout` passes.
    @MainActor
    func waitUntil(timeout: TimeInterval = 5, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            Thread.sleep(forTimeInterval: 0.25)
        }
        return condition()
    }

    /// Waits for `element` to match `predicate`. Read right after the action that changes it, a
    /// value or selection can still be the old one on CI's busy simulators, where XCUITest's wait
    /// for an idle app gives up: the typed comment of `FeedbackUITests` once read empty.
    @MainActor
    func waitFor(_ element: XCUIElement, toMatch predicate: NSPredicate, timeout: TimeInterval = 10) -> Bool {
        XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element)], timeout: timeout) == .completed
    }

    /// A tap that changed nothing is tapped once more. On the iPad simulator of GitHub's macOS 26
    /// image of October 13, 2026, a tap in Settings' tests is now and then lost: a switch never
    /// moves, or the gallery's Settings button opens nothing, while the app's main thread is free
    /// and its tree shows nothing in the way (the earlier image and the iPhone never lost one). The
    /// whole screen, system overlays included, is attached as `lost-tap-<what>` for the diagnosis,
    /// and the second tap is an activity the test's log shows.
    @MainActor
    func retapIfLost(_ what: String, _ tap: () -> Void) {
        attach(XCUIScreen.main.screenshot(), named: "lost-tap-\(what)")
        XCTContext.runActivity(named: "The tap on \(what) was lost: tapping again") { _ in tap() }
    }

    /// Turns a Settings switch on or off, tapping the switch itself at its row's trailing end, and
    /// says whether it got there (a lost tap: `retapIfLost`).
    @MainActor
    func flip(_ toggle: XCUIElement, on: Bool) -> Bool {
        let target = NSPredicate(format: "value == %@", on ? "1" : "0")
        let tap = { toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap() }
        tap()
        if waitFor(toggle, toMatch: target, timeout: 3) { return true }
        retapIfLost(toggle.label, tap)
        return waitFor(toggle, toMatch: target, timeout: 5)
    }

    /// A note among the test's results: what a failure needs explained.
    @MainActor
    func attachNote(_ text: String, named name: String) {
        let note = XCTAttachment(string: text)
        note.name = name
        note.lifetime = .keepAlways
        add(note)
    }

    /// The first element showing exactly `label`, whatever its kind.
    @MainActor
    func element(labeled label: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    /// Waits for a confirmation dialog to show `labels` (its title, its message, its buttons) and
    /// checks it points at `source`, the card or button whose action asked for it. A
    /// `.confirmationDialog` is a popover (iPhone too) anchored to the view that carries the
    /// modifier: one on a whole screen opened at the screen's middle, near its top, whichever card
    /// was chosen. The dialog's content (the smallest rectangle holding every label) must lie within
    /// `reach` of the source (the arrow is 13 pt long), with the arrow, which points at the source's
    /// center, over the content: the popover is above or below the source, or beside it where the
    /// source sits at the screen's edge (More, the draft row's Discard). The screen and the measures
    /// (the app's tree too when the check fails) are attached as `dialog-…-<what>`. Returns the
    /// content's frame, nil when the dialog never came up.
    @MainActor
    @discardableResult
    func checkDialog(showing labels: [String], pointsAt source: CGRect, _ what: String, in app: XCUIApplication) -> CGRect? {
        var dialog = CGRect.null
        var missing: [String] = []
        for label in labels {
            let shown = element(labeled: label, in: app)
            if shown.waitForExistence(timeout: dialog.isNull ? 10 : 2) {
                dialog = dialog.union(shown.frame)
            } else {
                missing.append(label)
            }
        }
        attachScreenshot(of: app, named: "dialog-\(what)")
        guard !dialog.isNull else {
            attachTree(of: app, named: "dialog-tree-\(what)")
            XCTFail("\(what): no confirmation dialog on screen")
            return nil
        }
        let reach: CGFloat = 40
        // The arrow ends inside the popover's rounded body, so within the padding of its content.
        let slack: CGFloat = 24
        let gapX = max(0, source.minX - dialog.maxX, dialog.minX - source.maxX)
        let gapY = max(0, source.minY - dialog.maxY, dialog.minY - source.maxY)
        let aboveOrBelow = gapY <= reach && (dialog.minX - slack...dialog.maxX + slack).contains(source.midX)
        let beside = gapX <= reach && (dialog.minY - slack...dialog.maxY + slack).contains(source.midY)
        attachNote(
            "dialog \(dialog.integral)\nsource \(source.integral)\ngap x \(Int(gapX)), y \(Int(gapY)) pt (reach \(Int(reach)))\n"
                + "arrow over the content: above or below \(aboveOrBelow), beside \(beside)\nmissing \(missing)",
            named: "dialog-measure-\(what)")
        if !missing.isEmpty || !(aboveOrBelow || beside) { attachTree(of: app, named: "dialog-tree-\(what)") }
        XCTAssertTrue(missing.isEmpty, "\(what): the dialog doesn't show \(missing)")
        XCTAssertTrue(
            aboveOrBelow || beside,
            "\(what): the dialog \(dialog.integral) doesn't point at what asked for it, \(source.integral) (gap x \(Int(gapX)), y \(Int(gapY)))")
        return dialog
    }

    /// Closes a dialog without choosing: Cancel where it has one, else a tap on the window's edge
    /// farthest from it (a popover closes on a tap outside it, which it swallows).
    @MainActor
    func dismissDialog(at dialog: CGRect, titled title: String, in app: XCUIApplication) {
        let cancel = app.buttons["Cancel"]
        if cancel.exists {
            cancel.tap()
        } else {
            let window = app.windows.firstMatch
            let y: CGFloat = dialog.midY > window.frame.midY ? 0.03 : 0.97
            window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: y)).tap()
        }
        XCTAssertTrue(element(labeled: title, in: app).waitForNonExistence(timeout: 10), "“\(title)” stayed on screen")
    }

    /// Opens Settings the way a person does: from the gallery's toolbar.
    @MainActor
    func openSettings() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "gallery-empty"]
        app.launch()
        let button = app.buttons["Settings"]
        XCTAssertTrue(button.waitForExistence(timeout: 30), "The gallery has no Settings button")
        let sheet = app.navigationBars["Settings"]
        button.tap()
        if !sheet.waitForExistence(timeout: 5) { retapIfLost("Settings") { button.tap() } }
        XCTAssertTrue(sheet.waitForExistence(timeout: 10), "The settings sheet didn't open")
        return app
    }
}
