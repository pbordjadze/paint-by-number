import Foundation
import PaintCore
import Testing
@testable import MakingOf

/// `Fixtures/reveal-small.json`, which `making_of_reveal.py --fixture` writes (see its docstring):
/// the schedule's inputs on the small show fixture (216 x 144), injected so these tests don't
/// depend on the code that picks a real show's spots and paints, and everything the module
/// computed from them. Labels are `Plane<Int32>`.
struct RevealFixture: Decodable {
    var spec: ShowSpec
    var inputs: Inputs
    var expected: Expected

    struct Inputs: Decodable {
        struct TraceData: Decodable {
            var stroke: Int
            var start: Double
            var duration: Double
            var points: [[Double]]
        }

        struct Labels: Decodable {
            var count: Int
            var runs: [[Int]]
        }

        var size: [Int]
        var petHeight: Double
        var seed: UInt64
        var sampling: Int
        var visits: [[[Double]]]
        var traces: [TraceData]
        var strokes: [[[Double]]]
        var numbers: [[Double]]
        /// [time, x, y, paint].
        var seeds: [[Double]]
        var paints: Int
        var paintOfRegion: [Int]
        var paletteLabels: Labels
        var simplifiedLabels: Labels
    }

    struct Expected: Decodable {
        struct Lattice: Decodable {
            var first: [Double]
            var fingerprint: String
        }

        struct Lattices: Decodable {
            var coarse: Lattice
            var fine: Lattice
        }

        struct Field: Decodable {
            var samples: [Double]
            var fingerprint: String
            var max: Double?
            var min: Double?
        }

        struct Paints: Decodable {
            var first: [Double]
            var fingerprint: String
            var spread: [Double]
        }

        struct StrokePin: Decodable {
            var walked: Bool
            var t0: Double
            var dur: Double
            var jagged: Int
            var smooth: Int
            var length: Double
            var jaggedFingerprint: String
            var smoothFingerprint: String
            var relaxFingerprint: String
            var relaxMin: Double
            var relaxMax: Double
        }

        struct StrokeDetail: Decodable {
            var index: Int
            var jagged: [[Double]]
            var smooth: [[Double]]
            var cumulative: [Double]
            var relax: [Double]
        }

        struct Lines: Decodable {
            struct Line: Decodable {
                var stroke: Int
                var points: Int
                var value: Double
            }

            var time: Double
            var lines: [Line]
            var fingerprint: String
        }

        struct Bounds: Decodable {
            var jaggedFingerprint: String
            var smoothFingerprint: String
        }

        struct Runs: Decodable {
            var runs: [[Int]]
        }

        var lattices: [Lattices]
        var noise: [Field]
        var arrival: [Field]
        var paints: Paints
        var merged: [Double]
        var lift: [Double]
        var clear: [Double]
        var strokes: [StrokePin]
        var order: [Int]
        var strokeDetail: [StrokeDetail]
        var lines: [Lines]
        var bounds: Bounds
        var numbers: [Double]
        var discs: Runs
    }

    static func load() throws -> RevealFixture {
        let url = try #require(Bundle.module.url(forResource: "reveal-small.json", withExtension: nil, subdirectory: "Fixtures"))
        return try JSONDecoder().decode(RevealFixture.self, from: Data(contentsOf: url))
    }

    // MARK: The inputs as the schedule takes them

    var width: Int { inputs.size[0] }
    var height: Int { inputs.size[1] }
    var timing: ScheduleTiming { ScheduleTiming(spec) }
    var streams: ShowStreams { ShowStreams(seed: inputs.seed) }
    var visits: [[Visit]] { inputs.visits.map { $0.map { Visit(time: $0[0], x: $0[1], y: $0[2]) } } }
    var strokes: [Polyline] { inputs.strokes.map { Polyline($0.map { Point($0[0], $0[1]) }) } }
    var traces: [Trace] {
        inputs.traces.map {
            Trace(stroke: $0.stroke, start: $0.start, duration: $0.duration, line: Polyline($0.points.map { Point($0[0], $0[1]) }))
        }
    }
    var numbers: [(x: Double, y: Double, size: Double)] { inputs.numbers.map { (x: $0[0], y: $0[1], size: $0[2]) } }
    var seeds: [PaintSeed] {
        inputs.seeds.map { PaintSeed(time: $0[0], x: $0[1], y: $0[2], paint: Int($0[3])) }
    }
    var paletteLabels: Plane<Int32> { Self.plane(inputs.paletteLabels.runs, width: width, height: height) }
    var simplifiedLabels: Plane<Int32> { Self.plane(inputs.simplifiedLabels.runs, width: width, height: height) }
    /// The paint of every pixel: a palette region has one colour, so one paint.
    var paints: Plane<Int32> {
        var plane = paletteLabels
        plane.data = plane.data.map { Int32(inputs.paintOfRegion[Int($0)]) }
        return plane
    }

    static func plane(_ runs: [[Int]], width: Int, height: Int) -> Plane<Int32> {
        var data: [Int32] = []
        data.reserveCapacity(width * height)
        for run in runs { data.append(contentsOf: repeatElement(Int32(run[0]), count: run[1])) }
        return Plane(width: width, height: height, data: data)
    }

    /// Step k's field, as the show builds it.
    func arrival(_ k: Int) -> Plane<Double> {
        Arrival.field(step: k, visits: visits[k], width: width, height: height, timing: timing, streams: streams)
    }
}

/// FNV-1a (64 bit) over the IEEE bytes of `values`, least significant first, as 16 hex digits:
/// `fingerprint` in `making_of_reveal.py`.
func fingerprint(_ values: some Sequence<Double>) -> String {
    var hash: UInt64 = 0xCBF2_9CE4_8422_2325
    for value in values {
        var bits = value.bitPattern
        for _ in 0..<8 {
            hash = (hash ^ (bits & 0xFF)) &* 0x100_0000_01B3
            bits >>= 8
        }
    }
    let hex = String(hash, radix: 16)
    return String(repeating: "0", count: 16 - hex.count) + hex
}

func fingerprint(_ points: [Point]) -> String {
    fingerprint(points.flatMap { [$0.x, $0.y] })
}

/// A plane's values at every `every`th pixel, row by row.
func samples(_ plane: Plane<Double>, every: Int) -> [Double] {
    var out: [Double] = []
    for y in stride(from: 0, to: plane.height, by: every) {
        for x in stride(from: 0, to: plane.width, by: every) { out.append(plane[x, y]) }
    }
    return out
}

/// Where two big arrays first differ, or nil: `#expect` on the arrays themselves would print them
/// whole, which takes minutes for a plane.
func firstDifference<T: Equatable>(_ a: [T], _ b: [T]) -> String? {
    if a.count != b.count { return "\(a.count) values against \(b.count)" }
    guard let i = a.indices.first(where: { a[$0] != b[$0] }) else { return nil }
    return "value \(i): \(a[i]) against \(b[i])"
}
