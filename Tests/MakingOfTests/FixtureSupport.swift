import Foundation
import Testing
@testable import MakingOf

/// `Fixtures/plan-parrots.json`, which `making_of_clip.py --plan-json` writes (see `CrewPlan`'s
/// doc comment): the spec and inputs a crew was planned from by `making_of_pets.py`, the plan, and
/// every guardian's state 30 times a second.
struct PlanFixture: Decodable {
    var spec: ShowSpec
    var inputs: Inputs
    var plan: Plan
    var states: States

    struct Inputs: Decodable {
        struct Member: Decodable {
            var id: String
            var start: [Double]
        }

        var size: [Double]
        var petHeight: Double
        var intro: Double
        var step: Double
        var seed: UInt64
        var pets: [Member]
        var candidates: [[[Double]]]
        var strokes: [[[Double]]]
        var frameHeight: Double

        var crewInputs: CrewInputs {
            CrewInputs(
                width: size[0], height: size[1], petHeight: petHeight, intro: intro, step: step, seed: seed,
                pets: pets.map { .init(id: $0.id, start: Point($0.start[0], $0.start[1])) },
                candidates: candidates.map { $0.map { Point($0[0], $0[1]) } },
                strokes: strokes.map { $0.map { Point($0[0], $0[1]) } }, frameHeight: frameHeight)
        }
    }

    struct Plan: Decodable {
        struct Pet: Decodable {
            var id: String
            var appear: Double
            var stops: [Stop]
            var walks: [Walk]
        }

        struct Stop: Decodable {
            var arrive: Double
            /// Null for the last stop, which never leaves.
            var leave: Double?
            var x: Double
            var y: Double
            /// -1 pops in, 0 to 5 is a job, -4 takes a last look, -2 waves, -3 walks out.
            var step: Int
            var path: [[Double]]?
        }

        struct Walk: Decodable {
            var leave: Double
            var arrive: Double
            var length: Double
            var distance: Double
            var hurry: Double
            var before: Double
            var bend: Double
        }

        struct Trace: Decodable {
            var stroke: Int
            var start: Double
            var duration: Double
            var points: [[Double]]
        }

        var pets: [Pet]
        var visits: [[[Double]]]
        var traces: [Trace]
    }

    struct States: Decodable {
        var fps: Int
        var pets: [[Row]]
    }

    /// [x, y, lift, row, frame, sx, sy, tilt, alpha].
    struct Row: Decodable {
        var x, y, lift: Double
        var row: String
        var frame: Int
        var sx, sy, tilt, alpha: Double

        init(from decoder: any Decoder) throws {
            var c = try decoder.unkeyedContainer()
            x = try c.decode(Double.self)
            y = try c.decode(Double.self)
            lift = try c.decode(Double.self)
            row = try c.decode(String.self)
            frame = try c.decode(Int.self)
            sx = try c.decode(Double.self)
            sy = try c.decode(Double.self)
            tilt = try c.decode(Double.self)
            alpha = try c.decode(Double.self)
        }
    }

    static func load() throws -> PlanFixture {
        let url = try #require(Bundle.module.url(forResource: "plan-parrots.json", withExtension: nil, subdirectory: "Fixtures"))
        return try JSONDecoder().decode(PlanFixture.self, from: Data(contentsOf: url))
    }
}

/// `making-of.json` as shipped with the app, for the tests that read the real file.
func shippedSpecData() throws -> Data {
    let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    return try Data(contentsOf: repo.appendingPathComponent("App/PaintByNumber/Resources/making-of.json"))
}

/// `pet-metrics.json` as shipped with the app, read through `#filePath` like the spec.
func shippedMetricsData() throws -> Data {
    let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    return try Data(contentsOf: repo.appendingPathComponent("App/PaintByNumber/Resources/pet-metrics.json"))
}

/// Collects what differs between two things, to report it together.
struct Differences {
    private(set) var found: [String] = []

    mutating func close(_ what: @autoclosure () -> String, _ a: Double, _ b: Double, within tolerance: Double) {
        if a != b && !(abs(a - b) <= tolerance) {
            found.append("\(what()): \(a) against \(b)")
        }
    }

    mutating func equal<T: Equatable>(_ what: @autoclosure () -> String, _ a: T, _ b: T) {
        if a != b {
            found.append("\(what()): \(a) against \(b)")
        }
    }

    var count: Int { found.count }

    /// The first few, for a failure message.
    var report: String {
        "\(found.count) differences, first: " + found.prefix(8).joined(separator: "; ")
    }
}
