import Foundation

/// Watercolor's Making Of as a study sheet (painting-company row 373): before a painting, a
/// watercolorist tries their paints on a scrap of the same paper. The Making Of shows that, not
/// the painting: the painter's picture is theirs to find as they paint it, so the film shows off
/// what the water does with the painting's own paints and never what the painting will be.
///
/// The sheet is the painting's size, so it lies where the painting will, and holds, ruled in
/// pencil and numbered with the painting's own numbers:
/// - a chart of the painting's paints (up to `chartPaints` of them, chosen for their area and
///   how far apart they lie), each a square laid from one corner, so a flood runs across it and
///   dries with a crisp rim on the dry paper around it (wet on dry);
/// - a band of three of its boldest paints side by side, laid one into the next while wet, so
///   they bleed where they meet (wet in wet);
/// - a long stripe of its most granulating paint, flooded from one end to the other, settling
///   into the paper's tooth;
/// - two discs, laid and then charged with a drop of clean water as they go damp, so their
///   pigment is pushed out into a cauliflower edge (blooms), and one more drop into the first
///   square of the chart.
///
/// The paper around them is one area with no number, never painted. Deterministic: the same
/// painting gives the same study.
public struct WatercolorStudy: Sendable {
    /// The study sheet as a template: the painting's palette (so each square carries the
    /// painting's own number) and the paper's white after it.
    public let template: Template
    /// The paper's area: no number, never laid.
    public let paper: Int
    /// The chart's squares, in the order they are laid.
    public let chart: [Int]
    /// The wet-in-wet band's pieces, left to right, light to dark.
    public let band: [Int]
    /// The granulation stripe.
    public let stripe: Int?
    /// The bloom discs.
    public let discs: [Int]
    /// Their radius, canvas units.
    public let discRadius: Float

    public static let chartPaints = 6

