import Foundation
import PaintCore

/// `pbn glass`: a Stained Glass window (painting-company row 366) from a photo and the painter's
/// lines, off the device: the window as `GlassWindow.leaded` makes it, its suggested glasses
/// (`GlassPalette`), and a preview of it lit with them.
struct GlassScript: Decodable {
    /// Each line's points as fractions of the photo's width and height (0…1, x right, y down).
    var lines: [[[Float]]]
}

struct GlassReport: Encodable {
    var pieces: Int
    var glasses: [[Float]]
    var offered: Int
    var background: Int
    var lines: [String]
    var valid: Bool
    var validation: String
}

func runGlass(_ options: Options) throws {
    guard options.positional.count == 2, let out = options.out else {
        fail("usage: pbn glass <photo> <lines.json> --out <dir> [generate options]")
    }
    let photo = loadImage(options.positional[0])
    guard let data = FileManager.default.contents(atPath: options.positional[1]) else { fail("cannot read \(options.positional[1])") }
    let script: GlassScript
    do { script = try JSONDecoder().decode(GlassScript.self, from: data) } catch { fail("cannot decode \(options.positional[1]): \(error)") }
    let outDir = URL(fileURLWithPath: out)
    try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
    let size = options.settings.workingSize(sourceWidth: photo.width, sourceHeight: photo.height)
    let lines = script.lines.map { line in
        line.compactMap { p in p.count == 2 ? SIMD2(p[0] * Float(size.width), p[1] * Float(size.height)) : nil }
    }
    let window: GlassWindow.Leaded
    do {
        window = try GlassWindow.leaded(photo: photo, width: size.width, height: size.height, colorSpace: photo.colorSpace, lines: lines,
                                    joining: Float(max(size.width, size.height)) * 0.02)
    } catch { fail("no window: \(error)") }
    let t = window.template
    let report = t.validate()
    try t.encoded().write(to: outDir.appendingPathComponent("window.pbnt"))
    let glazing = (0..<t.regions.count).map { Int16(t.regions[$0].colorIndex) }
    try writePPM(glassRaster(t, glazing: glazing, offered: GlassPalette.offered(for: t)), "lit.ppm", in: outDir)
    try writePPM(glassRaster(t, glazing: Array(repeating: Glazing.none, count: t.regions.count), offered: GlassPalette.offered(for: t)),
                 "unlit.ppm", in: outDir)
    let summary = GlassReport(
        pieces: t.regions.count, glasses: t.palette.map { [$0.oklab.x, $0.oklab.y, $0.oklab.z] },
        offered: GlassPalette.offered(for: t).count, background: window.suggestion.isBackground.filter { $0 }.count,
        lines: window.verdicts.map { "\($0)" }, valid: report.isValid, validation: report.description)
    let json = try jsonEncoder().encode(summary)
    try json.write(to: outDir.appendingPathComponent("glass.json"))
    print(String(data: json, encoding: .utf8)!)
}

/// The window as glass: each glazed piece its glass, lit (brighter toward its middle, a little
/// ripple), a piece not glazed dark with a hint of its suggested glass, and lead along every
/// boundary and the frame. A preview for judging glasses, not the app's renderer.
func glassRaster(_ t: Template, glazing: [Int16], offered: [PaletteColor]) -> RGBAImage {
    let w = t.width, h = t.height, n = w * h
    let map = t.regionMap.storage
    // Distance to the nearest other piece or the frame, by two chamfer passes.
    var d = [Float](repeating: .greatestFiniteMagnitude, count: n)
    for y in 0..<h {
        for x in 0..<w {
            let i = y * w + x, r = map[i]
            if x == 0 || y == 0 || x == w - 1 || y == h - 1 || map[i - 1] != r || map[i + 1] != r || map[i - w] != r || map[i + w] != r {
                d[i] = 0
            }
        }
    }
    for y in 0..<h {
        for x in 0..<w {
            let i = y * w + x
            if x > 0 { d[i] = min(d[i], d[i - 1] + 1) }
            if y > 0 { d[i] = min(d[i], d[i - w] + 1); if x > 0 { d[i] = min(d[i], d[i - w - 1] + 1.414) }; if x < w - 1 { d[i] = min(d[i], d[i - w + 1] + 1.414) } }
        }
    }
    for y in stride(from: h - 1, through: 0, by: -1) {
        for x in stride(from: w - 1, through: 0, by: -1) {
            let i = y * w + x
            if x < w - 1 { d[i] = min(d[i], d[i + 1] + 1) }
            if y < h - 1 { d[i] = min(d[i], d[i + w] + 1); if x < w - 1 { d[i] = min(d[i], d[i + w + 1] + 1.414) }; if x > 0 { d[i] = min(d[i], d[i + w - 1] + 1.414) } }
        }
    }
    var deepest = [Float](repeating: 1, count: t.regions.count)
    for i in 0..<n { deepest[Int(map[i])] = max(deepest[Int(map[i])], d[i]) }
    let lead = Float(max(w, h)) * 0.0045
    var px = [UInt8](repeating: 255, count: n * 4)
    for i in 0..<n {
        let r = Int(map[i]), x = i % w, y = i / w
        var c: SIMD3<Float>
        if d[i] < lead {
            c = SIMD3(0.105, 0.098, 0.125)
        } else {
            let depth = min(1, (d[i] - lead) / max(2, deepest[r] - lead))
            let ripple = (sin(Float(x) * 0.07 + Float(r)) * sin(Float(y) * 0.023 + Float(r) * 1.7)) * 0.5 + 0.5
            let g = Int(glazing[r])
            if g >= 0, g < offered.count {
                let f = 0.72 + 0.36 * depth.squareRoot() + (ripple - 0.5) * 0.18
                c = offered[g].rgb * f + SIMD3(0.055, 0.047, 0.031) * depth
            } else {
                let hint = t.palette[Int(t.regions[r].colorIndex)].rgb
                c = (hint * 0.17 + SIMD3(0.12, 0.12, 0.16) * 0.83) * (0.75 + 0.5 * ripple * 0.5)
            }
        }
        let b = bytes(c)
        px[i * 4] = b.x; px[i * 4 + 1] = b.y; px[i * 4 + 2] = b.z
    }
    return RGBAImage(width: w, height: h, pixels: px, colorSpace: t.colorSpace)
}
