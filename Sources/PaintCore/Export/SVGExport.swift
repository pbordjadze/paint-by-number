import Foundation

/// Renders a template as SVG for headless evaluation (pbn writes it, `tools/eval.py`
/// rasterizes it). The app prints and shares through CoreGraphics (`PDFExporter`,
/// `TemplateRasterizer`), not SVG.
public enum SVGExport {
    public struct Options: Sendable {
        /// Fill regions with their palette color (a "finished painting" preview).
        public var painted: Bool = false
        /// Draw region boundaries (including the canvas border).
        public var outlines: Bool = true
        /// Draw region numbers.
        public var numbers: Bool = true
        /// A palette index whose unpainted regions show as the app shows the selected color's
        /// cells: a tint hatched (group `selection`), drawn over the fills and under the lines.
        /// A coloring book outlines nothing for being selected, so the hatch alone tells its
        /// cells apart; nil selects nothing.
        public var selectedColor: Int? = nil

        public init(painted: Bool = false, outlines: Bool = true, numbers: Bool = true, selectedColor: Int? = nil) {
            self.painted = painted
            self.outlines = outlines
            self.numbers = numbers
            self.selectedColor = selectedColor
        }
    }

    private static let outlineColor = "#9ea3aa"
    private static let numberColor = "#6d727a"
    private static let lineColor = "#2b2530"
    private static let selectionColor = "#7b3f7e"
    /// Largest number size as a fraction of the canvas' long side; big regions get several
    /// numbers of this size rather than one huge one. Numbers are sized by `LabelSizing` and
    /// never dropped: none is smaller than `LabelSizing.minimumFontSize`.
    private static let maxNumberSize: Float = 1.0 / 64
    /// A coloring book's line, as a factor on the outline width: the app draws it three times
    /// as heavy as a classic line with the painting fitted to the screen.
    private static let coloringBookWidth: Float = 3

    /// How a layered template draws a `LineLayer`: its group's name, its absolute ink opacity
    /// and a factor on the outline width, as pbn's SVGs and eval sheets draw them. The app's
    /// `LineAppearance` uses other units (fractions of the paper's full ink) and is not read here.
    private static func lineLook(of layer: LineLayer) -> (name: String, opacity: Float, width: Float) {
        switch layer {
        case .outline: ("outline", 0.85, 1.15)
        case .detail: ("detail", 0.45, 0.9)
        case .texture: ("texture", 0.2, 0.75)
        case .color: ("color", 0.12, 0.7)
        }
    }