    /// The study of `painting`, laid out at its size; it throws only if the vectorizer does.
    public init(painting p: Template) throws {
        let w = max(p.width, 8), h = max(p.height, 8)
        let paints = Self.choosePaints(p)
        let lab = p.palette.map(\.oklab)
        func chroma(_ c: Int) -> Float { (lab[c].y * lab[c].y + lab[c].z * lab[c].z).squareRoot() }

        // The roles: the chart in the painting's order; the band's three boldest, light to dark;
        // the stripe the most granulating; the discs a middle value and the next boldest.
        let chartPaints = paints.sorted()
        let boldest = paints.sorted { chroma($0) != chroma($1) ? chroma($0) > chroma($1) : $0 < $1 }
        let bandPaints = Array(boldest.prefix(3)).sorted { lab[$0].x != lab[$1].x ? lab[$0].x > lab[$1].x : $0 < $1 }
        let grains = Self.granulating(p).map { [$0] } ?? []
        // Blooms show best in a saturated wash: the boldest paints the band leaves, or the
        // band's own where those are greys.
        let colorful = boldest.filter { !bandPaints.contains($0) && Self.chroma(lab[$0]) >= 0.05 }
        let discPaints = Array((colorful + bandPaints.reversed()).prefix(2))

        // The layout, in the sheet's pixels: rows inside a margin.
        let side = Float(min(w, h))
        let margin = 0.07 * side
        let gap = 0.045 * side
        let inner = (x0: margin, y0: margin, x1: Float(w) - margin, y1: Float(h) - margin)
        let innerW = inner.x1 - inner.x0, innerH = inner.y1 - inner.y0
        let portrait = Float(w) < 0.85 * Float(h)
        // The chart: one row, or two on a tall sheet; then the band; then stripe and discs.
        let chartRows = portrait && chartPaints.count > 3 ? 2 : 1
        let perRow = max(1, Int((Float(chartPaints.count) / Float(chartRows)).rounded(.up)))
        let shares: [Float] = portrait ? [0.34, 0.26, 0.40] : [0.26, 0.30, 0.44]
        let rowsH = innerH - 2 * gap
        let chartH = rowsH * shares[0], bandH = rowsH * shares[1], lastH = rowsH * shares[2]
        let chartY = inner.y0, bandY = chartY + chartH + gap, lastY = bandY + bandH + gap

        var shapes: [Shape] = []
        var colors: [UInt32] = []
        var chart: [Int] = [], band: [Int] = [], discs: [Int] = []
        var stripe: Int?
        var discRadius: Float = 0
        var rng = SplitMix64(seed: 0x57D7 ^ UInt64(w) &* 31 ^ UInt64(h))
        func wobble() -> Wobble {
            Wobble(phases: (0..<4).map { _ in rng.nextFloat() * 2 * .pi })
        }
        // The chart's squares, even in size, centred in their cells.
        let cellW = (innerW - gap * Float(perRow - 1)) / Float(perRow)
        let cellH = (chartH - gap * Float(chartRows - 1)) / Float(chartRows)
        let square = min(cellW, cellH)
        for (i, c) in chartPaints.enumerated() {
            let row = i / perRow, col = i % perRow
            let inRow = min(perRow, chartPaints.count - row * perRow)
            let rowW = Float(inRow) * square + Float(inRow - 1) * gap
            let x0 = inner.x0 + (innerW - rowW) / 2 + Float(col) * (square + gap)
            let y0 = chartY + Float(row) * (cellH + gap) + (cellH - square) / 2
            chart.append(shapes.count + 1)
            shapes.append(.box(x0: x0, y0: y0, x1: x0 + square, y1: y0 + square, wobble: wobble()))
            colors.append(UInt32(c))
        }
        // The band: one strip of paper's width, cut in three by wavering lines.
        if !bandPaints.isEmpty {
            let n = bandPaints.count
            var cuts: [Float] = [inner.x0]
            for k in 1..<n { cuts.append(inner.x0 + innerW * Float(k) / Float(n)) }
            cuts.append(inner.x1)
            let waver = wobble()
            for k in 0..<n {
                band.append(shapes.count + 1)
                shapes.append(.piece(x0: inner.x0, y0: bandY, x1: inner.x1, y1: bandY + bandH, left: cuts[k], right: cuts[k + 1],
                                     first: k == 0, last: k == n - 1, waver: waver, wobble: wobble()))
                colors.append(UInt32(bandPaints[k]))
            }
        }
        // The last row: the stripe, and the discs beside it (under it on a tall sheet).
        if portrait {
            let stripeH = lastH * 0.32
            if let g = grains.first {
                stripe = shapes.count + 1
                shapes.append(.box(x0: inner.x0, y0: lastY, x1: inner.x1, y1: lastY + stripeH, wobble: wobble()))
                colors.append(UInt32(g))
            }
            let discTop = lastY + stripeH + gap, discH = lastH - stripeH - gap
            let r = min(discH / 2, (innerW - gap) / 4)
            discRadius = r
            for (k, c) in discPaints.enumerated() {
                let cx = inner.x0 + innerW * (k == 0 ? 0.27 : 0.73)
                discs.append(shapes.count + 1)
                shapes.append(.disc(cx: cx, cy: discTop + discH / 2, r: r, wobble: wobble()))
                colors.append(UInt32(c))
            }
        } else {
            let stripeW = innerW * 0.48
            if let g = grains.first {
                stripe = shapes.count + 1
                let sh = lastH * 0.55
                shapes.append(.box(x0: inner.x0, y0: lastY + (lastH - sh) / 2, x1: inner.x0 + stripeW, y1: lastY + (lastH + sh) / 2,
                                   wobble: wobble()))
                colors.append(UInt32(g))
            }
            let left = inner.x0 + stripeW + gap
            let room = inner.x1 - left
            let r = min(lastH / 2, (room - gap) / 4)
            discRadius = r
            for (k, c) in discPaints.enumerated() {
                let cx = left + room * (k == 0 ? 0.25 : 0.75)
                discs.append(shapes.count + 1)
                shapes.append(.disc(cx: cx, cy: lastY + lastH / 2, r: r, wobble: wobble()))
                colors.append(UInt32(c))
            }
        }

        // The label map: the paper is 0, each shape its own area.
        var map = [UInt32](repeating: 0, count: w * h)
        let boxes = shapes.map(\.reach)
        for y in 0..<h {
            for x in 0..<w {
                let q = SIMD2(Float(x) + 0.5, Float(y) + 0.5)
                for (k, s) in shapes.enumerated() where boxes[k].contains(q) && s.contains(q) {
                    map[y * w + x] = UInt32(k + 1)
                    break
                }
            }
        }
        let paperColor = UInt32(p.palette.count)
        var palette = p.palette
        palette.append(PaletteColor(oklab: SIMD3(1, 0, 0), space: p.colorSpace))
        let segmentation = Segmentation(labels: RegionMap(width: w, height: h, storage: map),
                                        regionColor: [paperColor] + colors, palette: palette, colorSpace: p.colorSpace)
        var t = try Vectorizer.vectorize(segmentation, settings: GenerationSettings(), cancel: .none, clock: StageClock())
        // The paper carries no number: its labels leave, the others' kept in order.
        let paper = t.regions.firstIndex { $0.colorIndex == paperColor } ?? 0
        var labels: [Label] = []
        for r in t.regions.indices {
            let start = labels.count
            if r != paper {
                let reg = t.regions[r]
                labels += t.labels[Int(reg.labelStart)..<Int(reg.labelStart + reg.labelCount)]
            }
            t.regions[r].labelStart = UInt32(start)
            t.regions[r].labelCount = UInt32(labels.count - start)
        }
        t.labels = labels
        template = t
        self.paper = paper
        // The vectorizer keeps the segmentation's region order; map the shapes by their paint
        // and place all the same, in case it doesn't.
        func region(of shape: Int) -> Int? {
            let s = shapes[shape - 1].anchor
            return t.region(at: s)
        }
        self.chart = chart.compactMap(region)
        self.band = band.compactMap(region)
        self.stripe = stripe.flatMap(region)
        self.discs = discs.compactMap(region)
        self.discRadius = discRadius
    }

