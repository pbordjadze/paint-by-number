import Foundation

/// Water and pigment moving over a `WatercolorSheet` (painting-company row 373): every tap floods
/// its area from the finger, the wash carries its pigment to the rim, bleeds into a neighbour still
/// wet, and dries a touch lighter with a darker edge and pigment settled in the paper's tooth.
/// After Curtis et al., "Computer-Generated Watercolor" (SIGGRAPH 1997), much simplified; the
/// reference is the spike's `wc.py` (painting-company `spikes/2026-11-20-watercolor/`).
///
/// Per cell: water `W`, pigment suspended `S` and settled `D` (three optical densities, linear
/// P3, in `.w` nothing), how the wash under it granulates `G`, how hard it pulls to its rim `E`,
/// and `L` where the brush ran on into a dry wash of its group to soften it.
///
/// The sandbox's guarantees (Paul, November 20: beauty, calm, a finished picture; inside that,
/// anything goes):
/// - No tap is wrong. A tap of an area's own paint lays its wash from where the finger touched;
///   a tap of another paint, or of an area already laid, is water alone: a bloom.
/// - The picture always reads: `targets()` rescales each area's pigment so its mean lands on its
///   paint, however the water moved it (the target solve, done where it is drawn).
/// - Order and timing show at the edges: each cell's `E` is decided when the wash reaches it, by
///   what lies past the edge then. Still-wet paint: the wash runs on into it and the two bleed,
///   no rim on either side, a dark paint carrying into a lighter one only a little (wet-in-wet).
///   Dry paper or a dried wash: a crisp edge, a touch darker (wet-on-dry). And a tide-line as
///   strong as the water the brush carried. Both are accents of broad, light washes: a small or
///   dark area dries with a faint edge. A quick painter's picture comes out soft, a slow one's
///   crisp. Every cell of an area is reached (each piece of it has its own front), so paper shows
///   only where the template leaves it.
/// - Time runs in fixed steps of `dt`, and taps land on a step, so a tap log replays to the same
///   painting on the same device (`replay`); nothing in it reads a clock.
///
/// Only the wet part of the sheet is stepped (its box, `activeBox`), its rows on every core, each
/// cell written by one worker from the step before's values, so the result doesn't depend on the
/// core count. A sheet with nothing wet costs nothing.
public final class WatercolorSim {
    public static let dt: Float = 1 / 60
    /// Below this a cell is dry paper.
    static let wetLine: Float = 0.015
    /// How far past the pencil a wash creeps, in cells (unevenly: the lines aren't walls).
    static let reach: Float = 3
    /// Seconds a wash takes to dry at its middle.
    static let drySeconds: Float = 4

    public let sheet: WatercolorSheet
    public private(set) var step = 0
    public var time: Float { Float(step) * Self.dt }

    /// Water, settled and suspended pigment and the cell's wash properties (`count` each).
    public let W: UnsafeMutablePointer<Float>
    public let S: UnsafeMutablePointer<SIMD4<Float>>
    public let D: UnsafeMutablePointer<SIMD4<Float>>
    public let G: UnsafeMutablePointer<Float>
    let E: UnsafeMutablePointer<Float>
    let L: UnsafeMutablePointer<Float>
    // Scratch, one value per cell.
    private let soft: UnsafeMutablePointer<Float>
    private let fx: UnsafeMutablePointer<Float>
    private let fy: UnsafeMutablePointer<Float>
    private let px: UnsafeMutablePointer<SIMD4<Float>>
    private let py: UnsafeMutablePointer<SIMD4<Float>>
    private let wasWet: UnsafeMutablePointer<Bool>
    private let count: Int

    /// Each area painted (its paint laid at least once), what has been laid on it (the target
    /// solve's aim) and when it was first painted (its number fades then), `.infinity` until.
    public private(set) var laid: [Bool]
    public private(set) var laidDensity: [SIMD3<Float>]
    public private(set) var paintedAt: [Float]
    public private(set) var laidCount = 0

    private var floods: [Flood] = []
    /// The wet cells' box after the last step, `x0, y0, x1, y1`; nil when the sheet is dry.
    private var wetBox: Box?
    /// What changed since the drawing last asked (`takeChanges`).
    private var changedBox: Box?
    private var changedRegions = Set<Int32>()

