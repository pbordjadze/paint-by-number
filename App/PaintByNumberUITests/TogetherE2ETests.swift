#if DEBUG
import Foundation
import XCTest

/// Paint Together end to end on a real device (painting-company row 350): the device's side of
/// `tools/together-e2e/run.sh`, which has a second device call this one over FaceTime and start
/// Paint Together. This test answers the call, joins SharePlay, waits for the friend's painting
/// to open and paints in it, while the app's `-tourLog` keeps every frame and every fill sent and
/// received (`together` lines) for `tools/together-e2e/summary.py`.
///
/// It skips unless `TOGETHER_E2E` is set (CI's UI test runs take every class), so run it alone:
/// `-only-testing:PaintByNumberUITests/TogetherE2ETests` with `TEST_RUNNER_TOGETHER_E2E=guest`.
/// Knobs, all `TEST_RUNNER_`-prefixed in xcodebuild's environment:
///   TOGETHER_CALL_WAIT  seconds to wait for the call and then for SharePlay (default 300)
///   TOGETHER_FILLS      areas to paint once the painting is open (default 40)
///   TOGETHER_INTERVAL   seconds between fills (default 0.5)
///   TOGETHER_HOLD       seconds to stay in the painting afterwards, receiving (default 60)
/// It prints `TOGETHERMARK <what> <epoch s>` lines (the device's clock, which the log shares).
/// The system's own UI (the call's Accept, SharePlay's Join) is found by label in SpringBoard
/// and the call screen, since their identifiers aren't public; `labels` lists what it looks for.
@MainActor
final class TogetherE2ETests: XCTestCase {
    private let environment = ProcessInfo.processInfo.environment
    private let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    private let callScreen = XCUIApplication(bundleIdentifier: "com.apple.InCallService")
    private let faceTime = XCUIApplication(bundleIdentifier: "com.apple.facetime")

    private func number(_ key: String, _ fallback: Double) -> Double {
        environment[key].flatMap(Double.init) ?? fallback
    }

    private func mark(_ what: String) {
        print(String(format: "TOGETHERMARK %@ %.4f", what, Date().timeIntervalSince1970))
    }

    func testGuest() async throws {
        try XCTSkipUnless(environment["TOGETHER_E2E"] == "guest", "Runs only when asked for (TOGETHER_E2E=guest)")
        continueAfterFailure = false
        let wait = number("TOGETHER_CALL_WAIT", 300)
        let app = XCUIApplication()
        app.launchArguments = ["-tourLog", "YES", "-playHarness"]
        app.launch()
        mark("launched")

        try await press(["Accept", "Answer", "Accept call", "Join"], within: wait, what: "the incoming call's Accept")
        mark("call-accepted")

        // SharePlay offers the friend's activity once they start it: a banner or the call's
        // controls, which say Open or Join. The app may also join by itself if it is in front.
        let canvas = app.descendants(matching: .any)["play-state"]
        let deadline = Date().addingTimeInterval(wait)
        var joined = false
        while Date() < deadline, !canvas.exists {
            if !joined, let button = find(["Join SharePlay", "Open", "Join", "SharePlay"], in: [springboard, callScreen, faceTime, app]) {
                button.tap()
                joined = true
                mark("shareplay-tapped")
            }
            try await Task.sleep(for: .milliseconds(500))
            if app.state != .runningForeground, joined { app.activate() }
        }
        guard canvas.exists else {
            attachScreenshot("no-painting")
            throw PlayFailure("The friend's painting never opened")
        }
        mark("painting-open")
        attachScreenshot("painting-open")

        let fills = Int(number("TOGETHER_FILLS", 40))
        let interval = number("TOGETHER_INTERVAL", 0.5)
        var painted = 0
        mark("fills-begin")
        while painted < fills {
            guard try await paintOne(app) else { break }
            painted += 1
            try await Task.sleep(for: .seconds(interval))
        }
        mark("fills-end")
        print("TOGETHERFILLS \(painted)")

        try await Task.sleep(for: .seconds(number("TOGETHER_HOLD", 60)))
        mark("hold-end")
        attachScreenshot("end")
    }

    /// Taps one unpainted area of the selected paint (or the next paint with any left): the
    /// play harness's `area-N` buttons are valued with their paint.
    private func paintOne(_ app: XCUIApplication) async throws -> Bool {
        guard let json = app.descendants(matching: .any)["play-state"].value as? String else { return false }
        let state = try PlayState(data: Data(json.utf8))
        let filled = Set(state.filledAreas)
        guard filled.count < state.areaCount else { return false }
        let canvasFrame = app.descendants(matching: .any)["canvas"].frame
        let areas = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'area-'")).allElementsBoundByIndex
        var other: (area: XCUIElement, paint: Int)?
        for area in areas {
            guard let n = Int(area.identifier.dropFirst(5)), !filled.contains(n),
                  let paint = (area.value as? String).flatMap(Int.init),
                  canvasFrame.contains(area.frame) else { continue }
            if paint == state.selectedPaint {
                area.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
                return true
            }
            if other == nil, app.buttons["swatch-\(paint)"].isHittable { other = (area, paint) }
        }
        guard let other else { return false }
        app.buttons["swatch-\(other.paint)"].tap()
        try await Task.sleep(for: .milliseconds(300))
        other.area.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        return true
    }

    private func press(_ labels: [String], within seconds: Double, what: String) async throws {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if let button = find(labels, in: [springboard, callScreen, faceTime]) {
                button.tap()
                return
            }
            try await Task.sleep(for: .milliseconds(500))
        }
        attachScreenshot("missing")
        throw PlayFailure("No \(what) within \(Int(seconds)) s")
    }

    private func find(_ labels: [String], in apps: [XCUIApplication]) -> XCUIElement? {
        for app in apps {
            for label in labels {
                let button = app.buttons.matching(NSPredicate(format: "label ==[c] %@", label)).firstMatch
                if button.exists, button.isHittable { return button }
            }
        }
        return nil
    }

    private func attachScreenshot(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
#endif