    /// The paints the chart tries: the painting's, greedily the one with most area and then
    /// each next the farthest in OKLab from those chosen, weighed by its area, so the chart shows
    /// the painting's range and not its six near-greys.
    static func choosePaints(_ p: Template) -> [Int] {
        let share = shares(p)
        // A paint as pale as the paper shows nothing on it; and color shows the water best.
        var left = share.indices.filter { share[$0] > 0 && !isPaperLike(p.palette[$0].oklab) }
        if left.isEmpty { left = share.indices.filter { share[$0] > 0 } }
        func color(_ c: Int) -> Float { 0.3 + min(chroma(p.palette[c].oklab) / 0.12, 1) }
        func first(_ c: Int) -> Float { share[c].squareRoot() * color(c) }
        guard let start = left.max(by: { first($0) != first($1) ? first($0) < first($1) : $0 > $1 }) else { return [] }
        var chosen = [start]
        left.removeAll { $0 == start }
        while chosen.count < chartPaints, !left.isEmpty {
            func score(_ c: Int) -> Float {
                let near = chosen.map { ColorScience.distance(p.palette[$0].oklab, p.palette[c].oklab) }.min() ?? 0
                return near * share[c].squareRoot() * color(c)
            }
            let next = left.max { score($0) != score($1) ? score($0) < score($1) : $0 > $1 }!
            chosen.append(next)
            left.removeAll { $0 == next }
        }
        return chosen
    }

    /// Each paint's share of the painting's area.
    static func shares(_ p: Template) -> [Float] {
        var area = [Float](repeating: 0, count: p.palette.count)
        for r in p.regions where Int(r.colorIndex) < area.count { area[Int(r.colorIndex)] += r.area }
        let total = max(area.reduce(0, +), 1)
        return area.map { $0 / total }
    }

    static func chroma(_ lab: SIMD3<Float>) -> Float { (lab.y * lab.y + lab.z * lab.z).squareRoot() }

    static func isPaperLike(_ lab: SIMD3<Float>) -> Bool { lab.x > 0.84 && chroma(lab) < 0.045 }