    public struct Box: Equatable, Sendable {
        public var x0, y0, x1, y1: Int
        public init(x0: Int, y0: Int, x1: Int, y1: Int) {
            self.x0 = x0; self.y0 = y0; self.x1 = x1; self.y1 = y1
        }

        func union(_ o: Box?) -> Box {
            guard let o else { return self }
            return Box(x0: min(x0, o.x0), y0: min(y0, o.y0), x1: max(x1, o.x1), y1: max(y1, o.y1))
        }
    }

    private struct Flood {
        var cells: [Int32] = []
        var arrival: [Float] = []
        var water: [Float] = []
        var load: [Float] = []
        var soften: [Bool] = []
        var density = SIMD4<Float>(repeating: 0)
        var granulation: Float = 0
        var edge: [Float] = []
        var cursor = 0
        var box: Box
    }

    public init(sheet: WatercolorSheet) {
        self.sheet = sheet
        count = sheet.width * sheet.height
        let count = max(count, 1)
        W = Self.zeros(count); G = Self.zeros(count); E = Self.zeros(count); L = Self.zeros(count)
        soft = Self.zeros(count); fx = Self.zeros(count); fy = Self.zeros(count)
        S = Self.zeros(count); D = Self.zeros(count); px = Self.zeros(count); py = Self.zeros(count)
        wasWet = .allocate(capacity: count)
        wasWet.initialize(repeating: false, count: count)
        E.update(repeating: 1, count: count)
        laid = Array(repeating: false, count: sheet.regionCount)
        laidDensity = Array(repeating: .zero, count: sheet.regionCount)
        paintedAt = Array(repeating: .infinity, count: sheet.regionCount)
    }

    private static func zeros<T: SIMD>(_ n: Int) -> UnsafeMutablePointer<T> where T.Scalar == Float {
        let p = UnsafeMutablePointer<T>.allocate(capacity: n)
        p.initialize(repeating: .zero, count: n)
        return p
    }

    private static func zeros(_ n: Int) -> UnsafeMutablePointer<Float> {
        let p = UnsafeMutablePointer<Float>.allocate(capacity: n)
        p.initialize(repeating: 0, count: n)
        return p
    }

    deinit {
        for p in [W, G, E, L, soft, fx, fy] { p.deallocate() }
        for p in [S, D, px, py] { p.deallocate() }
        wasWet.deallocate()
    }

    /// Whether anything is wet or still arriving: the sheet needs stepping and drawing.
    public var isActive: Bool { wetBox != nil || !floods.isEmpty }

    // MARK: Taps

