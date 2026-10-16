import Foundation
import PaintCore

/// What `FieldShow` keeps of its build: when each step's change reaches each pixel, the lines' fuse
/// and the numbers' moments, from the six steps' fields (`FieldShow.init` of `making_of_fields.py`).
struct FieldBuild {
    var times: Compositor.Times
    /// The template's lines as the ink step burns them and the template step relaxes them, in the
    /// template's order: `start` and `duration` are the span of the fuse along the line, `relax` when
    /// the ripple reaches each point.
    var strokes: [StrokeSchedule.Stroke]
    /// When the fuse reaches each point of each line's stair-stepped outline.
    var fuses: [[Double]]
    /// When each number of the template starts to come out.
    var numberTimes: [Double]
    /// For each paint, when its last pixel has changed: the seed rings fade out after.
    var spread: [Double]
    var picks: Picks

    /// What chance decided, which a test can pin: the seeds each front is lit from, in the order they
    /// are lit, and which bits melt (the palette's areas that are not the largest of their merged
    /// region), at what rank in the order of melting.
    struct Picks: Sendable, Equatable {
        var sketch: [Geodesic.Seed]
        var shading: [Geodesic.Seed]
        var fuse: [Geodesic.Seed]
        var relax: [Geodesic.Seed]
        var bitPixels: Int
        var melting: [Int]
        var meltingRank: [Double]
    }

    /// - Parameters:
    ///   - survivors: the layers' (`ShowLayers.survivors`).
    ///   - seeds: step 3's k-means++ seeds (`PaintSeeds`), the same ones the crew's show drops.
    static func make(
        pictures: ShowPictures, survivors: Plane<Float>, template: ShowTemplate, spec: ShowSpec, seed: UInt64,
        seeds: [PaintSeed], paints: PaintColors, cancel: CancellationCheck
    ) throws -> FieldBuild {
        let plan = FieldPlan(pictures: pictures, spec: spec, seed: seed)
        let (pw, ph) = (plan.pw, plan.ph)
        let simplified = Labeling.regions(of: pictures.simplified)
        func perPixel(_ perRegion: [Double]) -> Plane<Float> {
            Plane(width: pw, height: ph, data: simplified.labels.data.map { Float(perRegion[Int($0)]) })
        }
        func floats(_ field: [Double]) -> Plane<Float> {
            Plane(width: pw, height: ph, data: field.map { Float($0) })
        }

        // the template's lines as the show draws them, to 0.01 px (the plan file's precision)
        let strokes = template.strokes.map { line in
            Polyline(line.points.map { Point(ExactMath.quantize($0.x, decimals: 2), ExactMath.quantize($0.y, decimals: 2)) })
        }
        try cancel.throwIfCancelled()

        let (sketch, lit) = plan.sketch(survivors: survivors)
        try cancel.throwIfCancelled()
        let (shading, drops) = plan.shading()
        try cancel.throwIfCancelled()
        let (paintsAt, spread) = plan.paints(seeds: seeds, paints: paints)
        try cancel.throwIfCancelled()
        let (merged, melting) = plan.merged(simplified: simplified, palette: Labeling.regions(of: pictures.palette))
        try cancel.throwIfCancelled()

        // the two fuses are lit from picks of one stream, in this order
        let burn = plan.burn(strokes: strokes)
        var fuseRng = plan.streams.field(4)
        let fuseSeeds = burn.picks(FieldShow.fuseSeeds, births: FieldShow.fuseBirths, from: &fuseRng)
        let relaxSeeds = burn.picks(FieldShow.relaxSeeds, births: FieldShow.relaxBirths, from: &fuseRng)

        // 5: fuses along the lines
        var fuse = burn.fuse(fuseSeeds)
        FieldMath.paced(
            &fuse, from: plan.start(4) + 0.05, to: plan.start(4) + plan.step - FieldShow.fuseEnd, over: burn.lines)
        let liftBy = plan.start(4) + plan.step - FieldShow.liftEnd
        let lift = Arrival.regionMinimum(
            Plane(width: pw, height: ph, data: fuse.map { min($0 + FieldShow.liftAfter, liftBy) }),
            labels: simplified.labels, count: simplified.count)
        try cancel.throwIfCancelled()

        // 6: a second fuse relaxes the outlines; the areas clear in drifts; the numbers come out
        var relax = burn.fuse(relaxSeeds)
        FieldMath.paced(
            &relax, from: plan.start(5) + 0.05, to: plan.start(5) + FieldShow.relaxSpan * plan.step, over: burn.lines)
        let clear = Arrival.regionMinimum(
            Plane(width: pw, height: ph, data: plan.clearing()), labels: simplified.labels, count: simplified.count)
        try cancel.throwIfCancelled()

        var lines: [StrokeSchedule.Stroke] = []
        var fuses: [[Double]] = []
        for (n, line) in strokes.enumerated() {
            let (jagged, smooth) = StrokeSchedule.staircase(line.points, grid: spec.outlines.grid)
            let cells = smooth.map {
                min(max(truncated($0.y), 0), ph - 1) * pw + min(max(truncated($0.x), 0), pw - 1)
            }
            let at = cells.map { fuse[$0] }
            let (first, last) = (at.min()!, at.max()!)
            fuses.append(at)
            lines.append(StrokeSchedule.Stroke(
                index: n, walked: false, start: first, duration: last - first, jagged: jagged, smooth: smooth,
                cumulative: Polyline(smooth).cumulative, relax: cells.map { relax[$0] }))
        }

        var rng = plan.streams.field(5)
        let numberTimes = template.numbers.map { number in
            let x = min(max(truncated(number.x), 0), pw - 1), y = min(max(truncated(number.y), 0), ph - 1)
            let clearAt = clear[Int(simplified.labels[x, y])]
            return min(
                clearAt + FieldShow.numberAfter + rng.uniform(0, FieldShow.numberSpread),
                plan.start(5) + plan.step - FieldShow.numberEnd)
        }

        return FieldBuild(
            times: Compositor.Times(
                sketch: floats(sketch), shading: floats(shading), paints: floats(paintsAt), merged: floats(merged),
                lift: perPixel(lift), clear: perPixel(clear)),
            strokes: lines, fuses: fuses, numberTimes: numberTimes, spread: spread,
            picks: Picks(
                sketch: lit, shading: drops, fuse: fuseSeeds, relax: relaxSeeds, bitPixels: melting.pixels,
                melting: melting.areas, meltingRank: melting.rank))
    }
}

