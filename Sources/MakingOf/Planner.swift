import Foundation
import PaintCore

/// When a pet changes the picture where it works: a moment, and where.
public struct Visit: Sendable, Equatable {
    public var time: Double
    public var x: Double
    public var y: Double
}

/// A line drawn by a pet walking along it.
public struct Trace: Sendable, Equatable {
    /// The line's index in the strokes the plan was made from.
    public var stroke: Int
    public var start: Double
    public var duration: Double
    /// In drawing order, which may be the stroke's reversed.
    public var line: Polyline
}

/// Hands out the jobs. A pet stands beside its spot (`side`), on the side it came from, so the
/// change it makes is never hidden under it; spots of pets working at the same time stay `space`
/// apart; arrivals land on the step's quarter beats, rippling left to right, the first on the
/// step's own downbeat when a pet can be there by then. Each pet has its band of the picture
/// (`bands`, by where it pops in) and takes a job elsewhere only when its band has none it can
/// reach in time.
struct Planner {
    var pets: [PetPlan]
    var rng: SplitMix64
    private let crew: ShowSpec.Crew
    private let width: Double
    private let height: Double
    private let h: Double
    private let beat: Double
    private let origin: Double
    /// Where feet may work.
    private let box: (x0: Double, y0: Double, x1: Double, y1: Double)
    private let bands: Int
    private let band: [Int]
    private var taken: [Taken] = []

    private struct Taken {
        var from: Double
        var to: Double
        var x: Double
        var y: Double
        var pet: Int
    }

    init(pets: [PetPlan], rng: SplitMix64, crew: ShowSpec.Crew, size: Point, petHeight: Double, beat: Double, origin: Double) {
        self.pets = pets
        self.rng = rng
        self.crew = crew
        (width, height) = (size.x, size.y)
        h = petHeight
        self.beat = beat
        self.origin = origin
        let m = crew.margin
        box = (m * size.x, m * size.y + petHeight, (1 - m) * size.x, size.y - 4)
        let n = pets.count
        bands = max(1, min(crew.bands, n))
        // by where each pops in, left to right; the first of two at one x is the first listed
        let order = pets.indices.sorted { (pets[$0].stops[0].x, $0) < (pets[$1].stops[0].x, $1) }
        var band = [Int](repeating: 0, count: n)
        for (rank, i) in order.enumerated() {
            band[i] = rank * bands / n
        }
        self.band = band
    }

    private func inBand(_ i: Int, _ x: Double) -> Bool {
        let w = (box.x1 - box.x0) / Double(bands)
        let b = Double(band[i])
        return box.x0 + b * w - 0.25 * h <= x && x <= box.x0 + (b + 1) * w + 0.25 * h
    }

    private func inside(_ p: Point) -> Bool {
        box.x0 <= p.x && p.x <= box.x1 && box.y0 <= p.y && p.y <= box.y1
    }

    private func stand(_ jx: Double, _ jy: Double, from fromX: Double) -> Point {
        let side = fromX < jx ? -1.0 : 1.0
        var x = jx + side * crew.side * h
        if !(0.05 * width <= x && x <= 0.95 * width) {
            x = jx - side * crew.side * h
        }
        return Point(min(max(x, 0.05 * width), 0.95 * width), min(jy + 0.05 * h, height - 4))
    }

    /// Whether (x, y) is free for `me` from `t0` to `t1`. Pets are taller than wide: clear means
    /// side by side with room, or a whole pet apart up and down.
    private func clear(_ x: Double, _ y: Double, _ t0: Double, _ t1: Double, _ me: Int) -> Bool {
        taken.allSatisfy {
            $0.pet == me || $0.to + 0.2 < t0 || t1 + 0.2 < $0.from
                || abs(x - $0.x) >= 0.85 * crew.space * h || abs(y - $0.y) >= 1.15 * crew.space * h
        }
    }

    /// The first beat at or after `t`, a little later further right.
    private func snap(_ t: Double, _ x: Double) -> Double {
        let k = ((t - origin) / beat - 1e-6).rounded(.up)
        return origin + k * beat + 0.15 * x / width
    }

    /// Pet `i` kept at its last stop until it had to go.
    private mutating func depart(_ i: Int, _ time: Double) {
        if time > pets[i].lastStop.leave {
            pets[i].stops[pets[i].stops.count - 1].leave = time
        }
    }

    /// The live pet that is free first (the first listed, of equals).
    private func nextPet(_ live: [Bool], _ free: [Double]) -> Int? {
        var best: Int?
        for j in live.indices where live[j] {
            if best.map({ free[j] < free[$0] }) ?? true {
                best = j
            }
        }
        return best
    }

