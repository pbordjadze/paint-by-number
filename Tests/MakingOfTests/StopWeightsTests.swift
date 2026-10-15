import Testing
@testable import MakingOf

/// `line_mask` and the weights of `making_of_inputs.py`: the same pixels and the same sums. The mask
/// below is in `tools/tests/test_making_of_inputs.py` too.
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
        let mask = LineMask(width: 14, height: 9, strokes: strokes, lineWidth: 1.5)
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
        let mask = LineMask(width: 6, height: 4, strokes: [Polyline([Point(-20, 1.5), Point(40, 1.5)]), Polyline([Point(50, 50), Point(60, 60)])], lineWidth: 1)
        #expect(picture(mask) == ["......", "######", "......", "......"])
    }

    @Test func noLinesNoInk() {
        #expect(LineMask(width: 3, height: 3, strokes: [], lineWidth: 2).plane == Plane(width: 3, height: 3, repeating: 0))
    }
}

@Suite struct StopWeightsTests {
    private func weights(_ small: SmallShow) -> StopWeights {
        StopWeights(
            pictures: small.pictures, template: small.show, petHeight: small.expected.inputs.petHeight,
            margin: small.spec.crew.margin)
    }

    @Test func theRoomKeepsPetsOutOfTheCorners() throws {
        let small = try SmallShow()
        let w = weights(small)
        // 216 x 144: 0.12 of the height plus the pet's 23.04 from the top, 8 px off the bottom, 0.12 of the width at the sides
        #expect(w.rows == 40..<136)
        #expect(w.columns == 25..<191)
    }

    @Test func eachStepsWeightsSumTheSameInPython() throws {
        let small = try SmallShow()
        let w = weights(small)
        for (k, want) in small.expected.trace.weightTotals.enumerated() {
            guard let want else { continue }
            #expect(ExactMath.cumulative(w.plane(forStep: k)).last == want, "step \(k)")
        }
    }

    @Test func weightsAreZeroOutsideTheRoomAndPositiveInside() throws {
        let small = try SmallShow()
        let w = weights(small)
        let width = small.pictures.width
        for k in [0, 1, 3, 5] {
            let plane = w.plane(forStep: k)
            for (i, v) in plane.enumerated() {
                let inside = w.rows.contains(i / width) && w.columns.contains(i % width)
                #expect(inside ? v > 0 : v == 0, "step \(k) cell \(i)")
            }
        }
    }

    @Test func structureWeighsAThirdOfTheLevelPlusTheEdges() throws {
        let small = try SmallShow()
        let plane = weights(small).structure()
        let i = 60 * small.pictures.width + 100
        #expect(plane[i] == Double(small.pictures.structure.data[i]) * 4 + 357)
    }

    @Test func smallRegionsWeighMorePerPixel() throws {
        let small = try SmallShow()
        let plane = weights(small).shrinking()
        let regions = Labeling.regions(of: small.pictures.simplified)
        var area = [Int](repeating: 0, count: regions.count)
        for label in regions.labels.data { area[Int(label)] += 1 }
        for (i, v) in plane.enumerated() where v > 0 {
            let a = Double(area[Int(regions.labels.data[i])])
            #expect(v == a.squareRoot() / a)
        }
    }

    @Test func numbersAreWeighedWhereTheyAreAndWhereLinesAreThin() throws {
        let small = try SmallShow()
        let w = weights(small)
        let plane = w.numbers()
        // a number's own pixel weighs at least one more than its neighbours', at the same openness
        let n = try #require(small.show.numbers.first { w.rows.contains(Int($0.y)) && w.columns.contains(Int($0.x)) && w.columns.contains(Int($0.x) + 1) })
        let at = Int(n.y) * small.pictures.width + Int(n.x)
        #expect(plane[at] > 0.9 && plane[at] > plane[at + 1])
        let ink = LineMask(width: small.pictures.width, height: small.pictures.height, strokes: small.show.strokes, lineWidth: small.show.lineWidth)
        #expect(ink.plane.data.reduce(0) { $0 + Int($1) } == small.expected.trace.inkPixels)
        let density = ExactMath.boxSums(ink.plane, radius: max(1, Int(0.35 * small.expected.inputs.petHeight)))
        #expect(ExactMath.percentile(density.data, percent: 95) == small.expected.trace.percentile95)
    }

    @Test func aPictureTooSmallForItsMarginsHasNoRoom() throws {
        let small = try SmallShow()
        let flat = Plane<SIMD4<UInt8>>(width: 20, height: 14, repeating: SIMD4(9, 9, 9, 255))
        let pictures = try ShowPictures(
            working: flat, structure: Plane(width: 20, height: 14, repeating: 0), smoothed: flat, palette: flat, simplified: flat)
        let none = ShowTemplate(small.template, width: 20, height: 14)
        let w = StopWeights(pictures: pictures, template: none, petHeight: 1.6, margin: 0.12)
        #expect(w.rows == 3..<6 && w.columns == 2..<18)
        let cramped = StopWeights(pictures: pictures, template: none, petHeight: 20, margin: 0.12)
        #expect(cramped.rows.isEmpty)
        #expect(cramped.structure().allSatisfy { $0 == 0 })
    }
}
