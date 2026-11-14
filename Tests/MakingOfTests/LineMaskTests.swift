import Testing
@testable import MakingOf

/// `line_mask` of `making_of_exact.py`: the same pixels. The masks below are in
/// `tools/tests/test_making_of_inputs.py` too.
@Suite struct LineMaskTests {
    private func picture(_ mask: LineMask) -> [String] {
        (0..<mask.plane.height).map { y in String((0..<mask.plane.width).map { mask.plane[$0, y] == 1 ? "#" : "." }) }
    }

    @Test func pixelsWithinReachOfALineAreInked() {
        let strokes = [
            Polyline([Point(1, 1.5), Point(12, 1.5), Point(12, 7.25)]),
            Polyline([Point(3, 5), Point(3.5, 5.2)]),
            Polyline([Point(6, 6), Point(6, 6)]),         // a dot
        ]
        let mask = LineMask(width: 14, height: 9, strokes: strokes, halfWidth: 1.5 / 2 + 0.33)
        #expect(picture(mask) == [
            ".###########..",
            "#############.",
            ".############.",
            "...........##.",
            "..##.......##.",
            "..#####....##.",
            ".....##....##.",
            "...........##.",
            "..............",
        ])
        #expect(mask.plane.data.reduce(0) { $0 + Int($1) } == 55)
    }

    @Test func linesOutsideThePlaneAreClipped() {
        let mask = LineMask(width: 6, height: 4, strokes: [Polyline([Point(-20, 1.5), Point(40, 1.5)]), Polyline([Point(50, 50), Point(60, 60)])], halfWidth: 0.5 + 0.33)
        #expect(picture(mask) == ["......", "######", "......", "......"])
    }

    @Test func noLinesNoInk() {
        #expect(LineMask(width: 3, height: 3, strokes: [], halfWidth: 1).plane == Plane(width: 3, height: 3, repeating: 0))
    }
}
