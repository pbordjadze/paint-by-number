import CoreGraphics
import CoreText
import Foundation
import PaintCore
import simd

/// CoreGraphics rendering of a template and its progress: gallery thumbnails, share
/// images, create-flow previews and PDF pages. No Metal, safe off the main actor.
///
/// Uses the template's vector geometry when present (crisp at any size, vector in PDFs)
/// and otherwise samples the raster region map.
nonisolated enum TemplateRasterizer {
    struct Style: Sendable {
        enum Unpainted: Sendable, Equatable {
            /// Plain paper.
            case paper
            /// A pale grey at the region's final lightness, like a pencil study of the
            /// picture, so partly painted thumbnails stay recognizable.
            case sketch
        }

        var unpainted: Unpainted = .paper
        /// Render every region painted (the finished picture).
        var paintAll = false
        /// Outline width in output pixels (points for PDF); 0 disables outlines.
        var outlineWidth: CGFloat = 1
        /// Encoded RGBA in the template's color space.
        var outlineColor = SIMD4<Float>(0.52, 0.54, 0.57, 1)
        /// Omit outlines between two painted regions so finished areas read as paint.
        var hidesOutlinesBetweenPainted = true
        var numbers = false
        var numberColor = SIMD4<Float>(0.38, 0.40, 0.43, 1)
        /// Numbers smaller than this (output pixels/points) are left out.
        var minimumNumberSize: CGFloat = 5
        var paper = SIMD3<Float>(1, 1, 1)

        /// Gallery thumbnails: painted regions in color, the rest a faint sketch.
        static let thumbnail = Style(
            unpainted: .sketch, outlineWidth: 0.9, outlineColor: SIMD4(0.45, 0.46, 0.49, 0.28))
        /// The finished painting, with a whisper of the lines it was painted in.
        static let finished = Style(
            paintAll: true, outlineWidth: 0.8, outlineColor: SIMD4(0.2, 0.2, 0.22, 0.10),
            hidesOutlinesBetweenPainted: false)
        /// Painted preview without any lines (create flow).
        static let painting = Style(paintAll: true, outlineWidth: 0)
        /// Outlines with numbers on paper, as the user will start painting it.
        static let template = Style(outlineWidth: 1, numbers: true, minimumNumberSize: 4.5)
        /// Printable template (PDF): hairlines and small numbers.
        static let printable = Style(
            outlineWidth: 0.4, outlineColor: SIMD4(0.45, 0.47, 0.5, 1), numbers: true,
            numberColor: SIMD4(0.35, 0.37, 0.4, 1), minimumNumberSize: 2.6)
    }

    // MARK: Entry points

    /// Pixel size of a render whose long side is `maxPixelSize`, keeping the template's aspect.
    static func pixelSize(of t: Template, maxPixelSize: Int) -> (width: Int, height: Int) {
        let long = max(t.width, t.height)
        let scale = Double(maxPixelSize) / Double(max(1, long))
        return (max(1, Int((Double(t.width) * scale).rounded())), max(1, Int((Double(t.height) * scale).rounded())))
    }

    /// Renders to an image whose long side is `maxPixelSize` pixels.
    /// - Parameter painted: Painted flag per region (`PaintProgress.painted`); nil = none.
    static func image(_ t: Template, painted: [Bool]? = nil, style: Style, maxPixelSize: Int) -> CGImage? {
        let size = pixelSize(of: t, maxPixelSize: maxPixelSize)
        guard let ctx = makeContext(width: size.width, height: size.height, colorSpace: t.colorSpace) else { return nil }
        draw(t, painted: painted, style: style, in: ctx, rect: CGRect(x: 0, y: 0, width: size.width, height: size.height))
        return ctx.makeImage()
    }

    static func pngData(_ t: Template, painted: [Bool]? = nil, style: Style, maxPixelSize: Int) -> Data? {
        image(t, painted: painted, style: style, maxPixelSize: maxPixelSize).flatMap(ImageCodec.pngData)
    }

    /// A bitmap context whose user space is y-down (origin top-left), like canvas units.
    static func makeContext(width: Int, height: Int, colorSpace: RGBColorSpace) -> CGContext? {
        guard let ctx = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: cgColorSpace(colorSpace), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: 1, y: -1)
        ctx.interpolationQuality = .high
        return ctx
    }

    /// Draws the template into `rect` of a y-down context (bitmap or PDF page).
    /// - Parameter rasterResolution: Pixel size used for the region-map fallback; defaults
    ///   to the device size of `rect`.
    static func draw(
        _ t: Template, painted: [Bool]?, style: Style, in ctx: CGContext, rect: CGRect,
        rasterResolution: CGSize? = nil
    ) {
        guard t.width > 0, t.height > 0, rect.width > 0, rect.height > 0 else { return }
        let flags = resolvedPainted(t, painted: painted, style: style)
        let scale = min(rect.width / CGFloat(t.width), rect.height / CGFloat(t.height))
        let deviceSize = rasterResolution ?? ctx.convertToDeviceSpace(rect).standardized.size

        ctx.saveGState()
        ctx.clip(to: rect)
        ctx.setFillColor(cgColor(SIMD4(style.paper, 1), space: t.colorSpace))
        ctx.fill(rect)
        ctx.translateBy(x: rect.minX, y: rect.minY)
        ctx.scaleBy(x: rect.width / CGFloat(t.width), y: rect.height / CGFloat(t.height))

        if t.rings.isEmpty {
            drawRegionMap(t, painted: flags, style: style, in: ctx, resolution: deviceSize)
        } else {
            drawVectorFills(t, painted: flags, style: style, in: ctx, scale: scale)
            if style.outlineWidth > 0 { drawVectorOutlines(t, painted: flags, style: style, in: ctx, scale: scale) }
        }
        if style.numbers { drawNumbers(t, painted: flags, style: style, in: ctx, scale: scale) }
        ctx.restoreGState()
    }

    // MARK: Colors

    static func cgColorSpace(_ space: RGBColorSpace) -> CGColorSpace {
        CGColorSpace(name: space == .displayP3 ? CGColorSpace.displayP3 : CGColorSpace.sRGB)!
    }

    static func cgColor(_ rgba: SIMD4<Float>, space: RGBColorSpace) -> CGColor {
        let components = [CGFloat(rgba.x), CGFloat(rgba.y), CGFloat(rgba.z), CGFloat(rgba.w)]
        return CGColor(colorSpace: cgColorSpace(space), components: components)
            ?? CGColor(red: components[0], green: components[1], blue: components[2], alpha: components[3])
    }

    /// The pale grey standing in for an unpainted region in `.sketch` mode.
    static func sketchColor(_ color: PaletteColor) -> SIMD3<Float> {
        let lightness = min(max(color.oklab.x, 0), 1)
        return SIMD3(repeating: 0.76 + 0.22 * lightness)
    }

    private static func resolvedPainted(_ t: Template, painted: [Bool]?, style: Style) -> [Bool] {
        if style.paintAll { return [Bool](repeating: true, count: t.regions.count) }
        guard let painted, painted.count == t.regions.count else { return [Bool](repeating: false, count: t.regions.count) }
        return painted
    }

    /// Fill of a region, or nil when it shows the paper.
    private static func fill(of region: Int, _ t: Template, painted: [Bool], style: Style) -> SIMD3<Float>? {
        let color = t.palette[Int(t.regions[region].colorIndex)]
        if painted[region] { return color.rgb }
        return style.unpainted == .sketch ? sketchColor(color) : nil
    }

    // MARK: Vector path

    private static func drawVectorFills(_ t: Template, painted: [Bool], style: Style, in ctx: CGContext, scale: CGFloat) {
        // One even-odd path per distinct fill. Regions never overlap, so even-odd over a
        // union of regions (outer rings + holes) fills exactly those regions.
        let paletteCount = t.palette.count
        var paths = [CGMutablePath?](repeating: nil, count: paletteCount * 2)
        for index in t.regions.indices {
            let color = Int(t.regions[index].colorIndex)
            let key: Int
            if painted[index] {
                key = color
            } else if style.unpainted == .sketch {
                key = paletteCount + color
            } else {
                continue
            }
            let path = paths[key] ?? CGMutablePath()
            for polygon in t.polygons(ofRegion: index) where polygon.count >= 3 {
                path.move(to: CGPoint(polygon[0]))
                for p in polygon.dropFirst() { path.addLine(to: CGPoint(p)) }
                path.closeSubpath()
            }
            paths[key] = path
        }
        // A hairline in the fill color closes anti-aliasing seams between neighbours.
        let seam = 0.7 / max(scale, 0.0001)
        ctx.setLineJoin(.round)
        ctx.setLineWidth(seam)
        for (key, path) in paths.enumerated() {
            guard let path else { continue }
            let rgb = key < paletteCount ? t.palette[key].rgb : sketchColor(t.palette[key - paletteCount])
            let color = cgColor(SIMD4(rgb, 1), space: t.colorSpace)
            ctx.setFillColor(color)
            ctx.setStrokeColor(color)
            ctx.addPath(path)
            ctx.drawPath(using: .eoFillStroke)
        }
    }

    private static func drawVectorOutlines(_ t: Template, painted: [Bool], style: Style, in ctx: CGContext, scale: CGFloat) {
        let path = CGMutablePath()
        for edge in t.edges where edge.right != BoundaryEdge.outside {
            if style.hidesOutlinesBetweenPainted && painted[Int(edge.left)] && painted[Int(edge.right)] { continue }
            let points = t.points(of: edge)
            guard let first = points.first else { continue }
            path.move(to: CGPoint(first))
            for p in points.dropFirst() { path.addLine(to: CGPoint(p)) }
        }
        ctx.setStrokeColor(cgColor(style.outlineColor, space: t.colorSpace))
        ctx.setLineWidth(style.outlineWidth / max(scale, 0.0001))
        ctx.setLineJoin(.round)
        ctx.setLineCap(.round)
        ctx.addPath(path)
        ctx.strokePath()
    }

    // MARK: Region-map fallback

    /// Rasterizes the region map (used while a template has no vector geometry). Renders
    /// at the larger of the template and output resolution, so downscaled thumbnails get
    /// filtered and enlarged exports keep 1-pixel outlines.
    private static func drawRegionMap(_ t: Template, painted: [Bool], style: Style, in ctx: CGContext, resolution: CGSize) {
        let outW = Int(resolution.width.rounded()), outH = Int(resolution.height.rounded())
        let w = min(max(t.width, outW), 8192), h = min(max(t.height, outH), 8192)
        guard let image = regionMapImage(t, painted: painted, style: style, width: w, height: h) else { return }
        ctx.saveGState()
        // Images draw y-up; undo the y-down flip locally.
        ctx.translateBy(x: 0, y: CGFloat(t.height))
        ctx.scaleBy(x: 1, y: -1)
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: t.width, height: t.height))
        ctx.restoreGState()
    }

    static func regionMapImage(_ t: Template, painted: [Bool], style: Style, width w: Int, height h: Int) -> CGImage? {
        func pack(_ rgb: SIMD3<Float>) -> UInt32 {
            let c = (rgb.clamped(lowerBound: .zero, upperBound: SIMD3(repeating: 1)) * 255).rounded(.toNearestOrAwayFromZero)
            return UInt32(c.x) | UInt32(c.y) << 8 | UInt32(c.z) << 16 | 0xFF00_0000
        }
        let fills = t.regions.indices.map { fill(of: $0, t, painted: painted, style: style) ?? style.paper }
        let outline = style.outlineColor
        let alpha = style.outlineWidth > 0 ? outline.w * Float(min(style.outlineWidth, 1)) : 0
        let colors = fills.map(pack)
        let outlined = fills.map { pack($0 * (1 - alpha) + SIMD3(outline.x, outline.y, outline.z) * alpha) }
        let hides = style.hidesOutlinesBetweenPainted
        let xs = (0..<w).map { min(t.width - 1, Int((Double($0) + 0.5) * Double(t.width) / Double(w))) }
        let ys = (0..<h).map { min(t.height - 1, Int((Double($0) + 0.5) * Double(t.height) / Double(h))) }

        var pixels = [UInt32](repeating: 0, count: w * h)
        pixels.withUnsafeMutableBufferPointer { out in
            t.regionMap.storage.withUnsafeBufferPointer { map in
                for y in 0..<h {
                    let row = ys[y] * t.width
                    let below = (y + 1 < h ? ys[y + 1] : ys[y]) * t.width
                    for x in 0..<w {
                        let r = Int(map[row + xs[x]])
                        var boundary = false
                        if alpha > 0 {
                            let right = x + 1 < w ? Int(map[row + xs[x + 1]]) : r
                            let down = Int(map[below + xs[x]])
                            boundary = (right != r && !(hides && painted[r] && painted[right]))
                                || (down != r && !(hides && painted[r] && painted[down]))
                        }
                        out[y * w + x] = boundary ? outlined[r] : colors[r]
                    }
                }
            }
        }
        let data = pixels.withUnsafeBytes { Data($0) }
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }
        return CGImage(
            width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
            space: cgColorSpace(t.colorSpace),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

    // MARK: Numbers

    /// Reference size the number glyph runs are laid out at, then scaled per label.
    private static let referenceFontSize: CGFloat = 100

    private static func drawNumbers(_ t: Template, painted: [Bool], style: Style, in ctx: CGContext, scale: CGFloat) {
        let font = CTFontCreateUIFontForLanguage(.system, referenceFontSize, nil)
            ?? CTFontCreateWithName("Helvetica" as CFString, referenceFontSize, nil)
        let capHeight = CTFontGetCapHeight(font)
        var lines: [Int: (line: CTLine, width: CGFloat)] = [:]
        func line(for number: Int) -> (line: CTLine, width: CGFloat) {
            if let cached = lines[number] { return cached }
            let attributes: [NSAttributedString.Key: Any] = [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true,
            ]
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: String(number), attributes: attributes))
            let entry = (line, CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil)))
            lines[number] = entry
            return entry
        }

        ctx.saveGState()
        ctx.setFillColor(cgColor(style.numberColor, space: t.colorSpace))
        // y-down user space: flip glyphs upright.
        ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        for label in t.labels {
            let region = Int(label.region)
            guard region < painted.count, !painted[region] else { continue }
            let number = Int(t.regions[region].colorIndex) + 1
            let size = CGFloat(SVGExport.fontSize(forRadius: label.radius, digits: number < 10 ? 1 : 2))
            guard size * scale >= style.minimumNumberSize else { continue }
            let run = line(for: number)
            let s = size / referenceFontSize
            ctx.saveGState()
            ctx.translateBy(x: CGFloat(label.position.x), y: CGFloat(label.position.y))
            ctx.scaleBy(x: s, y: s)
            ctx.textPosition = CGPoint(x: -run.width / 2, y: capHeight / 2)
            CTLineDraw(run.line, ctx)
            ctx.restoreGState()
        }
        ctx.restoreGState()
    }
}

nonisolated extension CGPoint {
    init(_ p: SIMD2<Float>) { self.init(x: CGFloat(p.x), y: CGFloat(p.y)) }
}
