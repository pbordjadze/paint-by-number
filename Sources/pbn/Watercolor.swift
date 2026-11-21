import Foundation
import PaintCore

/// `pbn watercolor`: a Watercolor painting (painting-company row 373) off the device, to judge
/// the simulation's look and time its steps. A painter taps every area of the template once, paint
/// by paint (each paint's areas top left first, `--spacing` seconds apart, at each area's label;
/// `--order sweep` every area from the top left down whatever its paint),
/// and the sheet is drawn as the app's shader draws it (`WatercolorRenderer.metal`, mirrored here
/// on the CPU: the target solve, Beer–Lambert over the paper's color, granulation in the paper's
/// fine valleys, the paper lit from the top left, pencil fading under paint; no sheen or numbers).
///
///   pbn watercolor <photo | template.pbnt> --out <dir> [--seed N] [--spacing S] [--order paint|sweep]
///       [--frames t1,t2,…]
///       [generate options]
///   pbn watercolor <photo | template.pbnt> --out <dir> --making-of [--fps N]   (`runMakingOf`)
///
/// Writes painting.ppm (dried), frame-<t>.ppm for each time asked (seconds from the first tap,
/// wet), watercolor.json (the tap log) and prints the steps' timings.
func runWatercolor(_ options: Options) throws {
    guard options.positional.count == 1, let out = options.out else {
        fail("usage: pbn watercolor <photo | template.pbnt> --out <dir> [--spacing S] [--order paint|sweep] [--frames t,…] [generate options]")
    }
    let path = options.positional[0]
    let template: Template
    if path.hasSuffix(".pbnt") {
        guard let data = FileManager.default.contents(atPath: path) else { fail("cannot read \(path)") }
        do { template = try Template(encoded: data) } catch { fail("cannot decode \(path): \(error)") }
    } else {
        template = try TemplateGenerator(settings: options.settings).generate(from: loadImage(path), cancel: .none).template
    }
    let outDir = URL(fileURLWithPath: out)
    try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
    let spacing = Float(options.watercolorSpacing ?? 0.12)
    let frames = options.watercolorFrames ?? []
    let seed = options.settings.seed

    let made = Date()
    let sheet = WatercolorSheet(template: template, seed: seed)
    print(String(format: "sheet %d x %d, %d areas, made in %.0f ms", sheet.width, sheet.height, sheet.regionCount,
                 Date().timeIntervalSince(made) * 1000))
    if options.watercolorMakingOf {
        try runMakingOf(template: template, sheet: sheet, fps: options.watercolorFPS ?? 15, out: outDir)
        return
    }
    let sim = WatercolorSim(sheet: sheet)
    // Paint by paint, each paint's areas from the top left down; or `sweep`, every area from the
    // top left down whatever its paint, so neighbours go on while each other is still wet.
    let sweep: Bool
    switch options.watercolorOrder ?? "paint" {
    case "paint": sweep = false
    case "sweep": sweep = true
    default: fail("--order is paint or sweep")
    }
    let order = template.labels.indices
        .sorted { a, b in
            let la = template.labels[a], lb = template.labels[b]
            let ca = template.regions[Int(la.region)].colorIndex, cb = template.regions[Int(lb.region)].colorIndex
            if !sweep, ca != cb { return ca < cb }
            let sa = la.position.x + la.position.y, sb = lb.position.x + lb.position.y
            return sa != sb ? sa < sb : la.region < lb.region
        }
    var seen = Set<UInt32>()
    var log = WatercolorLog(seed: seed)
    var steps: [Double] = []
    var taps: [(step: Int, label: Label)] = []
    var next = 0
    for i in order where seen.insert(template.labels[i].region).inserted {
        taps.append((next, template.labels[i]))
        next += max(1, Int((spacing / WatercolorSim.dt).rounded()))
    }
    var pendingFrames = frames.sorted()
    var tapIndex = 0
    while tapIndex < taps.count || sim.isActive {
        while tapIndex < taps.count, taps[tapIndex].step <= sim.step {
            let label = taps[tapIndex].label
            log.taps.append(.init(step: sim.step, region: Int(label.region), x: label.position.x, y: label.position.y, paint: true))
            let t0 = Date()
            sim.tap(region: Int(label.region), at: label.position, paint: true)
            steps.append(-Date().timeIntervalSince(t0))  // taps counted apart (negative)
            tapIndex += 1
        }
        if let f = pendingFrames.first, sim.time >= f {
            pendingFrames.removeFirst()
            try writePPM(watercolorRaster(sim, template: template), String(format: "frame-%05.2f.ppm", f), in: outDir)
        }
        let t0 = Date()
        sim.advance()
        steps.append(Date().timeIntervalSince(t0))
    }
    try writePPM(watercolorRaster(sim, template: template), "painting.ppm", in: outDir)
    try log.encoded().write(to: outDir.appendingPathComponent("watercolor.json"))
    let stepTimes = steps.filter { $0 >= 0 }.sorted()
    let tapTimes = steps.filter { $0 < 0 }.map { -$0 }.sorted()
    func ms(_ a: [Double], _ q: Double) -> Double { a.isEmpty ? 0 : a[min(a.count - 1, Int(Double(a.count) * q))] * 1000 }
    print(String(format: "%d taps over %.1f s: step median %.2f ms, p95 %.2f ms, max %.2f ms; tap median %.2f ms, max %.2f ms",
                 log.taps.count, sim.time, ms(stepTimes, 0.5), ms(stepTimes, 0.95), ms(stepTimes, 1), ms(tapTimes, 0.5), ms(tapTimes, 1)))
    let replayed = Date()
    let again = WatercolorSim(sheet: WatercolorSheet(template: template, seed: seed))
    again.replay(log)
    print(String(format: "replay of the log: %.0f ms", Date().timeIntervalSince(replayed) * 1000))
}

