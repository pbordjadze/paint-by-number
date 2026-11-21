import Foundation
import PaintCore

/// `pbn cave`: the Cave (painting-company row 371) off the device: a painting's plan from a photo
/// and its subject mask (`CavePlan.make`), and a stretch of wall lit by a torch as the app's
/// shader lights it, near enough to judge the rock, the drawing and the pigment by: the mouth, the
/// painting finished with a hand beside it, the same painting half blown with the pigments on
/// its ledge, and bare rock with its charcoal.
struct CaveReport: Encodable {
    var kind: String
    var width: Int
    var height: Int
    var areas: Int
    var pigments: [Int]
    var planBytes: Int
    var seconds: Double
}

func runCave(_ options: Options) throws {
    guard let out = options.out, options.positional.count == 0 || options.positional.count == 2 else {
        fail("usage: pbn cave [<photo> <subject-mask.pgm>] --out <dir> [--figure]")
    }
    let photo: RGBAImage, subject: Grid<Float>
    if options.positional.count == 2 {
        photo = loadImage(options.positional[0])
        let mask = loadImage(options.positional[1])
        subject = Grid(width: mask.width, height: mask.height, storage: (0..<(mask.width * mask.height)).map { Float(mask.pixels[$0 * 4]) / 255 })
    } else {
        (photo, subject) = CaveSample.horse()
    }
    let outDir = URL(fileURLWithPath: out)
    try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
    let start = Date()
    let plan = CavePlan.make(photo: photo, subject: subject, kind: options.caveFigure ? .figure : .animal)
    let made = Date().timeIntervalSince(start)
    try plan.encoded().write(to: outDir.appendingPathComponent("cave.plan"))

    // The plan's areas, each in its pigment, and its lines.
    var areas = RGBAImage(width: plan.width, height: plan.height, fill: SIMD4(40, 40, 40, 255))
    for i in 0..<(plan.width * plan.height) {
        var rgb = SIMD3<Float>(0.16, 0.16, 0.16)
        if plan.areas[i] > 0 {
            rgb = plan.pigments[Int(plan.areas[i]) - 1].rgb
            let x = i % plan.width, y = i / plan.width
            if x > 0, plan.areas[i - 1] != plan.areas[i] { rgb = SIMD3(1, 1, 1) }
            if y > 0, plan.areas[i - plan.width] != plan.areas[i] { rgb = SIMD3(1, 1, 1) }
        }
        if plan.lines[i] { rgb = SIMD3(0, 0, 0) }
        for c in 0..<3 { areas.pixels[i * 4 + c] = UInt8(min(255, rgb[c] * 255)) }
    }
    try writePPM(areas, "areas.ppm", in: outDir)

    // Four bays: the mouth, the painting finished with a hand, half blown, and bare rock.
    let bays: [(CaveBay.Content, CaveBay.Tools)] = [(.mouth, .none), (.painting(plan), .none), (.painting(plan), .pigments), (.bare, .charcoal)]
    let mapStart = Date()
    let maps = bays.enumerated().map { CaveBay.maps(index: $0.offset, content: $0.element.0, tools: $0.element.1) }
    let mapSeconds = Date().timeIntervalSince(mapStart) / 4
    var finished = CavePigmentLayer(plan: plan)
    finished.finishAll()
    let h = CaveWall.handSpot
    finished.stencil(CaveHand(fingers: [h + SIMD2(-54, 40), h + SIMD2(-30, -18), h + SIMD2(-4, -32), h + SIMD2(22, -22), h + SIMD2(42, 4)],
                              widths: [11, 9, 9, 9, 8]), amount: 1)
    var half = CavePigmentLayer(plan: plan)
    for a in 1...plan.areaCount where a % 2 == 1 {
        let points = half.points(of: a)
        for (k, p) in points.enumerated() where k % 23 == 0 {
            half.blow(at: p, radius: 12, amount: 0.3, pigment: plan.pigments[a - 1])
        }
        half.settle(seconds: 1)
    }
    let layers: [CavePigmentLayer?] = [nil, finished, half, nil]
    // A torch over each bay but the mouth, as a painter might leave it.
    let torches: [SIMD3<Float>] = [SIMD3(420 + 40, 480, 64), SIMD3(800 + 60, 470, 64), SIMD3(1200 + 40, 470, 64), SIMD3(1600 + 120, 520, 64)]
    let lit = caveRaster(maps: maps, layers: layers, torches: torches)
    try writePPM(lit, "wall.ppm", in: outDir)

    let report = CaveReport(kind: plan.kind == .animal ? "animal" : "figure", width: plan.width, height: plan.height,
                            areas: plan.areaCount, pigments: CavePigment.allCases.map { p in plan.pigments.filter { $0 == p }.count },
                            planBytes: plan.encoded().count, seconds: made)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(report).write(to: outDir.appendingPathComponent("cave.json"))
    print("cave: \(report.kind), \(report.areas) areas \(report.pigments), plan \(String(format: "%.2f", made)) s, a bay's maps \(String(format: "%.2f", mapSeconds)) s")
}

