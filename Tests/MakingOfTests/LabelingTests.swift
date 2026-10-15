import Testing
@testable import MakingOf

/// `label_regions` in `making_of_exact.py` makes the same labels: these grids and their numbers are
/// in `tools/tests/test_making_of_inputs.py` too.
@Suite struct LabelingTests {
    private func regions(_ rows: [[UInt32]]) -> RegionLabels {
        Labeling.regions(keys: Plane(width: rows[0].count, height: rows.count, data: rows.flatMap { $0 }))
    }

    private func rows(_ r: RegionLabels) -> [[Int32]] {
        (0..<r.labels.height).map { y in (0..<r.labels.width).map { r.labels[$0, y] } }
    }

    @Test func areasAreNumberedByTheirFirstRun() {
        let r = regions([[1, 1, 2, 2, 1], [1, 3, 3, 2, 1], [4, 3, 3, 1, 1], [4, 4, 1, 1, 5]])
        #expect(rows(r) == [[0, 0, 1, 1, 2], [0, 3, 3, 1, 2], [4, 3, 3, 2, 2], [4, 4, 2, 2, 5]])
        #expect(r.count == 6)
    }

    @Test func aHoleIsItsOwnArea() {
        let r = regions([[7, 7, 7], [7, 8, 7], [7, 7, 7]])
        #expect(rows(r) == [[0, 0, 0], [0, 1, 0], [0, 0, 0]])
        #expect(r.count == 2)
    }

    @Test func diagonalNeighboursAreNotJoined() {
        let r = regions([[1, 2, 1], [2, 1, 2], [1, 2, 1]])
        #expect(rows(r) == [[0, 1, 2], [3, 4, 5], [6, 7, 8]])
        #expect(r.count == 9)
    }

    @Test func runsJoinedLaterKeepTheEarliestNumber() {
        // the 6 at the left of row 2 and the 6 at the top right meet only below
        let r = regions([[5, 5, 5, 6], [6, 5, 6, 6], [6, 6, 6, 5]])
        #expect(rows(r) == [[0, 0, 0, 1], [1, 0, 1, 1], [1, 1, 1, 2]])
        #expect(r.count == 3)
    }

    @Test func aPictureIsLabeledByColor() {
        let a = SIMD4<UInt8>(10, 20, 30, 255), b = SIMD4<UInt8>(10, 20, 31, 255)
        let r = Labeling.regions(of: Plane(width: 3, height: 1, data: [a, b, a]))
        #expect(rows(r) == [[0, 1, 2]])
        // alpha is not part of a color
        let c = SIMD4<UInt8>(10, 20, 30, 0)
        #expect(Labeling.regions(of: Plane(width: 2, height: 1, data: [a, c])).count == 1)
    }

    @Test func oneRowAndOneColumn() {
        #expect(rows(regions([[1, 1, 2, 2, 1]])) == [[0, 0, 1, 1, 2]])
        #expect(rows(regions([[1], [1], [2], [1]])) == [[0], [0], [1], [2]])
    }

    @Test func smallFixtureHasItsRegions() throws {
        let small = try SmallShow()
        let simplified = Labeling.regions(of: small.pictures.simplified)
        #expect(simplified.count == small.expected.trace.labels)
        // one color per area, and areas of one color are not touching
        var colors = [SIMD4<UInt8>?](repeating: nil, count: simplified.count)
        for (label, color) in zip(simplified.labels.data, small.pictures.simplified.data) {
            if let seen = colors[Int(label)] { #expect(seen == color) } else { colors[Int(label)] = color }
        }
        let w = simplified.labels.width
        for y in 0..<simplified.labels.height {
            for x in 0..<w - 1 {
                let i = y * w + x
                #expect((simplified.labels.data[i] == simplified.labels.data[i + 1]) == (small.pictures.simplified.data[i] == small.pictures.simplified.data[i + 1]))
            }
        }
    }
}
