import XCTest

/// Runs the system accessibility audit on the main screens. Issues are collected into an
/// attachment (`accessibility-<scenario>`) for review; the test fails on the kinds that are
/// always actionable here (missing labels, unreachable elements).
final class AccessibilityAuditTests: XCTestCase {
    @MainActor
    func testGallery() throws {
        let app = launch("gallery")
        let preparing = app.staticTexts["Preparing…"]
        XCTAssertTrue(app.buttons["New Painting"].waitForExistence(timeout: 30))
        let deadline = Date.now.addingTimeInterval(120)
        while preparing.exists && Date.now < deadline { sleep(1) }
        try audit(app, named: "gallery")
    }

    @MainActor
    func testPainting() throws {
        let app = launch("paint-progress")
        XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: 60))
        sleep(2)
        try audit(app, named: "paint-progress")
    }

    @MainActor
    func testCreatePreview() throws {
        let app = launch("create-preview")
        let start = app.buttons["Start Painting"]
        XCTAssertTrue(start.waitForExistence(timeout: 30))
        expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: start)
        waitForExpectations(timeout: 60)
        try audit(app, named: "create-preview")
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
    private func launch(_ scenario: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", scenario]
        app.launch()
        return app
    }
}