/// The bays side by side, lit as `CaveShader` lights them (at map resolution, without its
/// calcite, flicker or vignette): relief normals, a torch with soft shadows from the relief, the
/// fat lamp by the tools, the mouth's daylight.
func caveRaster(maps: [CaveBay.Maps], layers: [CavePigmentLayer?], torches: [SIMD3<Float>]) -> RGBAImage {
    let mw = CaveWall.mapWidth, mh = CaveWall.mapHeight, s = Float(CaveWall.scale)
    let width = mw * maps.count
    var image = RGBAImage(width: width, height: mh, fill: SIMD4(0, 0, 0, 255))
    let depth = CaveBay.reliefDepth
    func height(_ x: Float, _ y: Float) -> Float {
        let i = min(width - 1, max(0, Int(x * s))), j = min(mh - 1, max(0, Int(y * s)))
        let b = i / mw
        return maps[b].relief[j * mw + i % mw] * depth
    }
    let pigments = layers.map { $0.map { ($0.rgba()) } }
    func smooth(_ a: Float, _ b: Float, _ x: Float) -> Float { let t = min(1, max(0, (x - a) / (b - a))); return t * t * (3 - 2 * t) }
    for j in 0..<mh {
        for i in 0..<width {
            let b = i / mw, li = i % mw
            let x = (Float(i) + 0.5) / s, y = (Float(j) + 0.5) / s
            let map = maps[b]
            let k = j * mw + li
            let hx = height(x + 0.5, y) - height(x - 0.5, y), hy = height(x, y + 0.5) - height(x, y - 0.5)
            var n = SIMD3(-hx, -hy, 1)
            n /= (n * n).sum().squareRoot()
            let p = SIMD3(x, y, map.relief[k] * depth)
            let base = SIMD3(Float(map.rock[k * 4]), Float(map.rock[k * 4 + 1]), Float(map.rock[k * 4 + 2])) / 255
            let day = Float(map.rock[k * 4 + 3]) / 255
            var albedo = base
            if let pg = pigments[b] {
                let pi = (Int(y) * CavePigmentLayer.width + Int(x - Float(b * CaveWall.bayWidth))) * 4
                let cov = Float(pg[pi + 3]) / 255
                let tint = SIMD3(Float(pg[pi]), Float(pg[pi + 1]), Float(pg[pi + 2])) / 255
                let soaked: SIMD3<Float> = tint * (SIMD3<Float>(repeating: 0.45) + base * (0.55 / 0.8))
                let charcoal = smooth(0.30, 0.12, (base.x + base.y + base.z) / 3)
                albedo += (soaked - albedo) * (cov * (1 - charcoal))
            }
            albedo *= 0.55 + 0.45 * smooth(-40, 170, y)
            let torch = torches[b]
            var l = torch - p
            let d = (l * l).sum().squareRoot()
            l /= d
            let att = 1 / (1 + (d / 330) * (d / 330) * 1.2)
            // Soft shadow: march toward the flame over the relief.
            var shade: Float = 1
            let reach = min(d, 200)
            for step in 1...16 {
                let t = reach * Float(step) / 16
                let q = p + l * t
                let under = height(q.x, q.y) - q.z
                if under > -0.5 { shade = min(shade, max(0, 1 - (under + 0.5) / 3)) }
            }
            let diff = max(0, (n * l).sum())
            let wrap = max(0, (n * l).sum() * 0.5 + 0.5)
            let flame = SIMD3<Float>(1, 0.58, 0.26) * (0.9 * att)
            var color: SIMD3<Float> = albedo * flame * (diff * 1.6 * shade + wrap * 0.3)
            if maps[b].index >= 0, b == 2 {
                let lamp = SIMD3(Float(b * CaveWall.bayWidth) + CaveWall.lampFlame.x, CaveWall.lampFlame.y - 6, 30)
                var l2 = lamp - p
                let d2 = (l2 * l2).sum().squareRoot()
                l2 /= d2
                let lampLight: Float = max(0, (n * l2).sum()) / (1 + (d2 / 120) * (d2 / 120) * 1.6) * 1.1
                color += albedo * SIMD3<Float>(1, 0.62, 0.30) * lampLight
            }
            let mouth = SIMD3(CaveWall.mouth.x, CaveWall.mouth.y, 80)
            var lm = mouth - p
            let dm = (lm * lm).sum().squareRoot()
            lm /= dm
            let daylight: Float = (max(0, (n * lm).sum()) * 0.9 + 0.15) / (1 + pow(dm / 300, 3)) * 1.5
            color += albedo * SIMD3<Float>(0.55, 0.68, 0.90) * daylight
            let bright = SIMD3<Float>(1.9, 1.95, 2.05), sky = SIMD3<Float>(1.25, 1.4, 1.65)
            let outside: SIMD3<Float> = bright + (sky - bright) * smooth(0.95, 0.3, day)
            let open = smooth(0.02, 0.5, day)
            color += (outside - color) * open
            let g = (SIMD2(x, y) - CaveWall.mouth) / SIMD2(175, 265)
            let glare: Float = exp(-(g * g).sum() * 1.3) * 0.55 * (1 - open)
            color += SIMD3<Float>(0.75, 0.85, 1) * glare
            color *= 1.35
            color /= 1 + color * 0.5
            for c in 0..<3 { image.pixels[(j * width + i) * 4 + c] = UInt8(min(255, pow(max(0, color[c]), 1 / 1.08) * 255)) }
        }
    }
    return image
}
