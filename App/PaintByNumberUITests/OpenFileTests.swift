import UIKit
import XCTest

/// "Open in Paint by Numbers": a file handed to the app opens the create flow on its preview,
/// titled with the file's name. Debug builds take the file from `-openFile <path>` and hand it
/// to the handler `onOpenURL` calls; the `create-from-file` scenario supplies a file of its own.
final class OpenFileTests: XCTestCase {
    @MainActor
    func testScenarioFileOpensItsPreviewUnderItsName() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "create-from-file"]
        app.launch()

        let start = app.buttons["Start Painting"]
        XCTAssertTrue(start.waitForExistence(timeout: 60), "The opened file didn't open the create flow")
        expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: start)
        waitForExpectations(timeout: 90)
        XCTAssertEqual(app.textFields["painting-title"].placeholderValue, "Morning Parrots")
        attach(app, named: "create-from-file")
    }

    @MainActor
    func testOpenFileArgumentOpensThatFile() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "Harbor Morning.jpg")
        let image = UIGraphicsImageRenderer(size: CGSize(width: 320, height: 240)).image { context in
            for (index, color) in [UIColor.systemTeal, .systemOrange, .systemIndigo].enumerated() {
                color.setFill()
                context.fill(CGRect(x: 0, y: CGFloat(index) * 80, width: 320, height: 80))
            }
        }
        try XCTUnwrap(image.jpegData(compressionQuality: 0.9)).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let app = XCUIApplication()
        app.launchArguments = ["-demo", "create-from-file", "-openFile", url.path]
        app.launch()

        XCTAssertTrue(app.buttons["Start Painting"].waitForExistence(timeout: 60), "The opened file didn't open the create flow")
        XCTAssertEqual(app.textFields["painting-title"].placeholderValue, "Harbor Morning")
    }

    @MainActor
    func testFileThatIsNotAPhotoShowsTheFailureState() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "notes.jpg")
        try Data("not a photo".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let app = XCUIApplication()
        app.launchArguments = ["-demo", "create-from-file", "-openFile", url.path]
        app.launch()

        XCTAssertTrue(app.staticTexts["Couldn’t Open Photo"].waitForExistence(timeout: 60), "No failure state for a file that isn't a photo")
        XCTAssertTrue(app.buttons["Close"].exists)
        attach(app, named: "create-from-file-failed")
    }

    @MainActor
    private func attach(_ app: XCUIApplication, named name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