    /// A tap at `canvas` (canvas units) in `region`, now. `paint` lays the region's own paint;
    /// false is water alone (another paint's tap: never a mistake, a bloom). A region already
    /// laid takes water alone either way.
    public func tap(region r: Int, at canvas: SIMD2<Float>, paint: Bool) {
        guard r >= 0, r < sheet.regionCount else { return }
        let firstPaint = paint && !laid[r]
        let density = firstPaint ? sheet.want[r] : SIMD3<Float>(repeating: 0)
        if firstPaint {
            laid[r] = true
            laidCount += 1
            laidDensity[r] += density
            paintedAt[r] = time
            changedRegions.insert(Int32(r))
        }
        let b = sheet.bounds[r]
        guard b.x < b.z, b.y < b.w else { return }
        let w = sheet.width, h = sheet.height
        let pad: Int32 = 5
        let box = Box(x0: Int(max(b.x - pad, 0)), y0: Int(max(b.y - pad, 0)),
                      x1: Int(min(b.z + pad, Int32(w))), y1: Int(min(b.w + pad, Int32(h))))
        let bw = box.x1 - box.x0, bh = box.y1 - box.y0, n = bw * bh
        @inline(__always) func global(_ j: Int) -> Int { (box.y0 + j / bw) * w + box.x0 + j % bw }

        var own = [Bool](repeating: false, count: n)
        for j in 0..<n where sheet.labels[global(j)] == Int32(r) { own[j] = true }
        let out = Self.chamfer(seeds: own, width: bw, height: bh)
        var creep = [Bool](repeating: false, count: n)
        var dryPainted = [Bool](repeating: false, count: n)
        // A neighbour still wet: the wash runs on into it (wet-in-wet), further, feathering.
        var wetNear = [Bool](repeating: false, count: n)
        var reachHere = [Float](repeating: Self.reach, count: n)
        var anyWet = false
        // How dark this paint is: a dark wash bleeds into a lighter wet neighbour only a little.
        let ownDark = sheet.want[r].x + sheet.want[r].y + sheet.want[r].z
        var bleedLoad = [Float](repeating: 1, count: n)
        for j in 0..<n where !own[j] {
            let g = global(j)
            let lf = sheet.lowFrequency[g], p = sheet.paper[g]
            if W[g] > Self.wetLine {
                wetNear[j] = true
                anyWet = true
            }
            var further: Float = 1
            if wetNear[j] {
                // Into a wet neighbour as dark or darker, a little further; into a lighter one,
                // less pigment the lighter it is, so a dark paint never swallows a small light one.
                let o = sheet.want[Int(sheet.labels[g])]
                let ratio = min(max((o.x + o.y + o.z) / max(ownDark, 1e-3), 0.15), 1)
                further = 1 + 0.25 * ratio
                bleedLoad[j] = 0.6 * ratio
            }
            reachHere[j] = Self.reach * further * min(max(0.5 + 0.6 * lf + 0.5 * (p - 0.5), 0.15), 1.3)
            creep[j] = out[j] <= reachHere[j]
            let d = D[g]
            if d.x + d.y + d.z > 0.05 && W[g] < Self.wetLine {
                dryPainted[j] = true
            }
        }
        for j in 0..<n where dryPainted[j] { creep[j] = false }
        // The brush runs on into a dry wash of nearly the same paint, softening its rim.
        var soften = [Bool](repeating: false, count: n)
        var mask = [Bool](repeating: false, count: n)
        var ownCount = 0
        let kin = sheet.group[r]
        for j in 0..<n {
            if !own[j], !creep[j], out[j] <= 3.5, sheet.group[Int(sheet.labels[global(j)])] == kin { soften[j] = true }
            mask[j] = own[j] || creep[j] || soften[j]
            if own[j] { ownCount += 1 }
        }
        // Where the front starts: the finger, else the nearest cell of the area (or of the mask).
        let tx = Int((canvas.x * sheet.scale).rounded(.down)) - box.x0
        let ty = Int((canvas.y * sheet.scale).rounded(.down)) - box.y0
        var start = -1
        if tx >= 0, ty >= 0, tx < bw, ty < bh, mask[ty * bw + tx] { start = ty * bw + tx }
        if start < 0 {
            var best = Int.max
            for pass in 0..<2 where start < 0 {
                for j in 0..<n where pass == 0 ? own[j] : mask[j] {
                    let dx = j % bw - tx, dy = j / bw - ty
                    let d = dx * dx + dy * dy
                    if d < best { best = d; start = j }
                }
            }
        }
        guard start >= 0 else { return }

        // Rings of 8-neighbour steps from the touch, inside the mask.
        var dist = [Int32](repeating: -1, count: n)
        dist[start] = 0
        var ring = [start], next: [Int] = []
        var d: Int32 = 0
        while !ring.isEmpty {
            d += 1
            next.removeAll(keepingCapacity: true)
            for j in ring {
                let x = j % bw, y = j / bw
                for dy in -1...1 {
                    for dx in -1...1 where dx != 0 || dy != 0 {
                        let nx = x + dx, ny = y + dy
                        guard nx >= 0, ny >= 0, nx < bw, ny < bh else { continue }
                        let k = ny * bw + nx
                        if mask[k], dist[k] < 0 { dist[k] = d; next.append(k) }
                    }
                }
            }
            swap(&ring, &next)
        }
        for seed in 0..<n where own[seed] && dist[seed] < 0 {
            // Another piece of the area: its own front, starting where the last one ended.
            dist[seed] = d
            ring = [seed]
            while !ring.isEmpty {
                d += 1
                next.removeAll(keepingCapacity: true)
                for j in ring {
                    let x = j % bw, y = j / bw
                    for dy in -1...1 {
                        for dx in -1...1 where dx != 0 || dy != 0 {
                            let nx = x + dx, ny = y + dy
                            guard nx >= 0, ny >= 0, nx < bw, ny < bh else { continue }
                            let k = ny * bw + nx
                            if mask[k], dist[k] < 0 { dist[k] = d; next.append(k) }
                        }
                    }
                }
                swap(&ring, &next)
            }
        }
        let dmax = Float(max(d - 1, 1))

        var rng = SplitMix64(seed: sheet.seed ^ (UInt64(step) &* 0x9E37_79B9_7F4A_7C15) ^ (UInt64(r) &* 0xD1B5_4A32_D192_ED03))
        // How unevenly this wash goes on, and how hard it pulls to its rim: some puddled, some
        // barely, and a small area can't hold a puddle, so small shapes don't read as rings.
        let wobble = 0.08 + 0.37 * rng.nextFloat()
        let u = max(rng.nextFloat(), 1e-7), v = rng.nextFloat()
        let normal = (-2 * log(u)).squareRoot() * cos(2 * Float.pi * v)
        // How much water the brush carried: a wash laid wet pools and dries to a tide-line, one
        // laid damp dries flat. The tide-line's strength follows the water.
        let puddle = 0.7 + 0.75 * rng.nextFloat()
        let tide = min(max(0.05 + 1.5 * (puddle - 0.85) + 0.2 * normal, 0.04), 1.6)
        // A broad area (a sky, a background) is laid as a big wet wash: more water, so it stays
        // open for its neighbours to run into. A ring is an accent of a broad, light wash: a
        // small area or a dark paint dries with a faint edge, so a busy picture isn't a field of
        // ringed shapes.
        let side = sheet.workingArea[r].squareRoot()
        let broad = min(max((side - 60) / 120, 0), 1)
        let size = min(max((side - 25) / 110, 0.08), 1)
        let light = min(max(1.25 - 0.45 * ownDark, 0.12), 1)
        let accent = size * light
        let edge = tide * accent
        let carried = puddle * (1 + 0.5 * broad)
        // How each edge dries depends on what the wash meets there: still-wet paint feathers
        // into it (no rim, the two bleed), dry paper or a dried wash stops it crisp and a touch
        // darker (wet-on-dry). Distances from the dry cells past the wash and from the wet ones.
        var hardSeed = [Bool](repeating: false, count: n)
        for j in 0..<n where !mask[j] && !wetNear[j] { hardSeed[j] = true }
        let toHard = Self.chamfer(seeds: hardSeed, width: bw, height: bh)
        let toWet = anyWet ? Self.chamfer(seeds: wetNear, width: bw, height: bh) : nil
        if anyWet {
            // The neighbour's wash, wet where this one runs in, loses its rim there too.
            for j in 0..<n where wetNear[j] && out[j] <= 9 {
                let g = global(j)
                E[g] *= 0.25 + 0.75 * min(max((out[j] - 1) / 8, 0), 1)
            }
        }
        let duration = 0.25 + 0.45 * min(1, Float(ownCount).squareRoot() / 120)
        let when = time

        var flood = Flood(box: box)
        flood.density = SIMD4(density, 0)
        flood.granulation = WatercolorSheet.granulation(of: sheet.encoded[r])
        var order: [(Float, Int32, Float, Float, Bool, Float)] = []
        order.reserveCapacity(n)
        for j in 0..<n where dist[j] >= 0 {
            let g = global(j)
            let lf = sheet.lowFrequency[g], p = sheet.paper[g]
            let df = Float(dist[j])
            let jitter = lf * 0.07 + (p - 0.5) * 0.1
            let arrival = when + duration * pow(max(df / dmax + jitter, 0), 0.75)
            // The drop lands where you touched: more water there pushes the pigment out, so the
            // touch stays a lighter bloom with the color gathered where the front comes to rest.
            let drop = 1 + 0.9 * exp(-df / (0.18 * dmax + 2))
            // Past the pencil the wash thins in pigment, not in water: a thinner film there drew the
            // wash's water, and its pigment with it, out to the creep's edge, where it dried as a
            // dark ring round every shape.
            let taper = own[j] ? 1 : min(max(1 - out[j] / (reachHere[j] + 1), 0.2), 1)
            let spread = own[j] ? 1 : 0.85 + 0.15 * taper
            let water = carried * drop * spread * min(max(1 + wobble * sheet.waterNoise[g], 0.3), 2)
            let wetIn = toWet.map { exp(-$0[j] / 2.5) } ?? 0
            let crisp = exp(-max(toHard[j] - 1, 0) / 0.8) * (1 - wetIn)
            var load = soften[j] ? 0 : min(max(1 + 0.15 * sheet.pigmentNoise[g], 0.4), 1.8)
            load *= (own[j] ? 1 : 0.45 * taper) * (1 + 0.5 * accent * crisp)
            if creep[j], wetNear[j] { load *= bleedLoad[j] }
            // Over a neighbour's wash already dry (where it crept past the pencil), a thin glaze:
            // laid full, every such overlap read as a dark outline round every shape.
            let under = D[g]
            if own[j], under.x + under.y + under.z > 0.05, W[g] < Self.wetLine { load *= 0.2 }
            order.append((arrival, Int32(g), water, load, soften[j], edge * (1 - 0.75 * wetIn)))
        }
        order.sort { $0.0 != $1.0 ? $0.0 < $1.0 : $0.1 < $1.1 }
        flood.cells = order.map(\.1)
        flood.arrival = order.map(\.0)
        flood.water = order.map(\.2)
        flood.load = order.map(\.3)
        flood.soften = order.map(\.4)
        flood.edge = order.map(\.5)
        floods.append(flood)
    }

