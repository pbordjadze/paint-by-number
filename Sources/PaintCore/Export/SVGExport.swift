import Foundation

/// Renders a template as SVG — used for headless visual evaluation and for exporting a
/// resolution-independent printable template.
public enum SVGExport {
    public struct Options: Sendable {
        /// Fill regions with their palette color (a "finished painting" preview).
        public var painted: Bool = false
        /// Draw region boundaries (including the canvas border).
        public var outlines: Bool = true
        /// Draw region numbers.
        public var numbers: Bool = true
        /// Outline stroke width in canvas units; `nil` derives it from the canvas size so a
        /// printed page gets ~0.1 mm lines.
        public var strokeWidth: Float? = nil
        public var outlineColor: String = "#9ea3aa"
        public var numberColor: String = "#6d727a"
        /// Largest number size as a fraction of the canvas' long side; big regions get
        /// several numbers of this size rather than one huge one. Numbers are sized by
        /// `LabelSizing` and never dropped: none is smaller than `LabelSizing.minimumFontSize`.
        public var maxNumberSize: Float = 1.0 / 64
        /// Layered templates (`Template.lineArt`): each `LineLayer` is a group (`lines-outline`,
        /// `lines-detail`, `lines-texture`, `lines-color`, drawn faintest first) of its edges and
        /// interior strokes in `lineColor`, at its style's opacity and width (a factor on the
        /// outline width), indexed by `LineLayer` raw value.
        public var layerStyles: [LayerStyle] = SVGExport.defaultLayerStyles
        public var lineColor: String = "#2b2530"

        public init(painted: Bool = false, outlines: Bool = true, numbers: Bool = true) {
            self.painted = painted
            self.outlines = outlines
            self.numbers = numbers
        }
    }

    public struct LayerStyle: Sendable, Equatable {
        public var opacity: Float
        public var width: Float

        public init(opacity: Float, width: Float) {
            self.opacity = opacity
            self.width = width
        }
    }

    /// The app's default line appearance with the painting fitted to the screen.
    public static let defaultLayerStyles = [
        LayerStyle(opacity: 0.85, width: 1.15), LayerStyle(opacity: 0.45, width: 0.9),
        LayerStyle(opacity: 0.2, width: 0.75), LayerStyle(opacity: 0.12, width: 0.7),
    ]

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
                let color = hex(t.palette[Int(t.regions[index].colorIndex)].rgb)
                var d = ""
                for poly in t.polygons(ofRegion: index) where !poly.isEmpty {
                    d += "M" + fmt(poly[0])
                    for p in poly.dropFirst() { d += "L" + fmt(p) }
                    d += "Z"
                }
                s += "<path d=\"\(d)\" fill=\"\(color)\" stroke=\"\(color)\" vector-effect=\"non-scaling-stroke\"/>\n"
            }
            s += "</g>\n"
        }

        if options.outlines, let lines = t.lineArt, lines.edgeLayers.count == t.edges.count {
            let width = options.strokeWidth ?? max(0.5, Float(max(t.width, t.height)) / 1900)
            let names = ["outline", "detail", "texture", "color"]
            for layer in LineLayer.allCases.reversed() {
                let style = options.layerStyles.indices.contains(Int(layer.rawValue))
                    ? options.layerStyles[Int(layer.rawValue)] : LayerStyle(opacity: 1, width: 1)
                var d = ""
                for (k, e) in t.edges.enumerated() where lines.edgeLayers[k] == layer.rawValue {
                    let pts = t.points(of: e)
                    guard let first = pts.first else { continue }
                    d += "M" + fmt(first)
                    for p in pts.dropFirst() { d += "L" + fmt(p) }
                }
                for stroke in lines.strokes where stroke.layer == layer.rawValue {
                    let start = Int(stroke.pointStart), end = start + Int(stroke.pointCount)
                    guard stroke.pointCount >= 2, end <= lines.strokePoints.count else { continue }
                    d += "M" + fmt(lines.strokePoints[start])
                    for p in lines.strokePoints[(start + 1)..<end] { d += "L" + fmt(p) }
                }
                guard !d.isEmpty else { continue }
                s += "<g id=\"lines-\(names[Int(layer.rawValue)])\" opacity=\"\(fmt(style.opacity))\">"
                s += "<path d=\"\(d)\" fill=\"none\" stroke=\"\(options.lineColor)\" stroke-width=\"\(fmt(width * style.width))\" stroke-linejoin=\"round\" stroke-linecap=\"round\"/></g>\n"
            }
        } else if options.outlines && !t.edges.isEmpty {
            let width = options.strokeWidth ?? max(0.5, Float(max(t.width, t.height)) / 1900)
            var d = ""
            for e in t.edges {
                let pts = t.points(of: e)
                guard let first = pts.first else { continue }
                d += "M" + fmt(first)
                for p in pts.dropFirst() { d += "L" + fmt(p) }
            }
            s += "<path d=\"\(d)\" fill=\"none\" stroke=\"\(options.outlineColor)\" stroke-width=\"\(fmt(width))\" stroke-linejoin=\"round\" stroke-linecap=\"round\"/>\n"
        }

        if options.numbers {
            let maxSize = options.maxNumberSize * Float(max(t.width, t.height))
            s += "<g font-family=\"Helvetica Neue, Helvetica, Arial, DejaVu Sans, sans-serif\" text-anchor=\"middle\" dominant-baseline=\"central\" fill=\"\(options.numberColor)\">\n"
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

    static func hex(_ rgb: SIMD3<Float>) -> String {
        func c(_ v: Float) -> String {
            let i = Int((min(max(v, 0), 1) * 255).rounded())
            let h = String(i, radix: 16)
            return h.count == 1 ? "0" + h : h
        }
        return "#" + c(rgb.x) + c(rgb.y) + c(rgb.z)
    }
}
