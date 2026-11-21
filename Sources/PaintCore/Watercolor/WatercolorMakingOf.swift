import Foundation

/// Watercolor's Making Of (painting-company row 373): a new painting painted once by the real
/// simulation, fast, before the painter paints it themselves. It is a tap log like a painter's
/// (`WatercolorLog`, played into a `WatercolorSim` of its own by `play(_:to:cursor:)`), laid as a
/// watercolorist lays a picture: the light washes first, the big ones of each value before the
/// small, the darks last, in a few overlapping waves, and a few drops of clean water charged into
/// the broad washes still damp, to bloom; and a clock (`step(at:)`) that shows it as a
/// time-lapse, the floods a little faster than life and the drying hurried, until the sheet has
/// all but dried (`isSettled`).
///
/// Nothing here is canned: every frame is the simulation's state at that moment, drawn as the
/// painting screen draws it. Deterministic like the simulation: the same template and seed make
/// the same Making Of. Measured with `pbn watercolor --making-of` (its doc comment).
public struct WatercolorMakingOf: Sendable {
    /// The taps, in step order: every area once with its own paint, and the blooms' water.
    public let log: WatercolorLog
    /// The step of the last tap.
    public let lastTapStep: Int

    /// Washes, light to dark: few enough that each reads as a stage of the painting, enough that
    /// the darks come last.
    public static let waves = 5
    /// Simulation seconds from one wave to the next, and the span a wave's taps spread over: a
    /// wave begins while the one before is still wet, as the passes of a painting are laid one
    /// into the next.
    public static let waveSeconds: Float = 1.0
    public static let waveSpread: Float = 0.8
    /// Drops of water charged into the broadest mid-value washes as the darks go on.
    public static let blooms = 4

    /// The time-lapse: simulation seconds per second shown while the washes go on and once the
    /// last is laid (the drying), and the seconds shown over which the one eases into the other.
    public static let floodSpeed: Double = 1.6
    public static let dryingSpeed: Double = 5
    public static let easing: Double = 0.8
    /// The share of the sheet still wet at which the Making Of has settled and may end: the last
    /// damp patches dry on while it is held and lifts away.
    public static let settledWetShare: Double = 0.03