    /// Distance from each cell to the nearest seed, 8-neighbour chamfer (1, √2): close to
    /// Euclidean over the few cells a wash creeps.
    static func chamfer(seeds: [Bool], width w: Int, height h: Int) -> [Float] {
        let big: Float = 1e6, diag: Float = 1.4142135
        var d = seeds.map { $0 ? 0 : big }
        for y in 0..<h {
            for x in 0..<w {
                var v = d[y * w + x]
                if x > 0 { v = min(v, d[y * w + x - 1] + 1) }
                if y > 0 {
                    v = min(v, d[(y - 1) * w + x] + 1)
                    if x > 0 { v = min(v, d[(y - 1) * w + x - 1] + diag) }
                    if x + 1 < w { v = min(v, d[(y - 1) * w + x + 1] + diag) }
                }
                d[y * w + x] = v
            }
        }
        for y in stride(from: h - 1, through: 0, by: -1) {
            for x in stride(from: w - 1, through: 0, by: -1) {
                var v = d[y * w + x]
                if x + 1 < w { v = min(v, d[y * w + x + 1] + 1) }
                if y + 1 < h {
                    v = min(v, d[(y + 1) * w + x] + 1)
                    if x + 1 < w { v = min(v, d[(y + 1) * w + x + 1] + diag) }
                    if x > 0 { v = min(v, d[(y + 1) * w + x - 1] + diag) }
                }
                d[y * w + x] = v
            }
        }
        return d
    }