/// The Making Of as the app plays it (`WatercolorMakingOf`): its own simulation stepped to the
/// step each frame shows, drawn wet every 1/`fps` second shown with no numbers and the pencil
/// going from under painted areas as it dries, as the app's film draws it, on past the moment it
/// settles for the app's hold and lift (`tail` seconds), as the app steps on while it ends.
/// Writes bare.ppm (the pencilled sheet the lift leaves, without its numbers) and labels.csv
/// (each number where the app draws it: x and y as fractions of the sheet, its font size as a
/// fraction of the sheet's width, `LabelSizing` as the sheet's renderers size it, and the number),
/// making-of.csv
/// (per frame: the step, the share of the sheet wet, whether it dries and has settled),
/// focus.txt (where the film pushes in, fractions of the sheet) and prints the steps' cost: the
/// app makes them off the main actor as the frames come due.
func runMakingOf(template: Template, sheet: WatercolorSheet, fps: Double, out: URL, tail: Double = 1.7) throws {
    let plan = WatercolorMakingOf(template: template, sheet: sheet)
    let sim = WatercolorSim(sheet: sheet)
    let fine = WatercolorSheet.paperHeight(width: sheet.width * 2, height: sheet.height * 2, seed: sheet.seed &+ 11)
    var cursor = 0, frame = 0
    var stepping: Double = 0, worstFrame: Double = 0
    var settledAt: Double?
    var csv = "frame,shown,step,simulated,wet,settled,drying\n"
    let cells = sheet.width * sheet.height
    try writePPM(watercolorRaster(sim, template: template, fine: fine), "bare.ppm", in: out)
    var labels = "x,y,size,number\n"
    let maxSize = LabelSizing.sheetMaximumFraction * Float(max(template.width, template.height))
    for label in template.labels {
        let number = Int(template.regions[Int(label.region)].colorIndex) + 1
        let size = LabelSizing.fontSize(radius: label.radius, digits: LabelSizing.digitCount(of: number), maximum: maxSize,
                                        detail: template.isDetailRegion(Int(label.region)))
        labels += String(format: "%.5f,%.5f,%.5f,%d\n", label.position.x / Float(template.width),
                         label.position.y / Float(template.height), size / Float(template.width), number)
    }
    try labels.write(to: out.appendingPathComponent("labels.csv"), atomically: true, encoding: .utf8)
    let focus = plan.focus ?? SIMD2(Float(template.width), Float(template.height)) / 2
    try String(format: "%.4f %.4f\n", focus.x / Float(template.width), focus.y / Float(template.height))
        .write(to: out.appendingPathComponent("focus.txt"), atomically: true, encoding: .utf8)
    while true {
        let shown = Double(frame) / fps
        let t0 = Date()
        plan.play(sim, to: plan.step(at: shown), cursor: &cursor)
        let settled = settledAt != nil || plan.isSettled(sim, cursor: cursor)
        let took = Date().timeIntervalSince(t0)
        if settledAt == nil {
            stepping += took
            worstFrame = max(worstFrame, took)
        }
        if settled, settledAt == nil { settledAt = shown }
        try writePPM(watercolorRaster(sim, template: template, fine: fine, front: plan.dryingFront(at: sim.time),
                                         pencilFade: plan.pencilFade(at: sim.time)),
                     String(format: "frame-%04d.ppm", frame), in: out)
        var wet = 0
        for i in 0..<cells where sim.W[i] > 0 { wet += 1 }
        csv += String(format: "%d,%.3f,%d,%.3f,%.4f,%d,%d\n", frame, shown, sim.step, sim.time, Double(wet) / Double(cells), settled ? 1 : 0,
                      plan.isDrying(sim) ? 1 : 0)
        frame += 1
        if let settledAt, shown >= settledAt + tail { break }
    }
    try csv.write(to: out.appendingPathComponent("making-of.csv"), atomically: true, encoding: .utf8)
    let settledStep = plan.step(at: settledAt ?? 0)
    print(String(format: "making of: %d taps, settled at %.1f s shown (%d steps, %.1f s simulated); stepping %.0f ms in all, %.2f ms a step, worst frame %.0f ms",
                 plan.log.taps.count, settledAt ?? 0, settledStep, Double(settledStep) * Double(WatercolorSim.dt),
                 stepping * 1000, stepping * 1000 / Double(max(settledStep, 1)), worstFrame * 1000))
}