    /// The paint the stripe shows granulating: of the painting's paints covering at least a
    /// hundredth of it, the one that settles most into the paper (blues and earths), whether or
    /// not the chart has it.
    static func granulating(_ p: Template) -> Int? {
        let share = shares(p)
        func grain(_ c: Int) -> Float { WatercolorSheet.granulation(of: p.palette[c].rgb) }
        return share.indices.filter { share[$0] >= 0.01 && !isPaperLike(p.palette[$0].oklab) }
            .max { grain($0) != grain($1) ? grain($0) < grain($1) : $0 > $1 }
    }

    /// The taps of the study, in step order (`WatercolorMakingOf(study:sheet:)`).
    func taps() -> (taps: [WatercolorLog.Tap], focus: SIMD2<Float>?) {
        let t = template
        let dt = WatercolorSim.dt
        func step(_ s: Float) -> Int { Int((s / dt).rounded()) }
        func box(_ r: Int) -> (min: SIMD2<Float>, max: SIMD2<Float>) {
            let b = t.regions[r].bounds
            return (SIMD2(Float(b.minX), Float(b.minY)), SIMD2(Float(b.maxX), Float(b.maxY)))
        }
        func inside(_ r: Int, _ f: SIMD2<Float>) -> SIMD2<Float> {
            let b = box(r)
            let q = b.min + (b.max - b.min) * f
            if t.region(at: q) == r { return q }
            return t.labels.first { Int($0.region) == r }?.position ?? (b.min + b.max) / 2
        }
        var taps: [WatercolorLog.Tap] = []
        func lay(_ r: Int, at seconds: Float, from f: SIMD2<Float>, paint: Bool = true) {
            let q = inside(r, f)
            taps.append(.init(step: step(seconds), region: r, x: q.x, y: q.y, paint: paint))
        }
        // The chart, square after square, each flooded from its top left corner.
        for (i, r) in chart.enumerated() { lay(r, at: Self.chartStart + Self.chartBeat * Float(i), from: SIMD2(0.2, 0.2)) }
        // The band, each laid against the one before while it is still wet.
        for (i, r) in band.enumerated() { lay(r, at: Self.bandStart + Self.bandBeat * Float(i), from: SIMD2(0.5, 0.35)) }
        // The stripe, from its left end.
        if let stripe { lay(stripe, at: Self.stripeStart, from: SIMD2(0.06, 0.5)) }
        // The discs, then a drop of water into each as it goes damp, off its middle.
        var focus: SIMD2<Float>?
        for (i, r) in discs.enumerated() {
            lay(r, at: Self.discStart + Self.bandBeat * Float(i), from: SIMD2(0.5, 0.5))
            let drop = inside(r, i == 0 ? SIMD2(0.38, 0.36) : SIMD2(0.62, 0.6))
            if focus == nil { focus = drop }
            taps.append(.init(step: step(Self.bloomStart + Self.bandBeat * Float(i)), region: r, x: drop.x, y: drop.y, paint: false))
        }
        if let first = chart.first { lay(first, at: Self.bloomStart - 0.3, from: SIMD2(0.62, 0.62), paint: false) }
        taps.sort { $0.step != $1.step ? $0.step < $1.step : ($0.paint != $1.paint ? $0.paint : $0.region < $1.region) }
        return (taps, focus)
    }

    /// When each passage begins, simulation seconds, and the beats between its washes.
    static let chartStart: Float = 0
    static let chartBeat: Float = 0.22
    static let bandStart: Float = 1.3
    static let bandBeat: Float = 0.2
    static let stripeStart: Float = 1.9
    static let discStart: Float = 2.2
    /// A drop's reach, a share of a disc's radius, and its water.
    static let dropShare: Float = 0.45
    static let dropWater: Float = 2
    static let bloomStart: Float = 3.3

    /// A shape of the study, in the sheet's pixels, its edges a little uneven, as a brush leaves
    /// them inside a ruled line.
    enum Shape {
        case box(x0: Float, y0: Float, x1: Float, y1: Float, wobble: Wobble)
        case piece(x0: Float, y0: Float, x1: Float, y1: Float, left: Float, right: Float, first: Bool, last: Bool,
                   waver: Wobble, wobble: Wobble)
        case disc(cx: Float, cy: Float, r: Float, wobble: Wobble)