    // MARK: Stepping

    /// One step of `dt`: the water the taps' fronts reach, flow, pigment carried and settled,
    /// evaporation, and what dries.
    public func advance() {
        let w = sheet.width, h = sheet.height
        let t1 = Float(step + 1) * Self.dt
        var arrived: Box?
        var kept: [Flood] = []
        for var flood in floods {
            while flood.cursor < flood.cells.count, flood.arrival[flood.cursor] <= t1 {
                let c = flood.cursor
                let i = Int(flood.cells[c])
                let water = flood.water[c]
                W[i] += water
                S[i] += flood.density * (water * flood.load[c])
                G[i] = flood.granulation
                E[i] = flood.edge[c]
                L[i] = flood.soften[c] ? 1 : 0
                let x = i % w, y = i / w
                arrived = Box(x0: x, y0: y, x1: x + 1, y1: y + 1).union(arrived)
                flood.cursor += 1
            }
            if flood.cursor < flood.cells.count { kept.append(flood) }
        }
        floods = kept
        step += 1
        guard let active = arrived.map({ $0.union(wetBox) }) ?? wetBox else { return }
        let margin = 4
        let b = Box(x0: max(active.x0 - margin, 0), y0: max(active.y0 - margin, 0),
                    x1: min(active.x1 + margin, w), y1: min(active.y1 + margin, h))
        changedBox = b.union(changedBox)
        let dt = Self.dt
        let W = W, S = S, D = D, G = G, E = E, L = L, soft = soft, fx = fx, fy = fy, px = px, py = py, wasWet = wasWet
        let paper = sheet.paper, evapNoise = sheet.evaporationNoise
        let rows = b.y1 - b.y0

        // 1. What is wet, and a soft version of it: the patch's interior pushes toward its rim.
        Parallel.forEachBand(rows, minimumBandSize: 8) { band in
            for y in (band.lowerBound + b.y0)..<(band.upperBound + b.y0) {
                for x in b.x0..<b.x1 {
                    let i = y * w + x
                    let wet = W[i] > Self.wetLine
                    wasWet[i] = wet
                    soft[i] = wet ? 1 : 0
                }
            }
        }
        Self.blur(soft, width: w, box: b)

        // 2. Flux between wet neighbours (dry paper is a wall; two wet ones bleed together),
        // ragged where the paper's tooth makes some paths easier; pigment rides it, upwind, and
        // diffuses a little within wet paint.
        let kw: Float = 0.22, ks: Float = 0.06
        Parallel.forEachBand(rows, minimumBandSize: 8) { band in
            for y in (band.lowerBound + b.y0)..<(band.upperBound + b.y0) {
                for x in b.x0..<b.x1 {
                    let i = y * w + x
                    let pi = W[i] + 0.7 * E[i] * soft[i]
                    let conc = S[i] / max(W[i], 0.15)
                    if x + 1 < b.x1, wasWet[i], wasWet[i + 1] {
                        let j = i + 1
                        let pj = W[j] + 0.7 * E[j] * soft[j]
                        let f = min(max(kw * (pi - pj) * (0.45 + paper[j]), -0.24 * W[j]), 0.24 * W[i])
                        fx[i] = f
                        var p = (f > 0 ? conc : S[j] / max(W[j], 0.15)) * f + ks * (S[i] - S[j])
                        p = simd_clamp4(p, -0.24 * S[j], 0.24 * S[i])
                        px[i] = p
                    } else {
                        fx[i] = 0
                        px[i] = .zero
                    }
                    if y + 1 < b.y1, wasWet[i], wasWet[i + w] {
                        let j = i + w
                        let pj = W[j] + 0.7 * E[j] * soft[j]
                        let f = min(max(kw * (pi - pj) * (0.45 + paper[j]), -0.24 * W[j]), 0.24 * W[i])
                        fy[i] = f
                        var p = (f > 0 ? conc : S[j] / max(W[j], 0.15)) * f + ks * (S[i] - S[j])
                        p = simd_clamp4(p, -0.24 * S[j], 0.24 * S[i])
                        py[i] = p
                    } else {
                        fy[i] = 0
                        py[i] = .zero
                    }
                }
            }
        }

        // 3. Apply the flux; water on a dried wash lifts a little of it (a softened rim);
        // pigment settles, more in the paper's valleys; the rim evaporates first; what's left
        // of the water dries its pigment in place.
        let evaporation = 1 / Self.drySeconds
        let bands = Parallel.mapBands(rows, minimumBandSize: 8) { band -> Box? in
            var wetHere: Box?
            for y in (band.lowerBound + b.y0)..<(band.upperBound + b.y0) {
                for x in b.x0..<b.x1 {
                    let i = y * w + x
                    var water = W[i] - fx[i] - fy[i]
                    var s = S[i] - px[i] - py[i]
                    if x > b.x0 { water += fx[i - 1]; s += px[i - 1] }
                    if y > b.y0 { water += fy[i - w]; s += py[i - w] }
                    var d = D[i]
                    if L[i] > 0 {
                        // Gently: lifted fast, a dried wash's edge washed out to bare paper.
                        let lift = d * (dt * 0.15 * L[i] * min(max(water - 0.2, 0), 1))
                        d -= lift
                        s += lift
                    }
                    let rate = min(max(dt * 0.12 * (0.6 + G[i] * 1.5 * (1 - paper[i])), 0), 1)
                    let settle = s * rate
                    s -= settle
                    d += settle
                    if wasWet[i] {
                        let rim = min(max(1 - soft[i], 0), 1)
                        water -= dt * evaporation * (0.6 + 1.8 * rim * min(E[i], 1)) * min(max(1 + 0.45 * evapNoise[i], 0.3), 2)
                        if water <= Self.wetLine {
                            d += s
                            s = .zero
                            water = 0
                            L[i] = 0
                        }
                    }
                    W[i] = max(water, 0)
                    S[i] = s
                    D[i] = d
                    if W[i] > 0 { wetHere = Box(x0: x, y0: y, x1: x + 1, y1: y + 1).union(wetHere) }
                }
            }
            return wetHere
        }
        var wet: Box?
        for band in bands { if let band { wet = band.union(wet) } }
        wetBox = wet
    }

