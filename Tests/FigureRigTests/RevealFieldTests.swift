import Foundation
import PaintCore
import Testing
@testable import FigureRig

private func gray(_ width: Int, _ height: Int, _ values: [UInt8]) -> PipelineSnapshot.Picture {
    .grayscale(Grid(width: width, height: height, storage: values))
}

@Suite("Reveal fields")
struct RevealFieldTests {
    @Test func rightHalfRisesFromLeftToRight() throws {
        let a = gray(80, 3, Array(repeating: 0, count: 240))
        let b = gray(80, 3, (0..<240).map { $0 % 80 >= 40 ? 255 : 0 })
        let field = try RevealField.make(from: a, to: b)
        #expect(field.changed == 0.5)
        for y in 0..<3 {
            for x in 0..<80 {
                #expect(field.times[y * 80 + x] == (x < 40 ? nil : Double(x - 40) / 39))
            }
        }
        let path = try ArcPath(field.workerPath(steps: 40))
        #expect(path.points.first == Point(40.5, 1.5))
        #expect(path.points.last == Point(79.5, 1.5))
    }

    @Test(arguments: RevealField.Seed.allCases)
    func unchangedHasNoTimesOrPath(seed: RevealField.Seed) throws {
        let picture = gray(3, 2, [0, 8, 255, 33, 89, 72])
        let field = try RevealField.make(from: picture, to: picture, seed: seed)
        #expect(field.times == Array(repeating: nil, count: 6))
        #expect(field.changed == 0)
        #expect(try field.workerPath() == "")
        #expect(Array(field.encodedPGM().suffix(6)) == [0, 0, 0, 0, 0, 0])
    }

    @Test func disconnectedBlobsContinueInRasterOrder() throws {
        let a = gray(9, 1, Array(repeating: 0, count: 9))
        let b = gray(9, 1, [0, 100, 100, 0, 100, 100, 0, 200, 200])
        let left = try RevealField.make(from: a, to: b)
        #expect(left.times == [nil, 0, 1.0 / 3, nil, 1.0 / 3, 2.0 / 3, nil, 2.0 / 3, 1])
        let strongest = try RevealField.make(from: a, to: b, seed: .strongest)
        #expect(strongest.times == [nil, 0, 0.5, nil, 0.5, 1, nil, 0, 0])
    }

    @Test func diagonalCostsAndCenterSeed() throws {
        let a = gray(3, 3, Array(repeating: 0, count: 9))
        let b = gray(3, 3, Array(repeating: 255, count: 9))
        let field = try RevealField.make(from: a, to: b, seed: .center)
        #expect(field.times == [1, 2.0 / 3, 1, 2.0 / 3, 0, 2.0 / 3, 1, 2.0 / 3, 1])
        // A diagonal connection belongs to one component and costs 3, rather than 2.
        let diagonal = try RevealField.make(from: a, to: gray(3, 3, [255, 0, 0, 0, 255, 255, 0, 0, 0]))
        #expect(diagonal.times == [0, nil, nil, nil, 0.6, 1, nil, nil, nil])
        // Four nearest center pixels tie; the first in raster order seeds the field.
        let tie = try RevealField.make(from: gray(2, 2, [0, 0, 0, 0]), to: gray(2, 2, [255, 255, 255, 255]), seed: .center)
        #expect(tie.times == [0, 2.0 / 3, 2.0 / 3, 1])
    }

    @Test func geodesicFollowsObstaclesRatherThanEuclideanDistance() throws {
        // A U-shaped corridor can only reach the right arm by walking around the bottom.
        let a = gray(5, 5, Array(repeating: 0, count: 25))
        let b = gray(5, 5, (0..<25).map { i in
            i % 5 == 0 || i % 5 == 4 || i / 5 == 4 ? 255 : 0
        })
        let field = try RevealField.make(from: a, to: b)
        #expect(field.times[0] == 0)
        #expect(field.times[20] == 0)
        #expect(field.times[21] == 2.0 / 15)
        #expect(field.times[22] == 4.0 / 15)
        #expect(field.times[23] == 6.0 / 15)
        #expect(field.times[19] == 9.0 / 15)
        #expect(field.times[4] == 1)
        #expect(field.times[12] == nil)
    }