/// The sheet as the app's shader draws it, at twice the simulation's grid (`fine`: the paper's
/// fine tooth there, made once for many frames), without numbers. With `front`, the film's wet
/// paint: the shader's, darker with a sheen where the water's surface tilts, shown more, over
/// every painted area ahead of the drying front standing there (`u.film.y`,
/// `WatercolorMakingOf.dryingFront`); with `pencilFade`, the pencil that much gone from under
/// painted areas (the film's, `u.film.x`).
func watercolorRaster(_ sim: WatercolorSim, template t: Template, fine: [Float]? = nil,
                      front: Float? = nil, pencilFade: Float = 0) -> RGBAImage {
    let sheet = sim.sheet
    let w = sheet.width, h = sheet.height, W2 = w * 2, H2 = h * 2
    var targets: [(gain: SIMD3<Float>, aim: SIMD3<Float>)] = []
    for r in 0..<sheet.regionCount { targets.append(sim.target(of: r)) }
    let glazes = (0..<sheet.regionCount).map { sim.glaze(of: $0) }
    let fine = fine ?? WatercolorSheet.paperHeight(width: W2, height: H2, seed: sheet.seed &+ 11)
    var image = RGBAImage(width: W2, height: H2, fill: SIMD4(0, 0, 0, 255))
    func cell(_ x: Int, _ y: Int) -> Int { min(max(y, 0), h - 1) * w + min(max(x, 0), w - 1) }
    let graphite = SIMD3<Float>(0.30, 0.30, 0.33)
    for y in 0..<H2 {
        for x in 0..<W2 {
            // Bilinear on the grid, from the cells of the pixel's own region alone where it has
            // any (so a wash ends on the pencil line, not on the grid's staircase), and the
            // target solve by the region under the pixel.
            let gx = (Float(x) + 0.5) / 2 - 0.5, gy = (Float(y) + 0.5) / 2 - 0.5
            let x0 = Int(gx.rounded(.down)), y0 = Int(gy.rounded(.down))
            let fx = gx - Float(x0), fy = gy - Float(y0)
            let canvas = SIMD2(Float(x) + 0.5, Float(y) + 0.5) / (2 * sheet.scale)
            let r = t.region(at: canvas) ?? 0
            func dens(_ i: Int) -> SIMD4<Float> { sim.D[i] + 0.9 * sim.S[i] }
            let corners = [(cell(x0, y0), (1 - fx) * (1 - fy)), (cell(x0 + 1, y0), fx * (1 - fy)),
                           (cell(x0, y0 + 1), (1 - fx) * fy), (cell(x0 + 1, y0 + 1), fx * fy)]
            var d4 = SIMD4<Float>(repeating: 0), mine = SIMD4<Float>(repeating: 0)
            var mineWeight: Float = 0
            for (i, wgt) in corners {
                d4 += dens(i) * wgt
                if Int(sheet.labels[i]) == r { mine += dens(i) * wgt; mineWeight += wgt }
            }
            if mineWeight > 1e-3 { d4 = mine / mineWeight }
            let gr = corners.reduce(Float(0)) { $0 + sim.G[$1.0] * $1.1 }
            let target = targets[r]
            var d = SIMD3(max(d4.x, 0), max(d4.y, 0), max(d4.z, 0)) * target.gain
            // One factor for all three channels (the shader's reason).
            var ratio: Float = 1
            for c in 0..<3 where d[c] >= 1e-5 {
                let cap = max(target.aim[c] * 1.7, 0.05)
                ratio = min(ratio, cap * tanh(d[c] / cap) / d[c])
            }
            d *= ratio
            // A thin area's paint, a glaze over what its neighbours' water left.
            d += target.aim * glazes[r]
            let p2 = fine[y * W2 + x]
            d *= 1 + gr * 0.6 * (0.5 - p2)
            var refl = WatercolorSheet.paperColor * SIMD3(exp(-d.x), exp(-d.y), exp(-d.z))
            let sx = fine[y * W2 + min(x + 1, W2 - 1)] - fine[y * W2 + max(x - 1, 0)]
            let sy = fine[min(y + 1, H2 - 1) * W2 + x] - fine[max(y - 1, 0) * W2 + x]
            let under = min(max((d.x + d.y + d.z) / 3 / 1.2, 0), 1)
            refl *= min(max(1 + 0.45 * (sx + sy) * (1 - 0.6 * under), 0.85), 1.1)
            if let front {
                func water(_ gx: Float, _ gy: Float) -> Float {
                    let x0 = Int(gx.rounded(.down)), y0 = Int(gy.rounded(.down))
                    let fx = gx - Float(x0), fy = gy - Float(y0)
                    return (sim.W[cell(x0, y0)] * (1 - fx) + sim.W[cell(x0 + 1, y0)] * fx) * (1 - fy)
                        + (sim.W[cell(x0, y0 + 1)] * (1 - fx) + sim.W[cell(x0 + 1, y0 + 1)] * fx) * fy
                }
                let along = (Float(x) + 0.5) / Float(W2) / 2 + (Float(y) + 0.5) / Float(H2) / 2
                let e = min(max((along - (front - 0.15)) / 0.3, 0), 1)
                let ahead = e * e * (3 - 2 * e)
                let painted: Float = sim.paintedAt[r] <= sim.time ? 1 : 0
                let wetness = max(min(max(water(gx, gy) / 0.6, 0), 1), painted) * ahead
                if wetness > 0 {
                    let wx = water(gx + 2, gy) - water(gx - 2, gy), wy = water(gx, gy + 2) - water(gx, gy - 2)
                    let emphasis: Float = 1
                    refl *= 1 - 0.07 * wetness * (1 + 2 * emphasis)
                    let spec = pow(min(max(-(wx + wy) * 0.8, 0), 1), 2) * wetness
                    refl += SIMD3(repeating: 0.12 * spec * (1 + emphasis))
                }
            }
            // Pencil where the region changes within a canvas unit.
            let here = t.region(at: canvas), right = t.region(at: canvas + SIMD2(1, 0)), down = t.region(at: canvas + SIMD2(0, 1))
            if here != right || here != down {
                let painted: Float = sim.paintedAt[r] <= sim.time ? 1 : 0
                let ink = 0.55 * (1 - 0.75 * min(under * 2.5, 1)) * (1 - pencilFade * painted)
                refl = refl * (1 - ink * (1 - graphite))
            }
            let p3 = refl
            // Linear P3 to sRGB for the file (close enough to judge by: P3 paints keep their hue).
            let srgb = ColorScience.p3ToSRGBLinear(p3)
            func byte(_ v: Float) -> UInt8 { UInt8(min(max(ColorScience.encodeSRGB(v), 0), 1) * 255 + 0.5) }
            image[x, y] = SIMD4(byte(srgb.x), byte(srgb.y), byte(srgb.z), 255)
        }
    }
    return image
}