/// The fields of the six steps: each is a time for every cell of a plane at 1 / `FieldShow.scale` of
/// the picture, grown back to its size and paced. Every function is a step of `FieldShow.__init__`
/// in `making_of_fields.py`, in its words.
struct FieldPlan {
    /// The picture's size, and the fields' (1 / `FieldShow.scale` of it).
    let pw: Int, ph: Int, w: Int, h: Int
    let timing: ScheduleTiming
    let streams: ShowStreams
    let noise: FieldNoise
    /// The noise's grain, which several steps rough up their speed with.
    let grain: [Double]
    let structure: Plane<UInt8>
    let size: (width: Int, height: Int)

    init(pictures: ShowPictures, spec: ShowSpec, seed: UInt64) {
        (pw, ph) = (pictures.width, pictures.height)
        (w, h) = (pw / FieldShow.scale, ph / FieldShow.scale)
        size = (pw, ph)
        timing = ScheduleTiming(spec)
        streams = ShowStreams(seed: seed)
        noise = FieldNoise(streams: streams)
        grain = noise.grain(width: w, height: h, scale: 6.0)
        structure = pictures.structure
    }

    func start(_ k: Int) -> Double { timing.start(k) }
    var step: Double { timing.step }

    /// `n` seeds of step `k` in a field, drawn by integer `weights` `spacing` cells apart, lit at
    /// the moments of a Poisson process squeezed into `from`...`to`, in a shuffled order (`born`).
    func born(step k: Int, weights: [Double], count n: Int, spacing: Double, from t0: Double, to t1: Double) -> [Geodesic.Seed] {
        var rng = streams.field(k)
        let spots = Sampling.sampleStops(weights: weights, width: w, count: n, spacing: spacing, rng: &rng)
        let gaps = (0...spots.count).map { _ in -log(1 - rng.nextDouble()) }
        let run = ExactMath.cumulative(gaps)
        let order = rng.permutation(spots.count)
        return order.enumerated().map { i, j in
            Geodesic.Seed(time: t0 + (t1 - t0) * run[i] / run[run.count - 1], x: Double(spots[j].x), y: Double(spots[j].y))
        }
    }

