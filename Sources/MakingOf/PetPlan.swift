import Foundation
import PaintCore

/// A place a pet is at for a while: a job worked standing at (x, y), or a line drawn by walking
/// `path`.
public struct Stop: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        /// Where the pet pops in.
        case appear
        /// The step (0 to 5) whose job it is.
        case job(Int)
        /// A last look at the finished picture, before the wave.
        case look
        /// Waving goodbye, where it stands (and the last one out once more, just inside the edge).
        case wave
        /// Walking out of the frame, which is where it ends up.
        case exit
    }

    public var arrive: Double
    /// When it sets off for the next stop; infinite for the last.
    public var leave: Double
    public var x: Double
    public var y: Double
    public var kind: Kind
    public var path: Polyline?

    /// Where the pet is when it sets off: at the end of the line it drew, else here.
    var end: Point {
        path?.points.last ?? Point(x, y)
    }
}

/// A walk from one stop to the next: a curve of `PetPlan.curve` pieces, bent to one side.
public struct Walk: Sendable, Equatable {
    public var leave: Double
    public var arrive: Double
    /// Along the curve, and in a straight line.
    public var length: Double
    public var distance: Double
    /// How much quicker than walking pace it goes to arrive on time (1 or more).
    public var hurry: Double
    /// Distance walked before this walk, so the stride never jumps.
    public var before: Double
    /// The curve's bend: a share of the distance, either side.
    public var bend: Double
    var px: [Double]
    var py: [Double]
    var cumulative: [Double]
    /// Which way it faces as it sets off, and along each piece of the curve.
    var entry: Facing
    var faces: [Facing]
}

enum Facing: Sendable, Equatable {
    case right, left

    /// The way a walker faces after a step of `tx` px sideways: the same, if the step is tiny.
    func turned(_ tx: Double) -> Facing {
        abs(tx) <= 0.15 ? self : tx > 0 ? .right : .left
    }

    /// The way it faces after each of `steps` (px sideways), starting from this one.
    func faces(after steps: [Double]) -> [Facing] {
        var out: [Facing] = []
        var facing = self
        for tx in steps {
            facing = facing.turned(tx)
            out.append(facing)
        }
        return out
    }
}

/// A sprite sheet's row.
public enum Row: String, Sendable {
    case idle, right, left, wave, busy, review
}

/// Where a pet is and how it looks at one moment.
public struct PetState: Sendable, Equatable {
    public var x: Double
    public var y: Double
    /// How far its feet are off the ground, in pixels.
    public var lift: Double
    public var row: Row
    /// The frame in `row`, counting up for as long as the row plays: wrap it to the row's length.
    public var frame: Int { truncated(frameValue) }
    public var scaleX: Double
    public var scaleY: Double
    /// Degrees, positive turning COUNTER-clockwise, as Pillow's `rotate` takes them (the Python
    /// reference's number, which the plan fixture pins): a guardian facing right leans forward at
    /// -4, a clockwise turn. `SpriteDraw.rotation` is this negated, clockwise-positive like
    /// SwiftUI's `rotationEffect`.
    public var tilt: Double
    public var alpha: Double
    /// `frame` before it is truncated.
    var frameValue: Double
}

/// One pet's way through the show: its stops, the walks between them, and where it is at any
/// time. Planned by `CrewPlan`; once finished, `state(at:)` is a pure function of the time.
public struct PetPlan: Sendable, Equatable {
    public let id: String
    public let appear: Double
    public internal(set) var stops: [Stop]
    public internal(set) var walks: [Walk] = []
    let height: Double
    /// When each step ends, for the shared hold.
    let stepEnds: [Double]
    let crew: ShowSpec.Crew
    let poses: [ShowSpec.Pose]
    /// For each stop that draws a line, which way the pet faces at each point of it.
    private var lineFaces: [[Facing]] = []

    /// The pieces each walk's curve is cut into.
    static let curve = 64

    init(id: String, start: Stop, height: Double, stepEnds: [Double], spec: ShowSpec) {
        self.id = id
        stops = [start]
        appear = start.arrive
        self.height = height
        self.stepEnds = stepEnds
        crew = spec.crew
        poses = spec.steps.map(\.pose)
    }

