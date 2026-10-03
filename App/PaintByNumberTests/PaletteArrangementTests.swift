import Foundation
import PaintCore
import Testing
@testable import PaintByNumber

/// The palette's orders and rows (Settings › Palette, More › Palette), custom arrangements,
/// and picking the next color in the palette's order.
@MainActor
struct PaletteArrangementTests {
    /// Red, a light gray, blue, yellow, a dark gray, green (OKLab).
    private static let labs: [SIMD3<Float>] = [
        SIMD3(0.63, 0.22, 0.13), SIMD3(0.9, 0, 0), SIMD3(0.45, -0.03, -0.31), SIMD3(0.97, -0.07, 0.2),
        SIMD3(0.3, 0.005, 0), SIMD3(0.87, -0.23, 0.18),
    ]
    private static let palette = labs.map { PaletteColor(oklab: $0, space: .sRGB) }

    private static let remaining = [4, 0, 9, 2, 2, 7]
    private static let all = Array(0..<6)

    private func arrange(_ order: PaletteOrder, custom: [Int]? = nil) -> [Int] {
        order.arrange(Self.all, palette: Self.palette, remaining: Self.remaining, custom: custom)
    }

    @Test func presetsOrderTheColors() {
        #expect(arrange(.number) == [0, 1, 2, 3, 4, 5])
        // Red, yellow, green, blue around the wheel; then the grays, light to dark.
        #expect(arrange(.rainbow) == [0, 3, 5, 2, 1, 4])
        #expect(arrange(.lightToDark) == [3, 1, 5, 0, 2, 4])
        #expect(arrange(.darkToLight) == [4, 2, 0, 5, 1, 3])
        // Ties keep number order.
        #expect(arrange(.nearlyDone) == [1, 3, 4, 0, 5, 2])
        #expect(arrange(.mostLeft) == [2, 5, 0, 3, 4, 1])
    }

    @Test func customFollowsTheArrangementAndFallsBackToNumbers() {
        #expect(arrange(.custom, custom: [5, 4, 3, 2, 1, 0]) == [5, 4, 3, 2, 1, 0])
        #expect(arrange(.custom) == Self.all)
        // Colors the arrangement lacks follow it by number.
        #expect(arrange(.custom, custom: [3, 1]) == [3, 1, 0, 2, 4, 5])
        // Only the colors asked for: finished ones have left the palette.
        #expect(PaletteOrder.custom.arrange([0, 2, 5], palette: Self.palette, remaining: Self.remaining, custom: [5, 4, 3, 2, 1, 0])
            == [5, 2, 0])
    }

    @Test func storedArrangementsMustFitThePainting() throws {
        let suite = "PaletteArrangementTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(PaletteOrder.storedCustom(seed: 7, count: 3, in: defaults) == nil)
        PaletteOrder.storeCustom([2, 0, 1], seed: 7, in: defaults)
        #expect(PaletteOrder.storedCustom(seed: 7, count: 3, in: defaults) == [2, 0, 1])
        #expect(PaletteOrder.storedCustom(seed: 8, count: 3, in: defaults) == nil)
        // Regenerated with another palette size, or damaged: not used.
        #expect(PaletteOrder.storedCustom(seed: 7, count: 4, in: defaults) == nil)
        PaletteOrder.storeCustom([2, 2, 1], seed: 7, in: defaults)
        #expect(PaletteOrder.storedCustom(seed: 7, count: 3, in: defaults) == nil)
    }

    @Test func rowsChoicesCapTheLines() {
        #expect(PaletteRows.auto.maxLines(automatic: 3) == 3)
        #expect(PaletteRows.four.maxLines(automatic: 1) == 4)
        #expect(PaletteRows.all.maxLines(automatic: 1) == .max)
        #expect(!PaletteRows.auto.isFixed && !PaletteRows.all.isFixed && PaletteRows.two.isFixed)
        #expect(Set(PaletteRows.allCases.map(\.name)).count == PaletteRows.allCases.count)
        #expect(Set(PaletteOrder.allCases.map(\.name)).count == PaletteOrder.allCases.count)
    }

    @Test func theNextColorFollowsThePalettesOrder() {
        let template = SyntheticTemplate.make(.init(width: 480, height: 640, columns: 6, rows: 8, seed: 3))
        let session = PaintingSession(template: template, nicknameSeed: 42)
        #expect(session.nicknameSeed == 42)
        let count = session.paletteCount
        #expect(session.nextIncompleteColor(after: 0) == 1)
        session.colorOrder = Array((0..<count).reversed())
        #expect(session.nextIncompleteColor(after: 0) == count - 1)
        #expect(session.nextIncompleteColor(after: count - 1) == count - 2)
        // An order that doesn't fit the palette is ignored.
        session.colorOrder = [1, 0]
        #expect(session.nextIncompleteColor(after: 0) == 1)
    }
}
