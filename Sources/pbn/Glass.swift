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
        fail("usage: pbn glass <photo> <lines.json | suggest> --out <dir> [generate options]")
    }
    let photo = loadImage(options.positional[0])
    let outDir = URL(fileURLWithPath: out)
    try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
    let size = options.settings.workingSize(sourceWidth: photo.width, sourceHeight: photo.height)
    let lines: [[SIMD2<Float>]]
    if options.positional[1] == "suggest" {
        // The lead the photo suggests (`GlassLeadSuggestion`), as the Lead screen starts with.
        let start = Date()
        lines = try GlassLeadSuggestion.lines(photo: photo, width: size.width, height: size.height)
        FileHandle.standardError.write("suggested \(lines.count) lines in \(String(format: "%.2f", Date().timeIntervalSince(start))) s\n".data(using: .utf8)!)
    } else {
        guard let data = FileManager.default.contents(atPath: options.positional[1]) else { fail("cannot read \(options.positional[1])") }
        let script: GlassScript
        do { script = try JSONDecoder().decode(GlassScript.self, from: data) } catch { fail("cannot decode \(options.positional[1]): \(error)") }
        lines = script.lines.map { line in
            line.compactMap { p in p.count == 2 ? SIMD2(p[0] * Float(size.width), p[1] * Float(size.height)) : nil }
        }
    }
    let laying = Date()
    let window: GlassWindow.Leaded
    do {
        window = try GlassWindow.leaded(photo: photo, width: size.width, height: size.height, colorSpace: photo.colorSpace, lines: lines,
                                    joining: Float(max(size.width, size.height)) * GlassLeadSuggestion.joining)
    } catch { fail("no window: \(error)") }
    FileHandle.standardError.write("leaded in \(String(format: "%.2f", Date().timeIntervalSince(laying))) s\n".data(using: .utf8)!)
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

/// The window as glass: each piece's glass as the app draws it (`GlassTexture`: a glazed piece
/// lit, brighter toward its middle and streaked, one not glazed dark with a hint of its suggested
/// glass), and lead along every boundary and the frame.
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
    let lead = Float(max(w, h)) * 0.006
    // The glass as the app shows it (`GlassTexture`), the lead over it.
    let colors = t.regions.indices.map { r -> SIMD3<Float> in
        let g = Int(glazing[r])
        return g >= 0 && g < offered.count ? offered[g].rgb : t.palette[Int(t.regions[r].colorIndex)].rgb
    }
    let lit = t.regions.indices.map { r in Int(glazing[r]) >= 0 && Int(glazing[r]) < offered.count }
    let glass = GlassTexture(template: t).pixels(colors: colors, lit: lit)
    var px = [UInt8](repeating: 255, count: n * 4)
    for i in 0..<n {
        let c = d[i] < lead ? SIMD3<Float>(0.07, 0.066, 0.08)
            : SIMD3(Float(glass[i * 4]), Float(glass[i * 4 + 1]), Float(glass[i * 4 + 2])) / 255
        let b = bytes(c)
        px[i * 4] = b.x; px[i * 4 + 1] = b.y; px[i * 4 + 2] = b.z
    }
    return RGBAImage(width: w, height: h, pixels: px, colorSpace: t.colorSpace)
}
