import XCTest

/// What every UI test shares: attachments the CI report keys on by name, a polling wait and the
/// way into Settings.
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