    var lastStop: Stop { stops[stops.count - 1] }

    /// Builds the walks between stops once every stop is planned, and which way it faces along
    /// them: the way it last stepped sideways, carried from one walk and line to the next.
    mutating func finish(_ rng: inout SplitMix64) {
        let n = Self.curve
        walks = []
        for (s0, s1) in zip(stops, stops.dropFirst()) {
            let l0 = s0.leave
            let (x0, y0) = (s0.end.x, s0.end.y)
            let a1 = s1.arrive
            let (x1, y1) = (s1.x, s1.y)
            let dx = x1 - x0
            let dy = y1 - y0
            let d = norm(dx, dy)
            let magnitude = rng.uniform(0.06, 0.16)
            let side: Double = rng.choice([-1, 1])
            let bend = magnitude * side
            let cx = (x0 + x1) / 2 - dy * bend
            let cy = (y0 + y1) / 2 + dx * bend
            var px: [Double] = []
            var py: [Double] = []
            for i in 0...n {
                let ts = Double(i) / Double(n)
                let u = 1 - ts
                px.append(u * u * x0 + 2 * u * ts * cx + ts * ts * x1)
                py.append(u * u * y0 + 2 * u * ts * cy + ts * ts * y1)
            }
            let curve = Polyline(zip(px, py).map { Point($0, $1) })
            let need = crew.walkTime(curve.length, height) - crew.lean
            let hurry = max(1.0, need / max(a1 - l0 - crew.lean, 0.05))
            walks.append(Walk(
                leave: l0, arrive: a1, length: curve.length, distance: d, hurry: hurry, before: 0, bend: bend,
                px: px, py: py, cumulative: curve.cumulative, entry: .right, faces: []))
        }
        var total = 0.0
        for i in walks.indices {            // distance walked before each walk, so the cycle never jumps
            walks[i].before = total
            total += walks[i].length
        }
        var facing = Facing.right
        lineFaces = Array(repeating: [], count: stops.count)
        for i in walks.indices {
            let steps = zip(walks[i].px, walks[i].px.dropFirst()).map { $1 - $0 }
            walks[i].entry = facing
            walks[i].faces = facing.faces(after: steps)
            facing = walks[i].faces[walks[i].faces.count - 1]
            if let path = stops[i + 1].path {
                let line = facing.faces(after: path.cumulative.map { path.ahead(at: $0) })
                lineFaces[i + 1] = line
                facing = line[line.count - 1]
            }
        }
    }

    /// Where `dist` along a walk is, and the piece of its curve that is on.
    private func point(_ walk: Walk, _ dist: Double) -> (x: Double, y: Double, piece: Int) {
        let n = Self.curve
        let u = interp(dist, walk.cumulative) { Double($0) / Double(n) }
        let i = max(min(truncated(u * Double(n)), n - 1), 0)
        let f = u * Double(n) - Double(i)
        let x = walk.px[i] + (walk.px[i + 1] - walk.px[i]) * f
        let y = walk.py[i] + (walk.py[i + 1] - walk.py[i]) * f
        return (x, y, i)
    }

    private func walking(
        _ x: Double, _ y: Double, _ facing: Facing, walked: Double, speed: Double, extraLift: Double = 0
    ) -> PetState {
        let h = height
        let frame = walked / (crew.stride * h) * 8
        let bob = 0.022 * h * abs(sin(.pi * walked / (crew.stride * h / 2))) * min(speed, 1)
        let tilt = crew.tilt * min(speed, 1) * (facing == .right ? -1 : 1)
        return PetState(
            x: x, y: y, lift: bob + extraLift, row: facing == .right ? .right : .left, scaleX: 1, scaleY: 1,
            tilt: tilt, alpha: 1, frameValue: frame)
    }

