import Foundation
import PaintCore

/// A color's 8-bit channels, rounded to nearest and clamped to the gamut.
func bytes(_ rgb: SIMD3<Float>) -> SIMD3<UInt8> {
    let v = rgb.clamped(lowerBound: SIMD3(repeating: 0), upperBound: SIMD3(repeating: 1)) * 255
    return SIMD3(UInt8(v.x.rounded()), UInt8(v.y.rounded()), UInt8(v.z.rounded()))
}

/// Raster preview: each pixel painted with its region's palette color.
func paintedRaster(_ t: Template) -> RGBAImage {
    var px = [UInt8](repeating: 255, count: t.width * t.height * 4)
    let colors = t.palette.map { bytes($0.rgb) }
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
    let colors = t.palette.map { bytes($0.rgb * 0.7 + SIMD3(repeating: 0.3)) }
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
/// is open, the background's color runs into the object, ringed in red at each of the
/// report's `openings`.
func areasRaster(_ t: Template, openings: [[Int]]) -> RGBAImage {
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
        return bytes(rgb)
    }
    for i in 0..<(w * h) {
        let c = colors[labels[Int(t.regionMap.storage[i])]]
        px[i * 4] = c.x; px[i * 4 + 1] = c.y; px[i * 4 + 2] = c.z
    }
    forEachDrawnSegment(of: t) { a, b in
        rasterize(from: a, to: b, width: w, height: h) { x, y in
            let o = (y * w + x) * 4
            px[o] = 30; px[o + 1] = 26; px[o + 2] = 34
        }
    }
    for opening in openings {
        for dy in -14...14 {
            for dx in -14...14 where abs(dx * dx + dy * dy - 12 * 12) <= 12 {
                let x = opening[0] + dx, y = opening[1] + dy
                guard x >= 0, y >= 0, x < w, y < h else { continue }
                let o = (y * w + x) * 4
                px[o] = 255; px[o + 1] = 0; px[o + 2] = 0
            }
        }
    }
    return RGBAImage(width: w, height: h, pixels: px, colorSpace: t.colorSpace)
}

/// `image` as `name` in `dir`.
func writePPM(_ image: RGBAImage, _ name: String, in dir: URL) throws {
    try Netpbm.encodePPM(image).write(to: dir.appendingPathComponent(name))
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

/// A coloring book as Refine shows it over the painting, at `scale` × the canvas: every area in
/// its paint, the drawing (`RefineGestures.drawingLines`) in the sheet's ink, `inkWidth` canvas
/// units wide, then `marks` (canvas units) over it, each polyline in its color and width (a
/// single point a dot).
func bookRaster(
    _ t: Template, scale: Int = 2, inkWidth: Float = 1.2, marks: [(points: [SIMD2<Float>], rgb: SIMD3<Float>, width: Float)] = []
) -> RGBAImage {
    let w = t.width * scale, h = t.height * scale, s = Float(scale)
    var rgb = [SIMD3<Float>](repeating: .zero, count: w * h)
    let colors = t.palette.map(\.rgb)
    for y in 0..<h {
        for x in 0..<w { rgb[y * w + x] = colors[Int(t.regions[Int(t.regionMap[x / scale, y / scale])].colorIndex)] }
    }
    /// Blends `color` over the pixels within `width / 2` of each polyline, edges antialiased.
    func stroke(_ lines: [[SIMD2<Float>]], _ color: SIMD3<Float>, width: Float, opacity: Float = 1) {
        var cover = [Float](repeating: 0, count: w * h)
        let r = width * s / 2
        for line in lines {
            let pts = line.map { $0 * s }
            let segments = pts.count == 1 ? [(pts[0], pts[0])] : Array(zip(pts, pts.dropFirst()))
            for (a, b) in segments {
                let lo = pointwiseMin(a, b) - SIMD2(repeating: r + 1), hi = pointwiseMax(a, b) + SIMD2(repeating: r + 1)
                let ab = b - a, len2 = (ab * ab).sum()
                let x0 = max(Int(lo.x), 0), x1 = min(Int(hi.x), w - 1), y0 = max(Int(lo.y), 0), y1 = min(Int(hi.y), h - 1)
                guard x0 <= x1, y0 <= y1 else { continue }
                for y in y0...y1 {
                    for x in x0...x1 {
                        let p = SIMD2(Float(x) + 0.5, Float(y) + 0.5)
                        let t = len2 > 0 ? min(max(((p - a) * ab).sum() / len2, 0), 1) : 0
                        let d = p - (a + ab * t)
                        let c = min(max(r + 0.5 - (d * d).sum().squareRoot(), 0), 1)
                        if c > cover[y * w + x] { cover[y * w + x] = c }
                    }
                }
            }
        }
        for i in cover.indices where cover[i] > 0 { rgb[i] += (color - rgb[i]) * (cover[i] * opacity) }
    }
    let ink = SIMD3<Float>(0.118, 0.102, 0.133)  // `CanvasPalette.sheetInkSRGB`
    stroke(RefineGestures.drawingLines(of: t).map { $0.map { SIMD2(Float($0.x), Float($0.y)) } }, ink, width: inkWidth)
    for mark in marks { stroke([mark.points], mark.rgb, width: mark.width, opacity: 0.8) }
    var px = [UInt8](repeating: 255, count: w * h * 4)
    for i in rgb.indices {
        let c = bytes(rgb[i])
        px[i * 4] = c.x; px[i * 4 + 1] = c.y; px[i * 4 + 2] = c.z
    }
    return RGBAImage(width: w, height: h, pixels: px, colorSpace: t.colorSpace)
}
