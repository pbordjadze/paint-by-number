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
        #if UNRELEASED
        // SideStore and Debug builds keep every color's place (painting-company row 293): number
        // n is on row (n - 1) % 3 of column (n - 1) / 3 from the first fill to the last (every paint
        // of the demo's painting has an area), a finished color there as a spent well, `well-N`,
        // which is no button.
        let places = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'swatch-' OR identifier BEGINSWITH 'well-'"))
            .allElementsBoundByIndex
        let frames = places
            .map { (number: Int($0.identifier.split(separator: "-").last ?? "") ?? 0, frame: $0.frame) }
            .sorted { $0.number < $1.number }
        XCTAssertGreaterThan(frames.count, 6, "Too few colors to fill three rows")
        // The colors painted first, 1 and on, are finished: they are here all the same.
        XCTAssertEqual(frames.map { $0.number }, Array(1...frames.count), "A color has no place, or two")
        let first = frames[0].frame
        for swatch in frames.dropFirst() {
            let row = (swatch.number - 1) % 3, column = (swatch.number - 1) / 3
            if row == 0 {
                XCTAssertEqual(swatch.frame.midY, first.midY, accuracy: 1, "\(swatch.number) isn't in the top row")
            } else {
                XCTAssertEqual(swatch.frame.midX, frames[swatch.number - 2].frame.midX, accuracy: 1, "\(swatch.number) isn't under \(swatch.number - 1)")
                XCTAssertGreaterThan(swatch.frame.midY, frames[swatch.number - 2].frame.midY + 1, "\(swatch.number) isn't below \(swatch.number - 1)")
            }
            if column == 0 {
                XCTAssertEqual(swatch.frame.midX, first.midX, accuracy: 1, "\(swatch.number) isn't in the first column")
            } else {
                XCTAssertGreaterThan(swatch.frame.midX, frames[swatch.number - 4].frame.midX + 1, "\(swatch.number) isn't right of \(swatch.number - 3)")
            }
        }
        #else
        let frames = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'swatch-'")).allElementsBoundByIndex
            .map { (number: Int($0.identifier.dropFirst("swatch-".count)) ?? 0, frame: $0.frame) }
            .sorted { $0.number < $1.number }
        XCTAssertGreaterThan(frames.count, 6, "Too few colors left to fill three rows")
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
