#if canImport(FoundationEssentials) && !canImport(Darwin)
import FoundationEssentials
#else
import Foundation
#endif

/// Watercolor's Making Of (painting-company row 373): a new painting painted once by the real
/// simulation, fast, before the painter paints it themselves. It is a tap log like a painter's
/// (`WatercolorLog`, played into a `WatercolorSim` of its own by `play(_:to:cursor:)`), laid as a
/// watercolorist lays a picture: its signature paints first (the picture's boldest colors, so
/// something saturated and plainly wet happens in the first moment), then the light washes, the big ones of each value before the
/// small, the darks last, in a few overlapping waves, and a few drops of clean water charged into
/// the broad washes still damp, to bloom; and a clock (`step(at:)`) that shows it as a
/// time-lapse, the floods a little faster than life and the drying hurried, shown as one front
/// sweeping the sheet (`dryingFront(at:)`), until it has passed (`isSettled`).
///
/// Nothing here is canned: every frame is the simulation's state at that moment, drawn as the
/// painting screen draws it. Deterministic like the simulation: the same template and seed make
/// the same Making Of. Measured with `pbn watercolor --making-of` (its doc comment).
public struct WatercolorMakingOf: Sendable {
    /// The taps, in step order: every area once with its own paint, and the blooms' water.
    public let log: WatercolorLog
    /// The step of the last tap.
    public let lastTapStep: Int
    /// Where the film pushes in as the sheet dries: the bloom nearest the middle, canvas units
    /// (nil without one), so the push never runs into a corner.
    public let focus: SIMD2<Float>?
    /// The areas laid first, in order (`signatures`).
    public let signatures: [Int]

    /// Washes, light to dark: few enough that each reads as a stage of the painting, enough that
    /// the darks come last.
    public static let waves = 5
    /// Simulation seconds from one wave to the next, and the span a wave's taps spread over: a
    /// wave begins while the one before is still wet, as the passes of a painting are laid one
    /// into the next.
    public static let waveSeconds: Float = 1.0
    public static let waveSpread: Float = 0.8
    /// The signature paints: the paints covering most of the sheet in saturated color (OKLab
    /// chroma at least `signatureChroma`), whatever their value (a picture's signature is often
    /// its darkest blue), each laid in up to `signatureAreas` of its largest areas at once,
    /// `signatureSeconds` apart from the start (critic round 2: the first second showed only
    /// pale washes, and a paint split into many small areas showed as a fleck).
    public static let signatureCount = 3
    public static let signatureAreas = 4
    public static let signatureSeconds: Float = 0.25
    public static let signatureChroma: Float = 0.08
    /// Drops of water charged into the broadest mid-value washes as the darks go on.
    public static let blooms = 4

    /// The time-lapse: simulation seconds per second shown while the washes go on and once the
    /// last is laid (the drying), and the seconds shown over which the one eases into the other.
    /// The clock starts `lead` simulation seconds in, so the first wash is already flooding
    /// in the first frames. The drying is hurried hardest (critic round 1: a still film
    /// once the paint was down), and the film pushes in toward a bloom meanwhile.
    public static let floodSpeed: Double = 1.6
    public static let dryingSpeed: Double = 9
    public static let easing: Double = 0.5
    public static let lead: Double = 0.25
    /// The drying as the film shows it: a front sweeping the sheet from its top left corner to
    /// its bottom right over `frontSeconds` of simulation after the last tap, wet paint ahead of
    /// it and matte behind, its edge `frontWidth` of the diagonal soft on either side. The
    /// simulation's own drying, cell by cell as its water ran out, read as round grey blotches
    /// over a pale wash (critic round 3); the pigment under the front is the simulation's still.
    public static let frontSeconds: Float = 10
    public static let frontWidth: Float = 0.15
    /// Simulation seconds after the last tap over which the pencil goes from under the painted
    /// areas (the film's finished painting has no lines through it).
    public static let pencilSeconds: Float = 6

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
        // The signature paints: chroma by the paint's whole area, so what is laid first is big
        // enough to spread visibly.
        func chroma(_ r: Int) -> Float {
            let c = Int(t.regions[r].colorIndex)
            guard t.palette.indices.contains(c) else { return 0 }
            let lab = t.palette[c].oklab
            return (lab.y * lab.y + lab.z * lab.z).squareRoot()
        }
        var byPaint: [UInt32: [Int]] = [:]
        for r in 0..<n where chroma(r) >= Self.signatureChroma { byPaint[t.regions[r].colorIndex, default: []].append(r) }
        var weight: [UInt32: Float] = [:]
        for (paint, members) in byPaint { weight[paint] = chroma(members[0]) * members.reduce(0) { $0 + t.regions[$1].area } }
        let boldest = byPaint.keys.sorted { weight[$0]! != weight[$1]! ? weight[$0]! > weight[$1]! : $0 < $1 }
        var signatures: [Int] = []
        for (i, paint) in boldest.prefix(Self.signatureCount).enumerated() {
            for r in byPaint[paint]!.sorted(by: bigFirst).prefix(Self.signatureAreas) {
                let p = point(r)
                taps.append(.init(step: step(Self.signatureSeconds * Float(i)), region: r, x: p.x, y: p.y, paint: true))
                signatures.append(r)
            }
        }
        let first = Set(signatures)
        for k in 0..<Self.waves {
            // Within a wave the big areas go first and the small ones are dotted in after, as a
            // brush lays the broad passages and then picks out the rest.
            let members = (0..<n).filter { wave[$0] == k && !first.contains($0) }.sorted(by: bigFirst)
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
        var focus: SIMD2<Float>?
        for (i, r) in middle.prefix(Self.blooms).enumerated() {
            let b = t.regions[r].bounds
            // Off the wash's middle, toward a corner of its box, so the bloom spreads across it.
            let corner = SIMD2(Float(i % 2 == 0 ? b.minX : b.maxX), Float(i < 2 ? b.minY : b.maxY))
            let p = point(r) + 0.35 * (corner - point(r))
            let at = t.region(at: p) == r ? p : point(r)
            let centre = SIMD2(Float(t.width), Float(t.height)) / 2
            func far(_ p: SIMD2<Float>) -> Float { ((p - centre) * (p - centre)).sum() }
            if focus.map({ far($0) > far(at) }) ?? true { focus = at }
            taps.append(.init(step: step(last + 0.15 * Float(i)), region: r, x: at.x, y: at.y, paint: false))
        }
        taps.sort { $0.step != $1.step ? $0.step < $1.step : ($0.paint != $1.paint ? $0.paint : $0.region < $1.region) }
        log = WatercolorLog(seed: sheet.seed, taps: taps)
        lastTapStep = taps.last?.step ?? 0
        self.focus = focus
        self.signatures = signatures
        drops = nil
    }