    /// Layered templates (`Template.lineArt`) draw each `LineLayer` as a group (`lines-outline`,
    /// `lines-detail`, `lines-texture`, `lines-color`, faintest first) of its edges and interior
    /// strokes. A coloring book draws its drawn layers alike as one group (`lines-drawing`) in
    /// solid ink, three times the outline width, and no color edges, as the app does.
    public static func render(_ t: Template, options: Options = Options()) -> String {
        var s = ""
        s.reserveCapacity(t.points.count * 16 + t.labels.count * 96 + 4096)
        s += "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 \(t.width) \(t.height)\" width=\"\(t.width)\" height=\"\(t.height)\">\n"
        s += "<rect width=\"100%\" height=\"100%\" fill=\"#ffffff\"/>\n"

        if options.painted && !t.rings.isEmpty {
            // Fills tile the canvas exactly, but anti-aliased rasterizers composite each
            // edge pixel's partial coverage of both neighbours over the background, which
            // leaves faint light seams. A hairline of the fill color (constant in screen
            // pixels, so it never grows with zoom) covers them.
            s += "<g fill-rule=\"evenodd\" stroke-width=\"0.6\" stroke-linejoin=\"round\">\n"
            for index in t.regions.indices {
                let color = "#" + t.palette[Int(t.regions[index].colorIndex)].hexDigits
                var d = ""
                for poly in t.polygons(ofRegion: index) { appendPath(&d, poly, closed: true) }
                s += "<path d=\"\(d)\" fill=\"\(color)\" stroke=\"\(color)\" vector-effect=\"non-scaling-stroke\"/>\n"
            }
            s += "</g>\n"
        }

        if let selected = options.selectedColor, t.palette.indices.contains(selected), !t.rings.isEmpty {
            // Diagonal hatching a few canvas units apart, like the canvas's highlight of the
            // selected color's unpainted cells; a hairline of the tint covers the seams.
            let spacing = max(4, Float(max(t.width, t.height)) / 160)
            let hatch = (spacing / 4 * 100).rounded() / 100, tint = selectionColor
            s += "<defs><pattern id=\"hatch\" patternUnits=\"userSpaceOnUse\" width=\"\(fmt(spacing))\" height=\"\(fmt(spacing))\" patternTransform=\"rotate(45)\">"
            s += "<rect width=\"\(fmt(spacing))\" height=\"\(fmt(spacing))\" fill=\"\(tint)\" fill-opacity=\"0.12\"/>"
            s += "<line x1=\"0\" y1=\"0\" x2=\"0\" y2=\"\(fmt(spacing))\" stroke=\"\(tint)\" stroke-width=\"\(fmt(hatch))\"/></pattern></defs>\n"
            var d = ""
            for index in t.regions.indices where Int(t.regions[index].colorIndex) == selected {
                for poly in t.polygons(ofRegion: index) { appendPath(&d, poly, closed: true) }
            }
            if !d.isEmpty {
                s += "<g id=\"selection\" fill-rule=\"evenodd\"><path d=\"\(d)\" fill=\"url(#hatch)\" stroke=\"\(tint)\" stroke-opacity=\"0.12\" stroke-width=\"0.6\" vector-effect=\"non-scaling-stroke\"/></g>\n"
            }
        }

        // About 0.1 mm lines on a printed page.
        let width = max(0.5, Float(max(t.width, t.height)) / 1900)
        if options.outlines, let lines = t.lineArt, lines.edgeLayers.count == t.edges.count {
            // The groups drawn, faintest first: every layer on its own, or a coloring book's drawn
            // layers together.
            let groups: [(name: String, layers: [UInt8], opacity: Float, width: Float)]
            switch lines.style {
            case .layered:
                groups = LineLayer.allCases.reversed().map { layer in
                    let look = lineLook(of: layer)
                    return (look.name, [layer.rawValue], look.opacity, look.width)
                }
            case .coloringBook:
                let drawn = LineLayer.allCases.filter { $0 != .color }.map(\.rawValue)
                groups = [("drawing", drawn, 1, coloringBookWidth)]
            }
            for group in groups {
                var d = ""
                for (k, e) in t.edges.enumerated() where group.layers.contains(lines.edgeLayers[k]) {
                    appendPath(&d, t.points(of: e), closed: false)
                }
                for stroke in lines.strokes where group.layers.contains(stroke.layer) {
                    let start = Int(stroke.pointStart), end = start + Int(stroke.pointCount)
                    guard stroke.pointCount >= 2, end <= lines.strokePoints.count else { continue }
                    appendPath(&d, lines.strokePoints[start..<end], closed: false)
                }
                guard !d.isEmpty else { continue }
                s += "<g id=\"lines-\(group.name)\" opacity=\"\(fmt(group.opacity))\">"
                s += "<path d=\"\(d)\" fill=\"none\" stroke=\"\(lineColor)\" stroke-width=\"\(fmt(width * group.width))\" stroke-linejoin=\"round\" stroke-linecap=\"round\"/></g>\n"
            }
        } else if options.outlines && !t.edges.isEmpty {
            var d = ""
            for e in t.edges { appendPath(&d, t.points(of: e), closed: false) }
            s += "<path d=\"\(d)\" fill=\"none\" stroke=\"\(outlineColor)\" stroke-width=\"\(fmt(width))\" stroke-linejoin=\"round\" stroke-linecap=\"round\"/>\n"
        }

        if options.numbers {
            let maxSize = maxNumberSize * Float(max(t.width, t.height))
            s += "<g font-family=\"Helvetica Neue, Helvetica, Arial, DejaVu Sans, sans-serif\" text-anchor=\"middle\" dominant-baseline=\"central\" fill=\"\(numberColor)\">\n"
            for label in t.labels {
                let text = String(t.regions[Int(label.region)].colorIndex + 1)
                let size = LabelSizing.fontSize(radius: label.radius, digits: text.count, maximum: maxSize)
                s += "<text x=\"\(fmt(label.position.x))\" y=\"\(fmt(label.position.y))\" font-size=\"\(fmt(size))\">\(text)</text>\n"
            }
            s += "</g>\n"
        }
        s += "</svg>\n"
        return s
    }

    static func fmt(_ v: Float) -> String {
        let r = (v * 100).rounded() / 100
        return r == r.rounded() ? String(Int(r)) : String(r)
    }

    static func fmt(_ p: SIMD2<Float>) -> String { fmt(p.x) + " " + fmt(p.y) }

    /// Path data for `points`: `M` the first, `L` each further one, `Z` when closed; nothing
    /// for an empty sequence.
    private static func appendPath(_ d: inout String, _ points: some Sequence<SIMD2<Float>>, closed: Bool) {
        var first = true
        for p in points {
            d += (first ? "M" : "L") + fmt(p)
            first = false
        }
        if closed && !first { d += "Z" }
    }
}