    /// A field grown to the picture's size.
    func grown(_ arrival: Plane<Double>) -> [Double] {
        FieldMath.grow(arrival, to: size)
    }

    // MARK: 1 sketch

    /// Graphite races along the structure like frost along cracks: fast along what survives relative
    /// total variation, slow across the flats.
    func sketch(survivors: Plane<Float>) -> (field: [Double], lit: [Geodesic.Seed]) {
        let kept = FieldMath.shrink(width: pw, height: ph) { Double(survivors.data[$0]) }
        let rough = noise.rough(width: w, height: h, scale: FieldShow.sketchRough.scale, strength: FieldShow.sketchRough.strength)
        let cost = (0..<w * h).map { i -> Double in
            let alive = min(max(kept.data[i], 0), 1)
            let along = FieldShow.sketchGain * pow(alive, FieldShow.sketchPower)
            let speed = (FieldShow.sketchFlat + along) * rough[i]
            return 1 / speed
        }
        let squares = FieldMath.shrink(width: pw, height: ph) { Double(Int(structure.data[$0]) * Int(structure.data[$0])) }
        let lit = born(
            step: 0, weights: squares.data.map { $0.rounded(.towardZero) }, count: FieldShow.sketchSeeds,
            spacing: FieldShow.sketchSpacing * Double(w), from: 0, to: FieldShow.sketchBirths)
        var field = grown(Geodesic.field(cost: Plane(width: w, height: h, data: cost), seeds: lit, sweeps: FieldShow.sweeps))
        FieldMath.paced(&field, from: start(0) + 0.05, to: start(0) + step - FieldShow.sketchEnd)
        return (field, lit)
    }

    // MARK: 2 shading

    /// Watercolor blooms open from drops born at random moments, slow to a stop at edges and seep
    /// past them.
    func shading() -> (field: [Double], drops: [Geodesic.Seed]) {
        var histogram = [Int](repeating: 0, count: 256)
        for v in structure.data { histogram[Int(v)] += 1 }
        let top = max(ExactMath.percentile(counts: histogram, percent: 98), 1)
        let edges = FieldMath.shrink(width: pw, height: ph) { Double(structure.data[$0]) }
        let rough = noise.rough(width: w, height: h, scale: FieldShow.bloomRough.scale, strength: FieldShow.bloomRough.strength)
        let cost = (0..<w * h).map { i -> Double in
            let edge = min(max(edges.data[i] / top, 0), 1)
            let swell = rough[i] * (0.6 + 0.8 * grain[i])
            let stop = 1 + FieldShow.bloomEdge * (edge * edge)
            return 1 / (swell / stop)
        }
        let drops = born(
            step: 1, weights: [Double](repeating: 1, count: w * h), count: FieldShow.bloomSeeds,
            spacing: FieldShow.bloomSpacing * Double(w), from: 0, to: FieldShow.bloomBirths)
        var field = grown(Geodesic.field(cost: Plane(width: w, height: h, data: cost), seeds: drops, sweeps: FieldShow.sweeps))
        FieldMath.paced(&field, from: start(1) + 0.05, to: start(1) + step - FieldShow.bloomEnd)
        return (field, drops)
    }

    // MARK: 3 paints