    /// A tap of water alone is a drop (`WatercolorSim.drop`) of this radius in cells and this
    /// much water, rather than a wash of clean water over the whole area: the study's blooms.
    let drops: (radius: Float, water: Float)?

    init(log: WatercolorLog, focus: SIMD2<Float>?, signatures: [Int], drops: (radius: Float, water: Float)?) {
        self.log = log
        self.drops = drops
        lastTapStep = log.taps.last?.step ?? 0
        self.focus = focus
        self.signatures = signatures
    }

    /// Whether every tap is laid: from here the film is the drying.
    public func isDrying(_ sim: WatercolorSim) -> Bool { sim.step > lastTapStep }

    /// How far the pencil has gone from under the painted areas at simulation time `t`, 0…1.
    public func pencilFade(at t: Float) -> Float {
        min(max((t - Float(lastTapStep) * WatercolorSim.dt) / Self.pencilSeconds, 0), 1)
    }

    /// Where the drying front stands at simulation time `t`, along the sheet's diagonal (0 its
    /// top left corner, 1 its bottom right, `(x + y) / 2` in fractions of the sheet): from
    /// `-frontWidth` (all of it ahead, wet) at the last tap to `1 + frontWidth` (all of it dry).
    public func dryingFront(at t: Float) -> Float {
        let u = min(max((t - Float(lastTapStep) * WatercolorSim.dt) / Self.frontSeconds, 0), 1)
        return -Self.frontWidth + u * (1 + 2 * Self.frontWidth)
    }

    /// Steps `sim` to `step`, laying each tap as its step comes; `cursor` is the next tap. The
    /// steps taken (a dry sheet with no tap due skips ahead for nothing).
    @discardableResult
    public func play(_ sim: WatercolorSim, to step: Int, cursor: inout Int) -> Int {
        var taken = 0
        while sim.step < step {
            while cursor < log.taps.count, log.taps[cursor].step <= sim.step {
                let tap = log.taps[cursor]
                if !tap.paint, let drops {
                    sim.drop(at: SIMD2(tap.x, tap.y), radius: drops.radius, water: drops.water)
                } else {
                    sim.tap(region: tap.region, at: SIMD2(tap.x, tap.y), paint: tap.paint)
                }
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

    /// Whether the Making Of has played out: every tap laid and the drying front's soft edge
    /// reaching the sheet's far corner, which it leaves while the painting is held (or the sheet
    /// already dry, its clock stopped).
    public func isSettled(_ sim: WatercolorSim, cursor: Int) -> Bool {
        guard cursor >= log.taps.count else { return false }
        return !sim.isActive || dryingFront(at: sim.time) >= 1
    }

    /// The simulation's step to show `seconds` after the Making Of began: `floodSpeed` until the
    /// last tap, easing to `dryingSpeed` over `easing` seconds shown.
    public func step(at seconds: Double) -> Int {
        let a = Self.floodSpeed, b = Self.dryingSpeed, r = Self.easing
        let lastTap = Double(lastTapStep) * Double(WatercolorSim.dt)
        let turn = lastTap / a
        let seconds = seconds + Self.lead / a
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