        func contains(_ q: SIMD2<Float>) -> Bool {
            switch self {
            case let .box(x0, y0, x1, y1, wb):
                let a = min(x1 - x0, y1 - y0) * 0.025
                return q.x >= x0 + a * wb.at(q.y / 37) && q.x < x1 - a * wb.at(q.y / 41 + 2)
                    && q.y >= y0 + a * wb.at(q.x / 43 + 4) && q.y < y1 - a * wb.at(q.x / 39 + 6)
            case let .piece(x0, y0, x1, y1, l, r, first, last, waver, wb):
                let a = min(x1 - x0, y1 - y0) * 0.025
                guard q.y >= y0 + a * wb.at(q.x / 43) && q.y < y1 - a * wb.at(q.x / 39 + 2) else { return false }
                let bend = (y1 - y0) * 0.18
                let lo = first ? x0 + a * wb.at(q.y / 37 + 4) : l + bend * waver.at(q.y / (y1 - y0) * 5 + l * 0.01)
                let hi = last ? x1 - a * wb.at(q.y / 41 + 6) : r + bend * waver.at(q.y / (y1 - y0) * 5 + r * 0.01)
                return q.x >= lo && q.x < hi
            case let .disc(cx, cy, r, wb):
                let d = q - SIMD2(cx, cy)
                let angle = atan2(d.y, d.x)
                let edge = r * (1 + 0.035 * wb.at(angle * 3) + 0.02 * wb.at(angle * 5 + 1))
                return (d * d).sum() < edge * edge
            }
        }

        /// A box the shape never leaves, its wavering included: the label map tests only the
        /// shapes whose box holds a pixel.
        var reach: (min: SIMD2<Float>, max: SIMD2<Float>, contains: (SIMD2<Float>) -> Bool) {
            let lo: SIMD2<Float>, hi: SIMD2<Float>
            switch self {
            case let .box(x0, y0, x1, y1, _):
                let a = min(x1 - x0, y1 - y0) * 0.025
                lo = SIMD2(x0 - a, y0 - a); hi = SIMD2(x1 + a, y1 + a)
            case let .piece(x0, y0, x1, y1, l, r, _, _, _, _):
                let a = min(x1 - x0, y1 - y0) * 0.025, bend = (y1 - y0) * 0.18
                lo = SIMD2(min(x0, l - bend) - a, y0 - a); hi = SIMD2(max(x1, r + bend) + a, y1 + a)
            case let .disc(cx, cy, r, _):
                let e = r * 1.06
                lo = SIMD2(cx - e, cy - e); hi = SIMD2(cx + e, cy + e)
            }
            return (lo, hi, { q in q.x >= lo.x && q.y >= lo.y && q.x <= hi.x && q.y <= hi.y })
        }

        /// A point well inside the shape.
        var anchor: SIMD2<Float> {
            switch self {
            case let .box(x0, y0, x1, y1, _): return SIMD2((x0 + x1) / 2, (y0 + y1) / 2)
            case let .piece(_, y0, _, y1, l, r, _, _, _, _): return SIMD2((l + r) / 2, (y0 + y1) / 2)
            case let .disc(cx, cy, _, _): return SIMD2(cx, cy)
            }
        }
    }

    /// A smooth wavering, -1…1, of seeded sines.
    struct Wobble {
        var phases: [Float]
        func at(_ s: Float) -> Float {
            0.5 * sin(s + phases[0]) + 0.3 * sin(2.3 * s + phases[1]) + 0.2 * sin(4.1 * s + phases[2])
        }
    }
}

extension WatercolorMakingOf {
    /// The Making Of of a study sheet (`WatercolorStudy`): its taps, on the clock every Making Of
    /// keeps.
    public init(study: WatercolorStudy, sheet: WatercolorSheet) {
        let (taps, focus) = study.taps()
        let radius = study.discRadius * sheet.scale * WatercolorStudy.dropShare
        self.init(log: WatercolorLog(seed: sheet.seed, taps: taps), focus: focus, signatures: study.chart,
                  drops: (radius, WatercolorStudy.dropWater))
    }
}