    /// Jobs at `candidates` (spots) for step `k`; returns the seeds its change spreads from, a
    /// short sweep beside each pet as it works.
    mutating func step(from t0: Double, to tEnd: Double, candidates: [Point], k: Int) -> [Visit] {
        var pool = candidates
        var seeds: [Visit] = []
        var free = pets.map { $0.lastStop.leave }
        var live = [Bool](repeating: true, count: pets.count)
        while let i = nextPet(live, free), !pool.isEmpty {
            let here = pets[i].lastStop.end
            var best: (arrive: Double, q: Int, spot: Point, d: Double, reach: Double)?
            search: for own in [true, false] {
                for (q, c) in pool.enumerated() where inBand(i, c.x) == own {
                    if best != nil && !inBand(i, c.x) {
                        break search                    // a job in its own band always comes first
                    }
                    var spot = stand(c.x, c.y, from: here.x)
                    var d = norm(spot.x - here.x, spot.y - here.y)
                    if d < crew.still * h {             // near enough to reach from here: no little shuffle over
                        spot = here
                        d = 0
                    }
                    let reach = max(free[i] + crew.walkTime(d, h), t0)  // compared unsnapped: the beat's
                    let arrive = snap(reach, spot.x)                    // ripple must not pull anyone sideways
                    if arrive + crew.work.lowerBound > tEnd
                        || !clear(spot.x, spot.y, arrive, arrive + crew.work.upperBound, i) {
                        continue
                    }
                    if best.map({ reach < $0.reach }) ?? true {
                        best = (arrive, q, spot, d, reach)
                    }
                }
            }
            guard let chosen = best else {
                live[i] = false
                continue
            }
            let job = pool.remove(at: chosen.q)
            depart(i, chosen.arrive - crew.walkTime(chosen.d, h))
            let leave = min(chosen.arrive + rng.uniform(crew.work.lowerBound, crew.work.upperBound), tEnd)
            pets[i].stops.append(Stop(
                arrive: chosen.arrive, leave: leave, x: chosen.spot.x, y: chosen.spot.y, kind: .job(k), path: nil))
            taken.append(Taken(from: chosen.arrive, to: leave, x: chosen.spot.x, y: chosen.spot.y, pet: i))
            free[i] = leave
            let toward = job.x >= chosen.spot.x ? 1.0 : -1.0
            for (f, dx) in [(0.1, -0.2), (0.35, 0.05), (0.6, 0.25)] {
                seeds.append(Visit(
                    time: chosen.arrive + f * (leave - chosen.arrive), x: job.x + toward * dx * h, y: job.y))
            }
        }
        return seeds
    }

    /// Step `k`'s lines: each free pet walks to the nearest line it can draw in time and draws it
    /// by walking along it. Returns the seeds and the lines drawn.
    mutating func trace(from t0: Double, to tEnd: Double, strokes: [Polyline], k: Int) -> (seeds: [Visit], traces: [Trace]) {
        var seeds: [Visit] = []
        var traces: [Trace] = []
        var pool = strokes.enumerated().filter { $0.element.length >= 0.9 * h }.map { (n: $0.offset, line: $0.element) }
        var free = pets.map { $0.lastStop.leave }
        var live = [Bool](repeating: true, count: pets.count)
        while let i = nextPet(live, free), !pool.isEmpty {
            let here = pets[i].lastStop.end
            var best: (arrive: Double, n: Int, dur: Double, line: Polyline, d: Double, reach: Double)?
            // a line starting in its own band always comes first
            var starts: [(own: Bool, n: Int, line: Polyline)] = []
            for own in [true, false] {
                for (n, s) in pool {
                    for line in [s, s.reversed] {
                        let first = line.points[0]
                        if inside(first) && inBand(i, first.x) == own {
                            starts.append((own, n, line))
                        }
                    }
                }
            }
            for (own, n, line) in starts {
                if best != nil && !own { break }
                let first = line.points[0]
                let d = norm(first.x - here.x, first.y - here.y)
                let reach = max(free[i] + crew.walkTime(d, h), t0)
                let arrive = snap(reach, first.x)
                let dur = crew.traceTime(line.length, h)
                if arrive + dur > tEnd || !clear(first.x, first.y, arrive, arrive + 0.4, i) {
                    continue
                }
                if best.map({ reach < $0.reach }) ?? true {
                    best = (arrive, n, dur, line, d, reach)
                }
            }
            guard let chosen = best else {
                live[i] = false
                continue
            }
            pool.removeAll { $0.n == chosen.n }
            let first = chosen.line.points[0]
            depart(i, chosen.arrive - crew.walkTime(chosen.d, h))
            pets[i].stops.append(Stop(
                arrive: chosen.arrive, leave: chosen.arrive + chosen.dur, x: first.x, y: first.y, kind: .job(k),
                path: chosen.line))
            taken.append(Taken(from: chosen.arrive, to: chosen.arrive + 0.4, x: first.x, y: first.y, pet: i))
            free[i] = chosen.arrive + chosen.dur + 0.12
            traces.append(Trace(stroke: chosen.n, start: chosen.arrive, duration: chosen.dur, line: chosen.line))
            for j in 0...5 {
                let f = Double(j) / 5
                let at = chosen.line.point(at: f * chosen.line.length)
                seeds.append(Visit(time: chosen.arrive + chosen.dur * f, x: at.x, y: at.y))
            }
        }
        return (seeds, traces)
    }