    private static func blur(_ a: UnsafeMutablePointer<Float>, width w: Int, box b: Box) {
        // Three boxes of radius 2: a Gaussian of about 2.5 cells, as the spike's.
        var line = [Float](repeating: 0, count: max(b.x1 - b.x0, b.y1 - b.y0))
        let r = 2, norm: Float = 1 / 5
        for _ in 0..<3 {
            let bw = b.x1 - b.x0, bh = b.y1 - b.y0
            for y in b.y0..<b.y1 {
                for i in 0..<bw { line[i] = a[y * w + b.x0 + i] }
                var sum: Float = 0
                for k in -r...r { sum += line[min(max(k, 0), bw - 1)] }
                for i in 0..<bw {
                    a[y * w + b.x0 + i] = sum * norm
                    sum += line[min(i + r + 1, bw - 1)] - line[max(i - r, 0)]
                }
            }
            for x in b.x0..<b.x1 {
                for i in 0..<bh { line[i] = a[(b.y0 + i) * w + x] }
                var sum: Float = 0
                for k in -r...r { sum += line[min(max(k, 0), bh - 1)] }
                for i in 0..<bh {
                    a[(b.y0 + i) * w + x] = sum * norm
                    sum += line[min(i + r + 1, bh - 1)] - line[max(i - r, 0)]
                }
            }
        }
    }