    @Test func grayscaleThresholdAndStrongestTies() throws {
        let field = try RevealField.make(from: gray(6, 1, [0, 100, 100, 0, 0, 0]),
                                         to: gray(6, 1, [8, 108, 91, 9, 20, 20]), seed: .strongest)
        #expect(field.times == [nil, nil, 1, 0.5, 0, 0])
        let singleton = try RevealField.make(from: gray(1, 1, [100]), to: gray(1, 1, [91]))
        #expect(singleton.times == [0])
        let path = try ArcPath(singleton.workerPath())
        #expect((path.sample(0.5).point - Point(0.5, 0.5)).length < 0.01)
    }

    @Test func colorUsesOKLabAndMixedPairsPromoteGray() throws {
        let a = PipelineSnapshot.Picture.color(RGBAImage(width: 3, height: 1, fill: SIMD4(100, 100, 100, 255)))
        let b = PipelineSnapshot.Picture.color(RGBAImage(width: 3, height: 1,
                            pixels: [101, 100, 100, 255, 200, 100, 100, 255, 100, 100, 100, 255]))
        let color = try RevealField.make(from: a, to: b)
        #expect(color.times == [nil, 0, nil])
        let mixed = try RevealField.make(from: gray(3, 1, [100, 100, 100]), to: b)
        #expect(mixed.times == color.times)
        // Use every gray byte as an RGB triplet and check the actual OKLab threshold.
        let rgb = PipelineSnapshot.Picture.color(RGBAImage(width: 256, height: 1,
                                pixels: (0..<256).flatMap { [UInt8($0), UInt8($0), UInt8($0), 255] }))
        let black = PipelineSnapshot.Picture.color(RGBAImage(width: 256, height: 1, fill: SIMD4(0, 0, 0, 255)))
        let field = try RevealField.make(from: black, to: rgb)
        for i in 0..<256 {
            let distance = ColorScience.distance(.zero, ColorScience.encodedToOKLab(SIMD3(repeating: Float(i) / 255), space: .sRGB))
            #expect((field.times[i] != nil) == (distance >= 0.02))
        }
    }

    @Test func workerBinsAndTwoChaikinRounds() throws {
        var times = [Double?](repeating: nil, count: 40)
        times[0] = 0; times[20] = 0.5; times[30] = 1
        let field = RevealField(width: 40, height: 1, seed: .left, times: times)
        let path = try ArcPath(field.workerPath(steps: 12))
        #expect(path.points.count == 12)
        #expect(path.points.first == Point(0.5, 0.5))
        #expect(path.points[1] == Point(1.75, 0.5))
        #expect(path.points[2] == Point(4.25, 0.5))
        #expect(path.points.last == Point(30.5, 0.5))
        #expect(throws: FigureInputError.self) { try field.workerPath(steps: 0) }
    }

    @Test(arguments: RevealField.Seed.allCases)
    func degeneratePathsHaveAFullStrideAndWorkInAScene(seed: RevealField.Seed) throws {
        let cases = [
            (gray(1, 1, [0]), gray(1, 1, [255]), Point(0.5, 0.5)),
            // All strongest pixels seed at once; the field has one time bin.
            (gray(3, 1, [0, 0, 0]), gray(3, 1, [255, 255, 255]), Point(1.5, 0.5)),
            // Center-seeded radial waves have several bins with coincident centroids.
            (gray(3, 3, Array(repeating: 0, count: 9)),
             gray(3, 3, Array(repeating: 255, count: 9)), Point(1.5, 1.5))
        ]
        let spec = FigureSpec(), stride = spec.motion.step * spec.normalizationScale * 50
        for (a, b, centroid) in cases {
            let field = try RevealField.make(from: a, to: b, seed: seed)
            let data = try field.workerPath(), path = try ArcPath(data)
            #expect(path.length >= stride)
            #expect((path.sample(0.5).point - centroid).length < 0.01)
            #expect((path.points.last! - path.points.first!).unit.dot(Point(1, 0)) > 0.99)
            #expect(try field.workerPath() == data)
            let scene = try JSONDecoder().decode(FigureScene.self, from: Data("""
                {"canvas":{"width":40,"height":40},"paths":{"reveal":"\(data)"},
                 "actors":[{"id":"worker","at":{"path":"reveal","t":0},
                            "timeline":[{"do":"walk","path":"reveal","to":1}]}],
                 "card":{"authors":"","year":0,"title":""}}
                """.utf8))
            let engine = try FigureEngine(spec: spec, scene: scene)
            #expect(engine.rig.actions[0].distance >= engine.rig.actions[0].stepLength)
            #expect(engine.actions[0].end > 0)
        }
    }