    /// The real k-means++ seeds drop, and each paint runs through its own areas like dye, jumping
    /// slowly between them. Also, for each paint, when its last pixel has changed.
    func paints(seeds: [PaintSeed], paints: PaintColors) -> (field: [Double], spread: [Double]) {
        let scale = FieldShow.scale
        var paintOf = [Int32](repeating: 0, count: w * h)
        for y in 0..<h {
            for x in 0..<w { paintOf[y * w + x] = paints.index[x * scale, y * scale] }
        }
        let rough = noise.rough(width: w, height: h, scale: FieldShow.dyeRough.scale, strength: FieldShow.dyeRough.strength)
        var everyone: [Geodesic.Seed] = []
        var jobs: [(paint: Int32, seeds: [Geodesic.Seed])] = []
        for p in 0..<paints.keys.count {
            let mine = seeds.filter { $0.paint == p }.map {
                Geodesic.Seed(time: $0.time * FieldShow.dyeBirth, x: $0.x / Double(scale), y: $0.y / Double(scale))
            }
            if !mine.isEmpty {
                everyone += mine
                jobs.append((Int32(p), mine))
            }
        }
        // each paint's own areas take their time from its own run of the front: no two runs touch the same cell
        var flow = [Double](repeating: .infinity, count: w * h)
        flow.withUnsafeMutableBufferPointer { flow in
            let out = UncheckedSendable(flow.baseAddress!)
            Parallel.forEachChunk(jobs.count, chunk: 1) { jobsHere in
                for j in jobsHere {
                    let (paint, mine) = jobs[j]
                    let cost = (0..<w * h).map { (paintOf[$0] == paint ? 1.0 : FieldShow.dyeOutside) / rough[$0] }
                    let arrival = Geodesic.field(cost: Plane(width: w, height: h, data: cost), seeds: mine, sweeps: 2)
                    for i in 0..<w * h where paintOf[i] == paint { out.value[i] = arrival.data[i] }
                }
            }
        }
        if flow.contains(.infinity) {
            let arrival = Geodesic.field(
                cost: Plane(width: w, height: h, data: rough.map { 1 / $0 }), seeds: everyone, sweeps: FieldShow.sweeps)
            for i in flow.indices where flow[i] == .infinity { flow[i] = arrival.data[i] + FieldShow.dyeUnseeded }
        }
        var field = grown(Plane(width: w, height: h, data: flow))
        FieldMath.paced(&field, from: start(2) + FieldShow.dyeStart, to: start(2) + step - FieldShow.dyeEnd)
        var spread = [Double](repeating: -.infinity, count: paints.keys.count)
        for (paint, time) in zip(paints.index.data, field) { spread[Int(paint)] = max(spread[Int(paint)], time) }
        return (field, spread)
    }

    // MARK: 4 merged

    /// The tiny bits melt into their neighbors from the outside in, smallest first. A bit is an
    /// area of one paint (`palette`) that isn't the largest of the merged region (`simplified`) it
    /// ended up in; the rest of the picture drifts.
    func merged(simplified: RegionLabels, palette: RegionLabels)
        -> (field: [Double], melting: (pixels: Int, areas: [Int], rank: [Double]))
    {
        let bitCount = palette.count
        // per merged region, the palette area that covers most of it (the lower number if two do)
        var overlap: [Int: Int] = [:]
        var run = 0, previous = -1
        for i in 0..<pw * ph {
            let pair = Int(simplified.labels.data[i]) * bitCount + Int(palette.labels.data[i])
            if pair == previous {
                run += 1
            } else {
                if run > 0 { overlap[previous, default: 0] += run }
                (previous, run) = (pair, 1)
            }
        }
        if run > 0 { overlap[previous, default: 0] += run }
        var largest = [(area: Int, pixels: Int)](repeating: (-1, 0), count: simplified.count)
        for (pair, pixels) in overlap {
            let (region, area) = pair.quotientAndRemainder(dividingBy: bitCount)
            if pixels > largest[region].pixels || (pixels == largest[region].pixels && area < largest[region].area) {
                largest[region] = (area, pixels)
            }
        }
        let bits = (0..<pw * ph).map { Int(palette.labels.data[$0]) != largest[Int(simplified.labels.data[$0])].area }
        var sizes = [Double](repeating: 0, count: bitCount)
        var isBit = [Bool](repeating: false, count: bitCount)
        for i in 0..<pw * ph {
            sizes[Int(palette.labels.data[i])] += 1
            if bits[i] { isBit[Int(palette.labels.data[i])] = true }
        }
        let melting = (0..<bitCount).filter { isBit[$0] }

        // the order they melt in: by size, shuffled by chance a share of the mean size
        var rng = streams.field(3)
        let typical = melting.isEmpty ? 0 : melting.reduce(0.0) { $0 + sizes[$1] } / Double(melting.count)
        let shuffled = melting.map { sizes[$0] + rng.nextDouble() * typical * FieldShow.meltJitter }
        let byTurn = melting.indices.sorted { shuffled[$0] != shuffled[$1] ? shuffled[$0] < shuffled[$1] : $0 < $1 }
        var rank = [Double](repeating: 0, count: bitCount)
        for (turn, j) in byTurn.enumerated() { rank[melting[j]] = Double(turn) / Double(max(melting.count - 1, 1)) }

        let coarseBits = FieldMath.shrink(width: pw, height: ph) { bits[$0] ? 1 : 0 }
        let inside = Plane(width: w, height: h, data: coarseBits.data.map { $0 > 0.5 ? Double.infinity : 0 })
        let inward = grown(Geodesic.field(
            cost: Plane(width: w, height: h, repeating: 1), start: inside, sweeps: 2))
        let after = start(3) + 0.1
        let melt = (0..<pw * ph).map { i -> Double in
            let early = after + rank[Int(palette.labels.data[i])] * FieldShow.meltSpan * step
            return early + min(inward[i], FieldShow.meltReach) * FieldShow.meltRate
        }
        var drift = grown(Plane(
            width: w, height: h,
            data: noise.warped(width: w, height: h, scale: FieldShow.meltDrift.scale, strength: 4.0)))
        FieldMath.paced(
            &drift, from: start(3) + FieldShow.meltDrift.from * step, to: start(3) + FieldShow.meltDrift.to * step)
        let latest = start(3) + step - FieldShow.meltEnd
        let field = (0..<pw * ph).map { min(bits[$0] ? melt[$0] : drift[$0], latest) }
        return (field, (bits.filter { $0 }.count, melting, melting.map { rank[$0] }))
    }

