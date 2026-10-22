import CoreGraphics
import Foundation
import PaintCore
import Testing
@testable import PaintByNumber

/// The palette's orders and rows (More › Palette), and picking the next color in the palette's
/// order.
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

    private func arrange(_ order: PaletteOrder) -> [Int] {
        order.arrange(Self.all, palette: Self.palette, remaining: Self.remaining)
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
        // Only the colors asked for: finished ones have left the palette.
        #expect(PaletteOrder.darkToLight.arrange([0, 3, 5], palette: Self.palette, remaining: Self.remaining) == [0, 5, 3])
    }

    /// Only the orders that follow progress read the areas left: arranged by number, hue or
    /// lightness, the painting screen that arranges its palette isn't re-rendered on every fill.
    @Test func onlyProgressOrdersReadTheAreasLeft() {
        var reads = 0
        func remaining() -> [Int] {
            reads += 1
            return Self.remaining
        }
        for order in PaletteOrder.allCases {
            reads = 0
            _ = order.arrange(Self.all, palette: Self.palette, remaining: remaining())
            let followsProgress = order == .nearlyDone || order == .mostLeft
            #expect(reads == (followsProgress ? 1 : 0), "\(order)")
        }
    }

    @Test func rowsChoicesCapTheLines() {
        #expect(PaletteRows.auto.maxLines(automatic: 3) == 3)
        #expect(PaletteRows.four.maxLines(automatic: 1) == 4)
        #expect(PaletteRows.all.maxLines(automatic: 1) == .max)
        #expect(!PaletteRows.auto.isFixed && !PaletteRows.all.isFixed && PaletteRows.two.isFixed)
        #expect(Set(PaletteRows.allCases.map(\.name)).count == PaletteRows.allCases.count)
        #expect(Set(PaletteOrder.allCases.map(\.name)).count == PaletteOrder.allCases.count)
    }

    /// Swatches fill across the bar before along it: three rows read 1 4 7 / 2 5 8 / 3 6 9.
    @Test func swatchesFillAcrossTheBarFirst() {
        #expect(PaletteBar.lanes(Array(0..<9), lines: 3) == [[0, 1, 2], [3, 4, 5], [6, 7, 8]])
        #expect(PaletteBar.lanes([5, 2, 7, 0], lines: 3) == [[5, 2, 7], [0]])
        #expect(PaletteBar.lanes([4, 1], lines: 1) == [[4], [1]])
        #expect(PaletteBar.lanes([], lines: 2).isEmpty)
    }

    /// A one-line phone bar 378 pt long, 56 pt a swatch: the bar scrolls a hidden swatch whole into
    /// view with 16 pt to spare on the side it comes in from, and not at all for one in view.
    @Test func theBarScrollsTheSelectedSwatchWholeIntoView() {
        let metrics = PaletteMetrics.standard
        // Scrolled on to show lanes 12 and up; lane 9 holds swatch 10.
        let bar = PaletteWindow(offset: 12 * 56, viewport: 378, content: 30 * 56 + 24, shown: 378)
        #expect(bar.offset(revealing: 9, metrics: metrics) == CGFloat(16 + 9 * 56 - 16))
        #expect(bar.offset(revealing: 13, metrics: metrics) == nil, "a swatch in view moved the bar")
        // Lane 20 starts at 1136, ends at 1184: the bar's end comes to 1200.
        #expect(bar.offset(revealing: 20, metrics: metrics) == CGFloat(1200 - 378))
        // Never past either end.
        #expect(bar.offset(revealing: 0, metrics: metrics) == CGFloat(0))
        #expect(bar.offset(revealing: 29, metrics: metrics) == CGFloat(30 * 56 + 24 - 378))
    }

    /// The swatch to bring into view is the one a tap on its color's area just shook.
    @Test func theShakenSwatchIsTheOneWhoseCountWentUp() {
        #expect(PaletteBar.shaken(from: [:], to: [7: 1]) == 7)
        #expect(PaletteBar.shaken(from: [7: 1, 3: 2], to: [7: 2, 3: 2]) == 7)
        #expect(PaletteBar.shaken(from: [7: 1], to: [7: 1]) == nil)
        #expect(PaletteBar.shaken(from: [7: 2], to: [:]) == nil)
        #expect(PaletteBar.shaken(from: [:], to: [9: 1, 4: 1]) == 4)
    }

    /// Paul's tap on "10": a scroll view reaching 170 pt past the glass on each side counts swatches
    /// under the glass as shown. Only what the glass shows counts.
    @Test func swatchesUnderTheGlassAreNotInView() {
        let metrics = PaletteMetrics.standard
        let bar = PaletteWindow(offset: 600, viewport: 718, content: 30 * 56 + 24, hiddenBefore: 170, shown: 378)
        // Lane 12 (at 688–736) is in the scroll view but under the glass's leading edge (770).
        let target = bar.offset(revealing: 12, metrics: metrics)
        #expect(target == CGFloat(16 + 12 * 56 - 16 - 170))
        if let target {
            let shownFrom = target + 170
            #expect(shownFrom <= CGFloat(16 + 12 * 56 - 16), "the swatch is still hidden on the leading side")
        }
        #expect(bar.offset(revealing: 15, metrics: metrics) == nil, "a swatch the glass shows moved the bar")
    }

    @Test func theNextColorFollowsThePalettesOrder() {
        let template = Fixtures.mosaic
        let session = PaintingSession(template: template, nicknameSeed: 42)
        #expect(session.nicknameSeed == 42)
        let count = session.paletteCount
        #expect(session.nextIncompleteColor(after: 0) == 1)
        session.colorOrder = Array((0..<count).reversed())
        #expect(session.nextIncompleteColor(after: 0) == count - 1)
        #expect(session.nextIncompleteColor(after: count - 1) == count - 2)
        // Backwards (the Paint menu's `[`), and from either end with nothing selected.
        #expect(session.nextIncompleteColor(after: 0, backwards: true) == 1)
        #expect(session.nextIncompleteColor(after: count - 1, backwards: true) == 0)
        #expect(session.nextIncompleteColor(after: nil) == count - 1)
        #expect(session.nextIncompleteColor(after: nil, backwards: true) == 0)
        // A finished color is passed over both ways.
        let finished = count - 2
        session.paint(
            template.regions.indices.filter { Int(template.regions[$0].colorIndex) == finished }, from: .zero, animated: false)
        #expect(session.isColorComplete(finished))
        #expect(session.nextIncompleteColor(after: count - 1) == count - 3)
        #expect(session.nextIncompleteColor(after: count - 3, backwards: true) == count - 1)
        // An order that doesn't fit the palette is ignored.
        session.colorOrder = [1, 0]
        #expect(session.nextIncompleteColor(after: 0) == 1)
    }
}
