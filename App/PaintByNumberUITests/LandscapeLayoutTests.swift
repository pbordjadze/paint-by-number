import UIKit
import XCTest

/// iPad layouts in landscape (the CI screenshot pass is portrait only). Each test attaches a
/// screenshot for review, then runs the system accessibility audit on the screen: all issues
/// are attached (`accessibility-<screen>`); missing labels and small hit regions fail.
final class LandscapeLayoutTests: XCTestCase {
    /// The palette (along the trailing edge) shows every color without scrolling.
    @MainActor
    func testPaintingPaletteAlongTrailingEdge() throws {
        let app = try launchInLandscape("paint-progress")
        XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: 60))
        sleep(3)
        attachScreenshot(of: app, named: "landscape-paint-progress")
        let swatches = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'swatch-'")).allElementsBoundByIndex
        XCTAssertFalse(swatches.isEmpty)
        let window = app.windows.firstMatch.frame
        for swatch in swatches {
            XCTAssertTrue(window.contains(swatch.frame), "\(swatch.label) is scrolled out of view")
        }
        // The canvas's VoiceOver areas are part of the audit below; they must be big enough to hit.
        let areas = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'canvas-area-'")).allElementsBoundByIndex
        XCTAssertFalse(areas.isEmpty, "The canvas offers no areas to VoiceOver")
        for area in areas {
            XCTAssertGreaterThanOrEqual(min(area.frame.width, area.frame.height), 43.5, "\(area.identifier) is too small")
            XCTAssertFalse(area.label.isEmpty)
        }
        try audit(app, named: "paint-progress")
    }

    @MainActor
    func testCreatePreview() throws {
        let app = try launchInLandscape("create-preview")
        let start = app.buttons["Start Painting"]
        XCTAssertTrue(start.waitForExistence(timeout: 30))
        expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: start)
        waitForExpectations(timeout: 60)
        sleep(1)
        attachScreenshot(of: app, named: "landscape-create-preview")
        try audit(app, named: "create-preview")
    }

    @MainActor
    func testGallery() throws {
        let app = try launchInLandscape("gallery")
        let preparing = app.staticTexts["Preparing…"]
        XCTAssertTrue(app.buttons["New Painting"].waitForExistence(timeout: 30))
        let deadline = Date.now.addingTimeInterval(120)
        while preparing.exists && Date.now < deadline { sleep(1) }
        sleep(2)
        attachScreenshot(of: app, named: "landscape-gallery")
        XCTAssertFalse(preparing.exists, "Samples were still being prepared")
        try audit(app, named: "gallery")
    }

    /// Collects issues from the audit's handler, whatever its isolation.
    private final class Findings: @unchecked Sendable {
        var all: [String] = []
        var blocking: [String] = []
    }

    @MainActor
    private func audit(_ app: XCUIApplication, named name: String) throws {
        let findings = Findings()
        try app.performAccessibilityAudit { issue in
            // The audit reports on the main thread.
            MainActor.assumeIsolated {
                let element = issue.element.map { "'\($0.label)' (\($0.elementType.rawValue))" } ?? "no element"
                let line = "\(Self.name(of: issue.auditType)): \(issue.compactDescription) — \(element)"
                findings.all.append(line)
                if issue.auditType == .sufficientElementDescription || issue.auditType == .hitRegion {
                    findings.blocking.append(line)
                }
            }
            return true
        }
        let attachment = XCTAttachment(string: findings.all.isEmpty ? "No issues" : findings.all.joined(separator: "\n"))
        attachment.name = "accessibility-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertTrue(findings.blocking.isEmpty, "Accessibility issues:\n" + findings.blocking.joined(separator: "\n"))
    }

    private static func name(of type: XCUIAccessibilityAuditType) -> String {
        let names: [(XCUIAccessibilityAuditType, String)] = [
            (.contrast, "contrast"), (.elementDetection, "element detection"), (.hitRegion, "hit region"),
            (.sufficientElementDescription, "description"), (.dynamicType, "dynamic type"),
            (.textClipped, "text clipped"), (.trait, "trait"),
        ]
        return names.first { type.contains($0.0) }?.1 ?? "type \(type.rawValue)"
    }

    @MainActor
    private func launchInLandscape(_ scenario: String) throws -> XCUIApplication {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "iPad layouts")
        XCUIDevice.shared.orientation = .landscapeLeft
        addTeardownBlock { @MainActor in XCUIDevice.shared.orientation = .portrait }
        let app = XCUIApplication()
        app.launchArguments = ["-demo", scenario]
        app.launch()
        return app
    }

    /// The whole screen in its native (portrait) orientation: app screenshots taken in
    /// landscape come out rotated and cropped.
    @MainActor
    private func attachScreenshot(of app: XCUIApplication, named name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