    /// Steps until nothing is wet (a painting opened, a replay's end), at most `limit` steps.
    public func finish(limit: Int = 60 * 120) {
        var n = 0
        while isActive, n < limit {
            advance()
            n += 1
        }
    }

    /// The painting a tap log makes: each tap at its step, the dry stretches between skipped
    /// (a sheet with nothing wet steps to itself), then dried. Taps out of order or of no area
    /// are left out.
    public func replay(_ log: WatercolorLog) {
        for tap in log.taps where tap.step >= step {
            while step < tap.step {
                if isActive { advance() } else { step = tap.step }
            }
            self.tap(region: tap.region, at: SIMD2(tap.x, tap.y), paint: tap.paint)
        }
        finish()
    }

    // MARK: Saving

    public enum SnapshotError: Error, Equatable {
        case damaged
        case newerVersion(UInt32)
        /// The snapshot is of another sheet (its size or its areas).
        case otherSheet
    }

    static let snapshotMagic: [UInt8] = Array("WCS1".utf8)
    static let snapshotVersion: UInt32 = 1

    /// The painting as it stands, dried where it lies (what is still in the water settles in
    /// place): opened again with `restore`, it shows at once, where replaying its log takes
    /// seconds. Little-endian: magic, version, width, height, areas, step; per area whether it is
    /// laid, what was laid and when; per cell the deposit and its granulation.
    public func snapshot() -> Data {
        var out = Data()
        out.reserveCapacity(24 + sheet.regionCount * 17 + count * 16)
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { out.append(contentsOf: $0) } }
        func f32(_ v: Float) { u32(v.bitPattern) }
        out.append(contentsOf: Self.snapshotMagic)
        u32(Self.snapshotVersion)
        u32(UInt32(sheet.width)); u32(UInt32(sheet.height)); u32(UInt32(sheet.regionCount)); u32(UInt32(clamping: step))
        for r in 0..<sheet.regionCount {
            out.append(laid[r] ? 1 : 0)
            f32(laidDensity[r].x); f32(laidDensity[r].y); f32(laidDensity[r].z)
            f32(paintedAt[r].isFinite ? paintedAt[r] : -1)
        }
        for i in 0..<count {
            let d = D[i] + S[i]
            f32(d.x); f32(d.y); f32(d.z); f32(G[i])
        }
        return out
    }

    /// The sheet as `snapshot` left it, nothing wet. Read as hostile input: every count is
    /// checked against the sheet and the bytes left, and a damaged snapshot changes nothing.
    public func restore(from data: Data) throws {
        let bytes = [UInt8](data)
        var at = 0
        func u32() throws -> UInt32 {
            guard at + 4 <= bytes.count else { throw SnapshotError.damaged }
            defer { at += 4 }
            return UInt32(bytes[at]) | UInt32(bytes[at + 1]) << 8 | UInt32(bytes[at + 2]) << 16 | UInt32(bytes[at + 3]) << 24
        }
        func f32() throws -> Float {
            let v = Float(bitPattern: try u32())
            guard v.isFinite else { throw SnapshotError.damaged }
            return v
        }
        guard bytes.count >= 8, Array(bytes[0..<4]) == Self.snapshotMagic else { throw SnapshotError.damaged }
        at = 4
        let version = try u32()
        guard version <= Self.snapshotVersion else { throw SnapshotError.newerVersion(version) }
        guard try u32() == UInt32(sheet.width), try u32() == UInt32(sheet.height), try u32() == UInt32(sheet.regionCount)
        else { throw SnapshotError.otherSheet }
        let savedStep = Int(try u32())
        guard bytes.count - at == sheet.regionCount * 17 + count * 16 else { throw SnapshotError.damaged }
        var laid = [Bool](repeating: false, count: sheet.regionCount)
        var laidDensity = [SIMD3<Float>](repeating: .zero, count: sheet.regionCount)
        var paintedAt = [Float](repeating: .infinity, count: sheet.regionCount)
        for r in 0..<sheet.regionCount {
            laid[r] = bytes[at] != 0
            at += 1
            laidDensity[r] = SIMD3(try f32(), try f32(), try f32())
            let t = try f32()
            paintedAt[r] = t < 0 ? .infinity : t
        }
        var deposit = [SIMD4<Float>](repeating: .zero, count: count)
        var granulation = [Float](repeating: 0, count: count)
        for i in 0..<count {
            deposit[i] = SIMD4(max(try f32(), 0), max(try f32(), 0), max(try f32(), 0), 0)
            granulation[i] = try f32()
        }
        self.laid = laid
        self.laidDensity = laidDensity
        self.paintedAt = paintedAt
        laidCount = laid.filter { $0 }.count
        step = savedStep
        floods = []
        wetBox = nil
        for i in 0..<count {
            D[i] = deposit[i]
            G[i] = granulation[i]
            W[i] = 0
            S[i] = .zero
            L[i] = 0
            E[i] = 1
        }
        changedBox = Box(x0: 0, y0: 0, x1: sheet.width, y1: sheet.height)
    }

    // MARK: Drawing

    /// What changed since the last call: the box of cells stepped and the regions whose target
    /// solve may have moved.
    public func takeChanges() -> (box: Box?, regions: [Int32]) {
        defer { changedBox = nil; changedRegions.removeAll(keepingCapacity: true) }
        if let b = changedBox {
            for (r, rb) in sheet.bounds.enumerated() where rb.x < rb.z
                && Int(rb.x) < b.x1 && Int(rb.z) > b.x0 && Int(rb.y) < b.y1 && Int(rb.w) > b.y0 {
                changedRegions.insert(Int32(r))
            }
        }
        return (changedBox, changedRegions.sorted())
    }

    /// The target solve of `region`: the gain on each channel that brings the mean pigment of its
    /// reached cells (settled plus most of what's still in the water) to what was laid there,
    /// within 0.7…1.4, so the picture reads however the water moved it; and the density its
    /// rims are capped toward (pigment piled at a rim darkens its own hue, never toward black).
    public func target(of region: Int) -> (gain: SIMD3<Float>, aim: SIMD3<Float>) {
        let aim = laid[region] ? laidDensity[region] : sheet.want[region]
        guard laid[region] else { return (SIMD3(repeating: 1), aim) }
        var sum = SIMD3<Float>(repeating: 0)
        var reached = 0
        for k in Int(sheet.regionStart[region])..<Int(sheet.regionStart[region + 1]) {
            let i = Int(sheet.regionCells[k])
            let d = D[i] + 0.9 * S[i]
            if d.x + d.y + d.z > 0.01 {
                sum += SIMD3(d.x, d.y, d.z)
                reached += 1
            }
        }
        guard reached > 0 else { return (SIMD3(repeating: 1), aim) }
        let mean = sum / Float(reached)
        var gain = SIMD3<Float>(repeating: 1)
        for c in 0..<3 where mean[c] > 1e-3 {
            gain[c] = min(max(aim[c] / mean[c], 0.7), 1.4)
        }
        return (gain, aim)
    }
}

@inline(__always)
private func simd_clamp4(_ v: SIMD4<Float>, _ lo: SIMD4<Float>, _ hi: SIMD4<Float>) -> SIMD4<Float> {
    // lo ≤ 0 ≤ hi always (pigment is never negative), so the order of min and max can't cross.
    v.replacing(with: lo, where: v .< lo).replacing(with: hi, where: v .> hi)
}