    @Test(arguments: [Point(1, 0), Point(-1, 0), Point(0, 1), Point(0, -1), Point(1, 1).unit])
    func oneBinRetainsTheWipeDirection(direction: Point) throws {
        var times = [Double?](repeating: nil, count: 9)
        let dx = Int(direction.x.rounded()), dy = Int(direction.y.rounded())
        times[(1 - dy) * 3 + 1 - dx] = 0
        times[4] = 0.5
        times[(1 + dy) * 3 + 1 + dx] = 1
        let field = RevealField(width: 3, height: 3, seed: .left, times: times)
        let path = try ArcPath(field.workerPath(steps: 1))
        #expect((path.sample(0.5).point - Point(1.5, 1.5)).length < 0.01)
        #expect((path.points.last! - path.points.first!).unit.dot(direction) > 0.99)
        let spec = FigureSpec()
        #expect(path.length >= spec.motion.step * spec.normalizationScale * 50)
    }

    @Test func pgmReservesZeroAndIncludesBothTimeEndpoints() throws {
        let field = RevealField(width: 5, height: 1, seed: .left, times: [nil, 0, 0.25, 0.5, 1])
        let expected = Data("P5\n5 1\n255\n".utf8) + Data([0, 1, 65, 128, 255])
        #expect(field.encodedPGM() == expected)
        #expect(try RevealSnapshots.read(expected) == gray(5, 1, [0, 1, 65, 128, 255]))
    }

    @Test(arguments: RevealField.Seed.allCases)
    func deterministicBytes(seed: RevealField.Seed) throws {
        let a = gray(5, 3, Array(repeating: 0, count: 15))
        let b = gray(5, 3, [0, 90, 90, 0, 200, 90, 0, 90, 0, 0, 90, 90, 90, 0, 100])
        let first = try RevealField.make(from: a, to: b, seed: seed)
        let second = try RevealField.make(from: a, to: b, seed: seed)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        #expect(first == second)
        #expect(first.encodedPGM() == second.encodedPGM())
        #expect(try encoder.encode(first.metadata()) == encoder.encode(second.metadata()))
    }

    @Test func snapshotReaderKeepsBinaryWhitespaceAndRejectsBadHeaders() throws {
        let data = Data("P5\r\n# snapshot\r\n3 1\r\n255\r\n".utf8) + Data([10, 32, 35])
        #expect(try RevealSnapshots.read(data) == gray(3, 1, [10, 32, 35]))
        let rgb = Data("P6\n1 1\n255\n".utf8) + Data([9, 10, 32])
        #expect(try RevealSnapshots.read(rgb) == .color(RGBAImage(width: 1, height: 1, pixels: [9, 10, 32, 255])))
        for header in ["P5\n-1 1\n255\n", "P5\n0 1\n255\n", "P5\n9223372036854775807 9\n255\n",
                       "P6\n2 1\n255\nxx", "P5\n1 1\n65535\n", "P5\n1 1\n255", "P3\n1 1\n255\n"] {
            #expect(throws: FigureInputError.self) { try RevealSnapshots.read(Data(header.utf8)) }
        }
        #expect(throws: FigureInputError.self) {
            try RevealField.make(from: gray(1, 1, [0]), to: gray(2, 1, [0, 0]))
        }
    }
}
