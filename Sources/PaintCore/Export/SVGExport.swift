import Foundation

/// Renders a template as SVG — used for headless visual evaluation and for exporting a
/// resolution-independent printable template.
public enum SVGExport {
    public struct Options: Sendable {
        /// Fill regions with their palette color (a "finished painting" preview).
        public var painted: Bool = false
        /// Draw region boundaries.
        public var outlines: Bool = true
        /// Draw region numbers.
        public var numbers: Bool = true
        /// Outline stroke width in canvas units.
        public var strokeWidth: Float = 0.9
        public var outlineColor: String = "#9aa0a6"

        public init(painted: Bool = false, outlines: Bool = true, numbers: Bool = true) {
            self.painted = painted
            self.outlines = outlines
            self.numbers = numbers
        }
    }

    public static func render(_ t: Template, options: Options = Options()) -> String {
        var s = ""
        s.reserveCapacity(t.points.count * 24 + 4096)
        s += "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 \(t.width) \(t.height)\" width=\"\(t.width)\" height=\"\(t.height)\">\n"
        s += "<rect width=\"100%\" height=\"100%\" fill=\"#ffffff\"/>\n"

        func fmt(_ v: Float) -> String {
            let r = (v * 100).rounded() / 100
            return r == r.rounded() ? String(Int(r)) : String(r)
        }

        // Region fills.
        if !t.rings.isEmpty {
            s += "<g stroke=\"none\" fill-rule=\"evenodd\">\n"
            for (index, region) in t.regions.enumerated() {
                let fill = options.painted ? hex(t.palette[Int(region.colorIndex)].rgb) : "#ffffff"
                var d = ""
                for poly in t.polygons(ofRegion: index) where !poly.isEmpty {
                    d += "M\(fmt(poly[0].x)) \(fmt(poly[0].y))"
                    for p in poly.dropFirst() { d += "L\(fmt(p.x)) \(fmt(p.y))" }
                    d += "Z"
                }
                // A hairline of the same color hides anti-aliasing seams between fills.
                s += "<path d=\"\(d)\" fill=\"\(fill)\" stroke=\"\(fill)\" stroke-width=\"0.35\"/>\n"
            }
            s += "</g>\n"
        }

        if options.outlines && !t.edges.isEmpty {
            s += "<g fill=\"none\" stroke=\"\(options.outlineColor)\" stroke-width=\"\(options.strokeWidth)\" stroke-linejoin=\"round\" stroke-linecap=\"round\">\n"
            for e in t.edges where e.right != BoundaryEdge.outside {
                let pts = t.points(of: e)
                guard let first = pts.first else { continue }
                var d = "M\(fmt(first.x)) \(fmt(first.y))"
                for p in pts.dropFirst() { d += "L\(fmt(p.x)) \(fmt(p.y))" }
                s += "<path d=\"\(d)\"/>\n"
            }
            s += "</g>\n"
        }

        if options.numbers {
            s += "<g font-family=\"Helvetica, Arial, sans-serif\" text-anchor=\"middle\" dominant-baseline=\"central\" fill=\"#5f6368\">\n"
            for label in t.labels {
                let region = t.regions[Int(label.region)]
                let text = String(region.colorIndex + 1)
                let size = fontSize(forRadius: label.radius, digits: text.count)
                guard size >= 1.2 else { continue }
                s += "<text x=\"\(fmt(label.position.x))\" y=\"\(fmt(label.position.y))\" font-size=\"\(fmt(size))\">\(text)</text>\n"
            }
            s += "</g>\n"
        }
        s += "</svg>\n"
        return s
    }

    /// Font size (canvas units) whose glyph run fits inside a disc of `radius`.
    public static func fontSize(forRadius radius: Float, digits: Int) -> Float {
        // Digits are ~0.6em wide and ~0.72em tall (cap height); fit the run's bounding box
        // diagonal inside the disc with a little breathing room.
        let w = 0.6 * Float(digits), h: Float = 0.72
        let diag = (w * w + h * h).squareRoot()
        return min(2 * radius * 0.9 / diag, 60)
    }

    static func hex(_ rgb: SIMD3<Float>) -> String {
        func c(_ v: Float) -> String {
            let i = Int((min(max(v, 0), 1) * 255).rounded())
            let h = String(i, radix: 16)
            return h.count == 1 ? "0" + h : h
        }
        return "#" + c(rgb.x) + c(rgb.y) + c(rgb.z)
    }
}