    // MARK: 5 ink, 6 template

    /// The drawing's pixels, where the fuses burn.
    struct Burn {
        let plan: FieldPlan
        /// The cost of a step for a front: cheap on a line, dear off it, with the grain's variation.
        let cost: Plane<Double>
        /// The cells (of the field) a line runs through.
        let cells: [Int]
        /// The pixels (of the picture) a line runs through: the cells the pacing ranks.
        let lines: [Bool]

        /// `n` seeds on the lines, lit at moments up to `births` (px of the field) apart.
        func picks(_ n: Int, births: Double, from rng: inout SplitMix64) -> [Geodesic.Seed] {
            guard !cells.isEmpty else { return [] }
            let picked = (0..<n).map { _ in cells[rng.below(cells.count)] }
            return picked.map {
                Geodesic.Seed(time: rng.uniform(0, births), x: Double($0 % plan.w), y: Double($0 / plan.w))
            }
        }

        /// When a front from `seeds` reaches each pixel of the picture, along the lines (unpaced).
        func fuse(_ seeds: [Geodesic.Seed]) -> [Double] {
            plan.grown(Geodesic.field(cost: cost, seeds: seeds, sweeps: FieldShow.sweeps))
        }
    }

    func burn(strokes: [Polyline]) -> Burn {
        let scale = Double(FieldShow.scale)
        let coarse = LineMask(
            width: w, height: h, strokes: strokes.map { Polyline($0.points.map { Point($0.x / scale, $0.y / scale) }) },
            halfWidth: 1.0)
        let cost = (0..<w * h).map { (coarse.plane.data[$0] != 0 ? 1.0 : FieldShow.fuseOffLine) * (0.75 + 0.5 * grain[$0]) }
        let full = LineMask(width: pw, height: ph, strokes: strokes, halfWidth: 1.0)
        return Burn(
            plan: self, cost: Plane(width: w, height: h, data: cost),
            cells: coarse.plane.data.indices.filter { coarse.plane.data[$0] != 0 }, lines: full.plane.data.map { $0 != 0 })
    }

    /// When each pixel's area clears: in drifts.
    func clearing() -> [Double] {
        var drift = grown(Plane(
            width: w, height: h,
            data: noise.warped(width: w, height: h, scale: FieldShow.clearDrift.scale, strength: 4.0)))
        FieldMath.paced(
            &drift, from: start(5) + FieldShow.clearDrift.from * step, to: start(5) + FieldShow.clearDrift.to * step)
        return drift
    }
}
