import Foundation
import PaintCore

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

/// Debug view of the areas a book's drawing encloses: every area in a color of its own (a
/// hashed hue, light where the area is one cell), the drawn edges in ink. Where a silhouette
/// is open, the background's color runs into the object.
func areasRaster(_ t: Template) -> RGBAImage {
    let labels = LineArtReport.enclosedAreaLabels(t)
    let counts = LineArtReport.areas(t, labels: labels)
    let w = t.width, h = t.height
    var px = [UInt8](repeating: 255, count: w * h * 4)
    let colors = counts.indices.map { label -> SIMD3<UInt8> in
        // Golden-angle hues: neighbouring labels get colors far apart.
        let hue = (Float(label) * 0.618_034).truncatingRemainder(dividingBy: 1)
        let single = counts[label].cells == 1
        let (s, v): (Float, Float) = single ? (0.25, 0.98) : (0.55, 0.9)
        let k = hue * 6, i = Int(k), f = k - Float(i)
        let p = v * (1 - s), q = v * (1 - s * f), u = v * (1 - s * (1 - f))
        let rgb: SIMD3<Float>
        switch i % 6 {
        case 0: rgb = SIMD3(v, u, p)
        case 1: rgb = SIMD3(q, v, p)
        case 2: rgb = SIMD3(p, v, u)
        case 3: rgb = SIMD3(p, q, v)
        case 4: rgb = SIMD3(u, p, v)
        default: rgb = SIMD3(v, p, q)
        }
        return SIMD3(UInt8((rgb.x * 255).rounded()), UInt8((rgb.y * 255).rounded()), UInt8((rgb.z * 255).rounded()))
    }
    for i in 0..<(w * h) {
        let c = colors[labels[Int(t.regionMap.storage[i])]]
        px[i * 4] = c.x; px[i * 4 + 1] = c.y; px[i * 4 + 2] = c.z
    }
    if let lines = t.lineArt, lines.edgeLayers.count == t.edges.count {
        func plot(_ p: SIMD2<Float>) {
            let x = Int(p.x.rounded()), y = Int(p.y.rounded())
            guard x >= 0, y >= 0, x < w, y < h else { return }
            let o = (y * w + x) * 4
            px[o] = 30; px[o + 1] = 26; px[o + 2] = 34
        }
        func segment(_ a: SIMD2<Float>, _ b: SIMD2<Float>) {
            let d = b - a
            let n = max(1, Int((d * d).sum().squareRoot().rounded(.up)))
            for s in 0...n { plot(a + d * (Float(s) / Float(n))) }
        }
        for (k, e) in t.edges.enumerated() where lines.edgeLayers[k] != LineLayer.color.rawValue {
            let pts = t.points(of: e)
            for j in pts.indices.dropFirst() { segment(pts[j - 1], pts[j]) }
        }
        for stroke in lines.strokes {
            let start = Int(stroke.pointStart), end = start + Int(stroke.pointCount)
            guard stroke.pointCount >= 2, end <= lines.strokePoints.count else { continue }
            for j in (start + 1)..<end { segment(lines.strokePoints[j - 1], lines.strokePoints[j]) }
        }
        // The openings (`LineArtReport.gaps`): a red ring around each.
        for opening in LineArtReport.gaps(t).openings {
            for dy in -14...14 {
                for dx in -14...14 where abs(dx * dx + dy * dy - 12 * 12) <= 12 {
                    let x = opening[0] + dx, y = opening[1] + dy
                    guard x >= 0, y >= 0, x < w, y < h else { continue }
                    let o = (y * w + x) * 4
                    px[o] = 255; px[o + 1] = 0; px[o + 2] = 0
                }
            }
        }
    }
    return RGBAImage(width: w, height: h, pixels: px, colorSpace: t.colorSpace)
}

/// painted.svg, template.svg, painted-outlined.svg and, for a template with line art,
/// selected.svg: the template with the cells of palette number `selected` hatched, as the
/// canvas shows the selected color.
func writeSVGs(_ t: Template, selected: Int? = nil, to outDir: URL) throws {
    try SVGExport.render(t, options: .init(painted: true, outlines: false, numbers: false))
        .write(to: outDir.appendingPathComponent("painted.svg"), atomically: true, encoding: .utf8)
    try SVGExport.render(t, options: .init(painted: false, outlines: true, numbers: true))
        .write(to: outDir.appendingPathComponent("template.svg"), atomically: true, encoding: .utf8)
    try SVGExport.render(t, options: .init(painted: true, outlines: true, numbers: false))
        .write(to: outDir.appendingPathComponent("painted-outlined.svg"), atomically: true, encoding: .utf8)
    if let selected, t.lineArt != nil {
        try SVGExport.render(t, options: .init(painted: false, outlines: true, numbers: true, selectedColor: selected - 1))
            .write(to: outDir.appendingPathComponent("selected.svg"), atomically: true, encoding: .utf8)
    }
}
