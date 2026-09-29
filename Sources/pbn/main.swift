import Foundation
import PaintCore

// Headless driver for the template pipeline: generate templates, render previews and
// report timings/metrics. Images are exchanged as PPM so no codecs are needed.
//
//   pbn generate <in.ppm> <outdir> [--colors N] [--detail F] [--smooth F] [--importance m.pgm]
//   pbn bench <in.ppm>... [--runs N] [--colors N] [--detail F] [--smooth F]

struct Options {
    var positional: [String] = []
    var settings = GenerationSettings()
    var importance: String?
    var runs = 3
}

func parse(_ args: ArraySlice<String>) -> Options {
    var o = Options()
    var it = args.makeIterator()
    while let a = it.next() {
        switch a {
        case "--colors": o.settings.colorCount = Int(it.next() ?? "") ?? o.settings.colorCount
        case "--detail": o.settings.detail = Float(it.next() ?? "") ?? o.settings.detail
        case "--smooth": o.settings.smoothness = Float(it.next() ?? "") ?? o.settings.smoothness
        case "--seed": o.settings.seed = UInt64(it.next() ?? "") ?? o.settings.seed
        case "--importance": o.importance = it.next()
        case "--runs": o.runs = Int(it.next() ?? "") ?? o.runs
        default: o.positional.append(a)
        }
    }
    return o
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

func loadImage(_ path: String) -> RGBAImage {
    guard let data = FileManager.default.contents(atPath: path) else { fail("cannot read \(path)") }
    do { return try Netpbm.read(data) } catch { fail("cannot decode \(path): \(error)") }
}

func loadImportance(_ path: String?) -> Grid<Float>? {
    guard let path else { return nil }
    let img = loadImage(path)
    return Grid(width: img.width, height: img.height,
                storage: (0..<(img.width * img.height)).map { Float(img.pixels[$0 * 4]) / 255 })
}

/// Raster preview: each pixel painted with its region's palette color.
func paintedRaster(_ t: Template) -> RGBAImage {
    var px = [UInt8](repeating: 255, count: t.width * t.height * 4)
    let colors = t.palette.map { c in
        SIMD3<UInt8>(UInt8((c.rgb.x * 255).rounded()), UInt8((c.rgb.y * 255).rounded()), UInt8((c.rgb.z * 255).rounded()))
    }
    for i in 0..<(t.width * t.height) {
        let c = colors[Int(t.regions[Int(t.regionMap.storage[i])].colorIndex)]
        px[i * 4] = c.x; px[i * 4 + 1] = c.y; px[i * 4 + 2] = c.z
    }
    return RGBAImage(width: t.width, height: t.height, pixels: px, colorSpace: t.colorSpace)
}

/// Region-shape debug view at 2× scale: softened palette fills with 1-px dark lines wherever
/// neighbouring canvas units belong to different regions.
func boundaryRaster(_ t: Template) -> RGBAImage {
    let w = t.width, h = t.height, ow = w * 2, oh = h * 2
    var px = [UInt8](repeating: 255, count: ow * oh * 4)
    let colors = t.palette.map { c -> SIMD3<UInt8> in
        let soft = c.rgb * 0.7 + SIMD3(repeating: 0.3)
        return SIMD3(UInt8((soft.x * 255).rounded()), UInt8((soft.y * 255).rounded()), UInt8((soft.z * 255).rounded()))
    }
    let map = t.regionMap
    for y in 0..<oh {
        let sy = y / 2
        for x in 0..<ow {
            let sx = x / 2
            let r = map[sx, sy]
            var line = false
            if x & 1 == 1 && sx + 1 < w && map[sx + 1, sy] != r { line = true }
            if y & 1 == 1 && sy + 1 < h && map[sx, sy + 1] != r { line = true }
            if x & 1 == 1 && y & 1 == 1 && sx + 1 < w && sy + 1 < h && map[sx + 1, sy + 1] != r { line = true }
            let c = line ? SIMD3<UInt8>(40, 40, 40) : colors[Int(t.regions[Int(r)].colorIndex)]
            let o = (y * ow + x) * 4
            px[o] = c.x; px[o + 1] = c.y; px[o + 2] = c.z
        }
    }
    return RGBAImage(width: ow, height: oh, pixels: px, colorSpace: t.colorSpace)
}

struct Metrics: Codable {
    var width: Int
    var height: Int
    var colors: Int
    var regions: Int
    var edges: Int
    var points: Int
    var triangles: Int
    var meanDeltaE: Float
    var p95DeltaE: Float
    var medianRegionArea: Float
    var regionsUnderRadius2: Int
    var regionsUnderRadius3: Int
    var minPaletteDistance: Float
    var timingsMs: [String: Double]
    var totalMs: Double
    var encodedBytes: Int
    var palette: [String]
}

func metrics(_ out: TemplateGenerator.Output, working: RGBAImage) -> Metrics {
    let t = out.template
    let lab = ColorScience.okLabImage(from: working)
    var errors = [Float](repeating: 0, count: t.width * t.height)
    for i in 0..<errors.count {
        let p = lab.storage[i]
        let c = t.palette[Int(t.regions[Int(t.regionMap.storage[i])].colorIndex)].oklab
        errors[i] = ColorScience.distance(SIMD3(p.x, p.y, p.z), c)
    }
    let sortedErrors = errors.sorted()
    let areas = t.regions.map(\.area).sorted()
    var minPal = Float.infinity
    for i in 0..<t.palette.count {
        for j in (i + 1)..<t.palette.count {
            minPal = min(minPal, ColorScience.distance(t.palette[i].oklab, t.palette[j].oklab))
        }
    }
    var timings: [String: Double] = [:]
    for timing in out.timings { timings[timing.name, default: 0] += timing.seconds * 1000 }
    return Metrics(
        width: t.width, height: t.height, colors: t.palette.count, regions: t.regions.count,
        edges: t.edges.count, points: t.points.count, triangles: t.mesh.indices.count / 3,
        meanDeltaE: errors.reduce(0, +) / Float(max(1, errors.count)),
        p95DeltaE: sortedErrors.isEmpty ? 0 : sortedErrors[Int(Float(sortedErrors.count - 1) * 0.95)],
        medianRegionArea: areas.isEmpty ? 0 : areas[areas.count / 2],
        regionsUnderRadius2: t.regions.filter { $0.inscribedRadius < 2 }.count,
        regionsUnderRadius3: t.regions.filter { $0.inscribedRadius < 3 }.count,
        minPaletteDistance: minPal.isFinite ? minPal : 0,
        timingsMs: timings, totalMs: out.totalSeconds * 1000,
        encodedBytes: t.encoded().count,
        palette: t.palette.map { c in
            c.rgb.indices.map { String(format: "%02x", Int((min(max(c.rgb[$0], 0), 1) * 255).rounded())) }.joined()
        })
}

let args = CommandLine.arguments
guard args.count >= 2 else { fail("usage: pbn generate|bench ...") }
let options = parse(args.dropFirst(2))

switch args[1] {
case "generate":
    guard options.positional.count == 2 else { fail("usage: pbn generate <in.ppm> <outdir> [options]") }
    let image = loadImage(options.positional[0])
    let outDir = URL(fileURLWithPath: options.positional[1])
    try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
    let generator = TemplateGenerator(settings: options.settings)
    let output: TemplateGenerator.Output
    do {
        output = try generator.generate(from: image, importance: loadImportance(options.importance), cancel: .none)
    } catch { fail("generation failed: \(error)") }
    let t = output.template
    let size = generator.settings.workingSize(sourceWidth: image.width, sourceHeight: image.height)
    let working = Resample.area(image, width: size.width, height: size.height)
    let m = metrics(output, working: working)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(m).write(to: outDir.appendingPathComponent("stats.json"))
    try t.encoded().write(to: outDir.appendingPathComponent("template.pbnt"))
    try Netpbm.encodePPM(paintedRaster(t)).write(to: outDir.appendingPathComponent("raster.ppm"))
    try Netpbm.encodePPM(working).write(to: outDir.appendingPathComponent("working.ppm"))
    try Netpbm.encodePPM(boundaryRaster(t)).write(to: outDir.appendingPathComponent("boundaries.ppm"))
    try SVGExport.render(t, options: .init(painted: true, outlines: false, numbers: false))
        .write(to: outDir.appendingPathComponent("painted.svg"), atomically: true, encoding: .utf8)
    try SVGExport.render(t, options: .init(painted: false, outlines: true, numbers: true))
        .write(to: outDir.appendingPathComponent("template.svg"), atomically: true, encoding: .utf8)
    try SVGExport.render(t, options: .init(painted: true, outlines: true, numbers: false))
        .write(to: outDir.appendingPathComponent("painted-outlined.svg"), atomically: true, encoding: .utf8)
    print(String(data: try encoder.encode(m), encoding: .utf8)!)

case "bench":
    guard !options.positional.isEmpty else { fail("usage: pbn bench <in.ppm>...") }
    let generator = TemplateGenerator(settings: options.settings)
    for path in options.positional {
        let image = loadImage(path)
        var totals: [String: [Double]] = [:]
        var order: [String] = []
        var regionCount = 0
        for _ in 0..<options.runs {
            let out: TemplateGenerator.Output
            do { out = try generator.generate(from: image, cancel: .none) } catch { fail("\(error)") }
            regionCount = out.template.regions.count
            var perRun: [String: Double] = [:]
            for t in out.timings {
                if totals[t.name] == nil { order.append(t.name) }
                perRun[t.name, default: 0] += t.seconds * 1000
            }
            for (k, v) in perRun { totals[k, default: []].append(v) }
        }
        print("\(path) — \(regionCount) regions")
        for name in order {
            let v = totals[name]!.sorted()
            print(String(format: "  %-28@ median %8.1f ms   min %8.1f ms", name as NSString, v[v.count / 2], v[0]))
        }
    }

default:
    fail("unknown command \(args[1])")
}
