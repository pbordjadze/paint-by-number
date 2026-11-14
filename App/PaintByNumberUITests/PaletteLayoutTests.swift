import XCTest

/// Where the palette puts its swatches on screen (More › Palette).
final class PaletteLayoutTests: XCTestCase {
    /// Three rows by number fill down each column before across: 1 4 7 / 2 5 8 / 3 6 9.
    @MainActor
    func testRowsFillDownEachColumnFirst() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "paint-palette-number"]
        app.launch()
        XCTAssertTrue(app.buttons["Back"].waitForExistence(timeout: 60), "The painting didn't open")
        sleep(3)
        attachScreenshot(of: app, named: "paint-palette-number")
        let frames = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'swatch-'")).allElementsBoundByIndex
            .map { (number: Int($0.identifier.dropFirst("swatch-".count)) ?? 0, frame: $0.frame) }
            .sorted { $0.number < $1.number }
        XCTAssertGreaterThan(frames.count, 6, "Too few colors left to fill three rows")
        #if UNRELEASED
        // SideStore and Debug builds keep each color's place (painting-company row 293): number n,
        // finished colors or not, is on row (n - 1) % 3 of column (n - 1) / 3 (every paint of the
        // demo's painting has an area), so the colors left are where they were at the start.
        let first = frames[0]
        for swatch in frames.dropFirst() {
            let rows = (swatch.number - 1) % 3 - (first.number - 1) % 3
            let columns = (swatch.number - 1) / 3 - (first.number - 1) / 3
            if rows == 0 {
                XCTAssertEqual(swatch.frame.midY, first.frame.midY, accuracy: 1, "\(swatch.number) isn't on \(first.number)'s row")
            } else {
                XCTAssertEqual(rows > 0, swatch.frame.midY > first.frame.midY + 1, "\(swatch.number) is on the wrong side of \(first.number)'s row")
            }
            if columns == 0 {
                XCTAssertEqual(swatch.frame.midX, first.frame.midX, accuracy: 1, "\(swatch.number) isn't in \(first.number)'s column")
            } else {
                XCTAssertGreaterThan(swatch.frame.midX, first.frame.midX + 1, "\(swatch.number) isn't right of \(first.number)")
            }
        }
        #else
        for (i, swatch) in frames.enumerated().dropFirst() {
            let previous = frames[i - 1].frame
            if i % 3 == 0 {
                // A new column: to the right, starting back at the top row.
                XCTAssertGreaterThan(swatch.frame.midX, previous.midX + 1, "\(swatch.number) isn't right of \(frames[i - 1].number)")
                XCTAssertEqual(swatch.frame.midY, frames[i - 3].frame.midY, accuracy: 1, "\(swatch.number) isn't in the top row")
            } else {
                // The same column, one row down.
                XCTAssertEqual(swatch.frame.midX, previous.midX, accuracy: 1, "\(swatch.number) isn't under \(frames[i - 1].number)")
                XCTAssertGreaterThan(swatch.frame.midY, previous.midY + 1, "\(swatch.number) isn't below \(frames[i - 1].number)")
            }
        }
        #endif
    }
}