    /// Whether walking from `a` to `b` passes over a pet standing at `o` (boxes as in `clear`).
    private func crosses(_ a: Point, _ b: Point, _ o: Point) -> Bool {
        let l2 = (b.x - a.x) * (b.x - a.x) + (b.y - a.y) * (b.y - a.y)
        let u = min(max(((o.x - a.x) * (b.x - a.x) + (o.y - a.y) * (b.y - a.y)) / max(l2, 1e-9), 0), 1)
        let px = a.x + u * (b.x - a.x)
        let py = a.y + u * (b.y - a.y)
        return abs(px - o.x) < 0.85 * crew.space * h && abs(py - o.y) < 1.15 * crew.space * h
    }

    /// The goodbye: each pet takes a last look at the finished picture (`crew.look` s, reviewing),
    /// waves where it stands from `waveAt[i]` for `crew.wave` s, then walks briskly to the nearest
    /// edge whose way doesn't cross a pet still there, and steps out of the frame. The last one out
    /// stops just inside that edge, turns to you and waves once more (`crew.edgeWave` s) first.
    mutating func farewell(waveAt: [Double], frameHeight: Double) {
        let spots = pets.map { $0.lastStop.end }
        var leaving: [(off: Double, exit: Point)] = []
        for i in pets.indices {
            let prev = pets[i].lastStop
            let here = spots[i]
            let done: Double
            if let path = prev.path {
                done = prev.arrive + crew.traceTime(path.length, h)
            } else if case .job = prev.kind {
                done = prev.leave
            } else {
                done = prev.arrive
            }
            let at = max(waveAt[i], done)
            depart(i, at)
            pets[i].stops.append(Stop(arrive: at, leave: at + crew.look, x: here.x, y: here.y, kind: .look, path: nil))
            pets[i].stops.append(Stop(
                arrive: at + crew.look, leave: at + crew.look + crew.wave, x: here.x, y: here.y, kind: .wave, path: nil))
            let candidates = [
                Point(-0.7 * h, here.y), Point(width + 0.7 * h, here.y), Point(here.x, -0.25 * h),
                Point(here.x, frameHeight + 1.2 * h),
            ]
            // the nearest first, the first listed of equals
            let exits = candidates.indices.sorted {
                let a = norm(candidates[$0].x - here.x, candidates[$0].y - here.y)
                let b = norm(candidates[$1].x - here.x, candidates[$1].y - here.y)
                return (a, $0) < (b, $1)
            }.map { candidates[$0] }
            let others = spots.indices.filter { $0 != i }.map { spots[$0] }
            let exit = exits.first { e in !others.contains { crosses(here, e, $0) } } ?? exits[0]
            let need = crew.walkTime(norm(exit.x - here.x, exit.y - here.y), h) / crew.exit
            leaving.append((at + crew.look + crew.wave + need, exit))
        }
        // the last one out; of equals, the later listed, as the reference's tuple max picks
        let last = leaving.indices.max { (leaving[$0].off, $0) < (leaving[$1].off, $1) }
        for i in pets.indices {
            var (off, exit) = leaving[i]
            if i == last {
                // it stops where it can still be seen whole, and waves to you before it goes
                let here = spots[i]
                let spot = exit.x < 0 || exit.x > width
                    ? Point(exit.x < 0 ? 0.5 * h : width - 0.5 * h, here.y)
                    : Point(here.x, exit.y < 0 ? 1.05 * h : height - 4)
                let at = pets[i].lastStop.leave + crew.walkTime(norm(spot.x - here.x, spot.y - here.y), h) / crew.exit
                pets[i].stops.append(Stop(
                    arrive: at, leave: at + crew.edgeWave, x: spot.x, y: spot.y, kind: .wave, path: nil))
                off = at + crew.edgeWave + crew.walkTime(norm(exit.x - spot.x, exit.y - spot.y), h) / crew.exit
            }
            pets[i].stops.append(Stop(arrive: off, leave: .infinity, x: exit.x, y: exit.y, kind: .exit, path: nil))
        }
    }

    /// Builds every pet's walks once all the stops are planned.
    mutating func finishPets() {
        for i in pets.indices {
            pets[i].finish(&rng)
        }
    }
}
