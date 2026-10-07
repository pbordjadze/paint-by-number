import UIKit
import XCTest

/// Settings › Preview on Line Art: the create flow's comparison shows the drawing alone, and a
/// phone's enlarged preview tunes it one slider at a time.
final class LineArtPreviewUITests: XCTestCase {
    /// The comparison's trailing side is the drawing on blank paper: captioned Line Art, with
    /// none of the painting's colors.
    @MainActor
    func testLineArtPreviewShowsTheDrawing() throws {
        let app = launchPreview()
        let compare = app.descendants(matching: .any)["Comparison of photo and template"]
        XCTAssertTrue(compare.exists, "The preview has no comparison")
        XCTAssertTrue(app.staticTexts["Line Art"].exists, "The comparison isn't captioned Line Art")
        XCTAssertFalse(app.staticTexts["Painting"].exists, "The comparison still shows the painting")
        let screenshot = app.screenshot()
        attach(screenshot, named: "create-line-art")
        // Right of the divider (in the middle), clear of the caption and the status capsule.
        let frame = compare.frame
        let area = CGRect(
            x: frame.minX + 0.62 * frame.width, y: frame.minY + 0.18 * frame.height,
            width: 0.33 * frame.width, height: 0.55 * frame.height)
        let colorful = try colorfulShare(of: screenshot, in: area, window: app.windows.firstMatch.frame)
        XCTAssertLessThan(colorful, 0.01, "\(Int((colorful * 100).rounded())) % of the line art is colored like paint")
    }

    /// A phone's preview enlarges: the comparison grows, the title and Start give way to the
    /// slider of one setting at a time, Lines first, and Done brings the page back with what
    /// was tuned.
    @MainActor
    func testEnlargedPreviewTunesOneSettingAtATime() throws {
        try XCTSkipIf(
            UIDevice.current.userInterfaceIdiom == .pad, "Only compact windows enlarge the preview: the iPad's is large already")
        let app = launchPreview()
        let compare = app.descendants(matching: .any)["Comparison of photo and template"]
        let fitted = compare.frame
        let enlarge = app.buttons["Enlarge Preview"]
        XCTAssertTrue(enlarge.waitForExistence(timeout: 10), "The preview can't be enlarged")
        enlarge.tap()

        let chooser = app.descendants(matching: .any).matching(identifier: "tuned-setting").firstMatch
        XCTAssertTrue(chooser.waitForExistence(timeout: 10), "The enlarged preview has no setting chooser")
        XCTAssertTrue(
            waitUntil { compare.frame.height > 1.25 * fitted.height },
            "The comparison didn't grow: \(fitted) → \(compare.frame)")
        let enlarged = compare.frame
        XCTAssertFalse(app.buttons["Start Painting"].exists, "Start shows in the enlarged preview")
        XCTAssertFalse(app.textFields["painting-title"].exists, "The title shows in the enlarged preview")
        let lines = app.sliders["Lines"]
        XCTAssertTrue(lines.exists, "The enlarged preview doesn't start on Lines")
        XCTAssertFalse(app.sliders["Colors"].exists, "The enlarged preview shows more than one slider")
        XCTAssertEqual(lines.value as? String, "Balanced")
        lines.adjust(toNormalizedSliderPosition: 0.95)
        XCTAssertTrue(waitFor(lines, toMatch: NSPredicate(format: "value == %@", "Most")), "Lines reads \(lines.value ?? "")")
        attachScreenshot(of: app, named: "create-enlarged-lines")

        let detail = chooser.buttons["Detail"]
        XCTAssertTrue(detail.exists, "The chooser has no Detail")
        detail.tap()
        XCTAssertTrue(app.sliders["Detail"].waitForExistence(timeout: 5), "Choosing Detail didn't show its slider")
        XCTAssertFalse(lines.exists, "Lines still shows beside Detail")
        attachScreenshot(of: app, named: "create-enlarged-detail")

        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["Start Painting"].waitForExistence(timeout: 10), "Done didn't bring the page back")
        XCTAssertTrue(waitUntil { compare.frame.height < enlarged.height - 20 }, "The comparison stayed enlarged")
        XCTAssertEqual(app.sliders["Lines"].value as? String, "Most", "What the enlarged preview tuned didn't stay")
        XCTAssertEqual(app.buttons["settings-origin"].value as? String, "Custom")
    }

    // MARK: - Helpers

    /// The Great Wave's preview with Settings › Preview on Line Art, once its settings are chosen.
    @MainActor
    private func launchPreview() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "create-preview", "-demoFixedPictures", "YES", "-previewStyle", "lineArt"]
        app.launch()
        let start = app.buttons["Start Painting"]
        XCTAssertTrue(start.waitForExistence(timeout: 30), "The preview didn't open")
        XCTAssertTrue(
            waitFor(start, toMatch: NSPredicate(format: "isEnabled == true"), timeout: 120),
            "The preview never finished choosing its settings")
        return app
    }

    /// The share of `area`'s pixels (window points) colored like paint rather than paper or ink.
    @MainActor
    private func colorfulShare(of screenshot: XCUIScreenshot, in area: CGRect, window: CGRect) throws -> Double {
        let image = try XCTUnwrap(screenshot.image.cgImage)
        let scale = CGFloat(image.width) / window.width
        let pixels = CGRect(x: area.minX * scale, y: area.minY * scale, width: area.width * scale, height: area.height * scale)
        let crop = try XCTUnwrap(image.cropping(to: pixels.integral))
        let width = crop.width, height = crop.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let drawn = data.withUnsafeMutableBytes { raw -> Bool in
            guard let ctx = CGContext(
                data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            ctx.draw(crop, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        XCTAssertTrue(drawn, "The screenshot couldn't be read")
        var colorful = 0
        for i in stride(from: 0, to: data.count, by: 4) {
            let r = Int(data[i]), g = Int(data[i + 1]), b = Int(data[i + 2])
            if max(r, g, b) - min(r, g, b) > 70 { colorful += 1 }
        }
        return Double(colorful) / Double(max(1, width * height))
    }
}