    /// Where the pet is, and how it looks, `t` seconds into the show.
    public func state(at t: Double) -> PetState {
        let h = height
        let start = stops[0]
        if t < appear {
            return PetState(
                x: start.x, y: start.y, lift: 0, row: .idle, scaleX: 1, scaleY: 1, tilt: 0, alpha: 0, frameValue: 0)
        }
        for (i, walk) in walks.enumerated() {
            if t < walk.leave { break }
            if t < walk.arrive {
                if walk.length < 1e-6 {                         // the next job is right here: it stays put
                    return atStop(i, t, walked: walk.before)
                }
                let dt = t - walk.leave
                if dt < crew.lean {                             // the breath before setting off
                    let w = sin(.pi * dt / crew.lean)
                    let leanBack = 2.5 * w * (walk.px[walk.px.count - 1] >= walk.px[0] ? 1 : -1)
                    return PetState(
                        x: walk.px[0], y: walk.py[0], lift: 0, row: walk.entry == .right ? .right : .left,
                        scaleX: 1 + 0.05 * w, scaleY: 1 - 0.06 * w, tilt: leanBack, alpha: 1, frameValue: 0)
                }
                let k = walk.hurry
                let dist = crew.travelled((dt - crew.lean) * k, walk.length, h)
                let (x, y, piece) = point(walk, dist)
                let speed = (crew.travelled((dt - crew.lean + 0.01) * k, walk.length, h) - dist) / 0.01 / (crew.walk * h)
                let toGo = walk.arrive - t
                var hop = 0.0
                if walk.distance >= crew.hopMin * h && toGo < crew.hopTime && stops[i + 1].path == nil {
                    hop = crew.hop * h * sin(.pi * (1 - toGo / crew.hopTime))
                }
                return walking(x, y, walk.faces[piece], walked: walk.before + dist, speed: speed, extraLift: hop)
            }
            if t <= stops[i + 1].leave || i + 1 == walks.count {
                return atStop(i + 1, t, walked: walk.before + walk.length)
            }
        }
        return atStop(0, t, walked: 0)
    }

    private func holding(_ t: Double) -> Bool {
        stepEnds.contains { $0 - crew.hold <= t && t < $0 }
    }

    private func atStop(_ n: Int, _ t: Double, walked: Double) -> PetState {
        let stop = stops[n]
        var arrive = stop.arrive
        var (x, y) = (stop.x, stop.y)
        if let path = stop.path {
            let faces = lineFaces[n]
            if arrive <= t && t <= arrive + crew.traceTime(path.length, height) {     // drawing a line
                let dist = crew.traced(t - arrive, path.length, height)
                let at = path.point(at: dist)
                let speed = (crew.traced(t - arrive + 0.01, path.length, height) - dist) / 0.01 / (crew.walk * height)
                let passed = path.pointsBehind(dist)            // the first, at least
                let facing = faces[max(passed - 1, 0)].turned(path.ahead(at: dist))
                return walking(at.x, at.y, facing, walked: walked + dist, speed: speed)
            }
            (x, y) = (stop.end.x, stop.end.y)                   // the line drawn, it looks it over
            arrive += crew.traceTime(path.length, height)
        }
        let land = t - arrive
        let sy = stop.path == nil ? 1 + spring(land, -0.10, period: 0.22, decay: 0.08) : 1.0
        let sx = 1 / max(sy, 0.5).squareRoot()
        func still(_ row: Row, _ frame: Double, _ sx: Double, _ sy: Double, alpha: Double = 1) -> PetState {
            PetState(x: x, y: y, lift: 0, row: row, scaleX: sx, scaleY: sy, tilt: 0, alpha: alpha, frameValue: frame)
        }
        switch stop.kind {
        case .look:                                             // a last look at the picture
            return still(.review, (t - arrive) * 8, 1, 1)
        case .wave:                                             // waving goodbye
            return still(.wave, (t - arrive) * 7, 1, 1)
        case .exit:                                             // gone
            return still(.idle, 0, 1, 1, alpha: 0)
        case .appear, .job:
            if holding(t) { return still(.review, t * 8, sx, sy) }
            if t <= stop.leave, case .job(let step) = stop.kind {
                return still(poses.indices.contains(step) ? Row(poses[step]) : .idle, land * 8, sx, sy)
            }
            return still(.idle, t * 6, sx, sy)
        }
    }
}

extension Row {
    init(_ pose: ShowSpec.Pose) {
        self = pose == .busy ? .busy : .review
    }
}
