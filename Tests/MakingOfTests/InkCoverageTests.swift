import Foundation
import Testing
@testable import MakingOf

/// The same hand-made cases as `InkCoverageTests` in `tools/tests/test_making_of_fields.py`; the
/// golden frames compare the rasterizer with the Python's on real lines, bit for bit.
@Suite struct InkCoverageTests {
    private func coverage(_ lines: [InkLine], width: Double = 1, size: (Int, Int) = (12, 10)) -> Plane<Float> {
        InkCoverage.plane(lines, width: size.0, height: size.1, lineWidth: width)
    }

    private func line(_ points: [(Double, Double)], value: Double = 1) -> InkLine {
        InkLine(stroke: 0, points: points.map { Point($0.0, $0.1) }, value: value)
    }

    @Test func aHorizontalLineCoversThePixelsItRunsThrough() {
        // two pixels wide along y = 5: rows 4 and 5 are full ink, rows 3 and 6 are not touched
        let c = coverage([line([(2, 5), (8, 5)])], width: 2)
        #expect(c[4, 4] == 1 && c[4, 5] == 1 && c[4, 3] == 0 && c[4, 6] == 0)
        // round ends: a pixel a whole width past the end is clear, the one right at it is covered
        #expect(c[9, 4] == 0 && c[8, 4] > 0.5)
    }

    @Test func theEdgeIsSoftOverOnePixel() {
        // a line 1.5 wide: full ink half a pixel inside its edge (0.25 from its middle), none half a
        // pixel outside (1.25), a pixel's worth of grey between
        let on = coverage([line([(0, 5), (10, 5)])], width: 1.5)
        #expect([on[5, 4], on[5, 5], on[5, 3]] == [0.75, 0.75, 0])
        let off = coverage([line([(0, 5.25), (10, 5.25)])], width: 1.5)
        #expect([off[5, 5], off[5, 4], off[5, 6]] == [1, 0.5, 0])
    }

    @Test func aValueScalesTheInkAndTheDarkerLineWins() {
        let faint = line([(0, 5), (10, 5)], value: 0.4), bold = line([(5, 0), (5, 9)])
        let c = coverage([faint, bold], width: 2)
        #expect(c[2, 4] == 0.4)
        #expect(c[4, 4] == 1)                   // where they cross
        #expect(coverage([bold, faint], width: 2)[4, 4] == 1)
    }

    @Test func linesOffThePictureAreClipped() {
        let c = coverage([line([(-20, -5), (30, -3)]), line([(40, 2), (50, 3)])], width: 2)
        #expect(c.data.allSatisfy { $0 == 0 })
    }

    @Test func aDotIsRound() {
        let c = coverage([line([(5.5, 5.5), (5.5, 5.5)])], width: 4)
        #expect([c[5, 5], c[7, 5], c[8, 5]] == [1, 0.5, 0])
        #expect(c[7, 7] == 0 && c[0, 0] == 0)           // the corner of the square it isn't
    }

    @Test func aSinglePointDrawsNothing() {
        #expect(coverage([line([(5, 5)])], width: 4).data.allSatisfy { $0 == 0 })
        #expect(coverage([]).data.allSatisfy { $0 == 0 })
    }
}