    public init(template t: Template, sheet: WatercolorSheet) {
        let n = t.regions.count
        // Where each area's wash starts: its largest number, where a painter's eye goes.
        var start = [SIMD2<Float>?](repeating: nil, count: n)
        var radius = [Float](repeating: -1, count: n)
        for label in t.labels where Int(label.region) < n && label.radius > radius[Int(label.region)] {
            start[Int(label.region)] = label.position
            radius[Int(label.region)] = label.radius
        }
        func point(_ r: Int) -> SIMD2<Float> {
            let b = t.regions[r].bounds
            return start[r] ?? SIMD2(Float(b.minX + b.maxX) / 2, Float(b.minY + b.maxY) / 2)
        }
        // Darkness: the mean density of the area's paint, as the watercolor key lays it.
        let darkness = sheet.want.map { ($0.x + $0.y + $0.z) / 3 }
        let byValue = (0..<n).sorted { darkness[$0] != darkness[$1] ? darkness[$0] < darkness[$1] : $0 < $1 }
        var wave = [Int](repeating: 0, count: n)
        for (rank, r) in byValue.enumerated() { wave[r] = min(Self.waves - 1, rank * Self.waves / max(n, 1)) }

        var taps: [WatercolorLog.Tap] = []
        taps.reserveCapacity(n + Self.blooms)
        let dt = WatercolorSim.dt
        func step(_ seconds: Float) -> Int { Int((seconds / dt).rounded()) }
        func bigFirst(_ a: Int, _ b: Int) -> Bool {
            t.regions[a].area != t.regions[b].area ? t.regions[a].area > t.regions[b].area : a < b
        }
        for k in 0..<Self.waves {
            // Within a wave the big areas go first and the small ones are dotted in after, as a
            // brush lays the broad passages and then picks out the rest.
            let members = (0..<n).filter { wave[$0] == k }.sorted(by: bigFirst)
            let begin = Float(k) * Self.waveSeconds
            for (i, r) in members.enumerated() {
                let f = members.count > 1 ? Float(i) / Float(members.count - 1) : 0
                let p = point(r)
                taps.append(.init(step: step(begin + Self.waveSpread * f.squareRoot()), region: r, x: p.x, y: p.y, paint: true))
            }
        }
        // Blooms: clean water dropped into the broadest washes of the middle values, still damp
        // when the darks go on, pushing their pigment out into a cauliflower edge.
        let middle = (0..<n).filter { wave[$0] > 0 && wave[$0] < Self.waves - 1 }.sorted(by: bigFirst)
        let last = Float(Self.waves - 1) * Self.waveSeconds
        for (i, r) in middle.prefix(Self.blooms).enumerated() {
            let b = t.regions[r].bounds
            // Off the wash's middle, toward a corner of its box, so the bloom spreads across it.
            let corner = SIMD2(Float(i % 2 == 0 ? b.minX : b.maxX), Float(i < 2 ? b.minY : b.maxY))
            let p = point(r) + 0.35 * (corner - point(r))
            let at = t.region(at: p) == r ? p : point(r)
            taps.append(.init(step: step(last + 0.15 * Float(i)), region: r, x: at.x, y: at.y, paint: false))
        }
        taps.sort { $0.step != $1.step ? $0.step < $1.step : ($0.paint != $1.paint ? $0.paint : $0.region < $1.region) }
        log = WatercolorLog(seed: sheet.seed, taps: taps)
        lastTapStep = taps.last?.step ?? 0
    }

    /// Steps `sim` to `step`, laying each tap as its step comes; `cursor` is the next tap. The
    /// steps taken (a dry sheet with no tap due skips ahead for nothing).
    @discardableResult
    public func play(_ sim: WatercolorSim, to step: Int, cursor: inout Int) -> Int {
        var taken = 0
        while sim.step < step {
            while cursor < log.taps.count, log.taps[cursor].step <= sim.step {
                let tap = log.taps[cursor]
                sim.tap(region: tap.region, at: SIMD2(tap.x, tap.y), paint: tap.paint)
                cursor += 1
            }
            if sim.isActive || cursor < log.taps.count {
                sim.advance()
                taken += 1
            } else {
                break
            }
        }
        return taken
    }

    /// Whether the Making Of has played out: every tap laid and all but `settledWetShare` of the
    /// sheet dry.
    public func isSettled(_ sim: WatercolorSim, cursor: Int) -> Bool {
        guard cursor >= log.taps.count else { return false }
        guard sim.isActive else { return true }
        let cells = sim.sheet.width * sim.sheet.height
        let most = Int(Double(cells) * Self.settledWetShare)
        var wet = 0
        for i in 0..<cells where sim.W[i] > 0 {
            wet += 1
            if wet > most { return false }
        }
        return true
    }

    /// The simulation's step to show `seconds` after the Making Of began: `floodSpeed` until the
    /// last tap, easing to `dryingSpeed` over `easing` seconds shown.
    public func step(at seconds: Double) -> Int {
        let a = Self.floodSpeed, b = Self.dryingSpeed, r = Self.easing
        let lastTap = Double(lastTapStep) * Double(WatercolorSim.dt)
        let turn = lastTap / a
        let sim: Double
        if seconds <= turn {
            sim = a * max(seconds, 0)
        } else if seconds <= turn + r {
            let u = seconds - turn
            sim = lastTap + a * u + (b - a) * u * u / (2 * r)
        } else {
            sim = lastTap + a * r + (b - a) * r / 2 + b * (seconds - turn - r)
        }
        return Int((sim / Double(WatercolorSim.dt)).rounded(.down))
    }
}
