import PaintCore

/// What the show reads of the finished template: the lines of its drawing, which the ink step draws
/// and the last step relaxes, and where its numbers go, in pixels of the snapshots' picture.
///
/// Positions are the SVG's (`SVGExport.render`, which `making_of_inputs.py` parses): a canvas unit
/// rounded to 0.01, then scaled by the picture's width over the canvas's. The strokes are
/// the drawing's lines in the SVG's order, the edges that are drawn and then the strokes inside
/// cells; a template without line art (a classic one) draws every edge.
///
/// A picture is the canvas cut down to whole pixels (the snapshots' sizes round down), so a point on
/// the canvas's far edge can sit up to a pixel past the picture's last row or column: whoever
/// turns a point into a pixel clamps it, and nothing resizes.
public struct ShowTemplate: Sendable, Equatable {
    public struct Number: Sendable, Equatable {
        public var x: Double
        public var y: Double
        /// The font size, which says how much room the number takes.
        public var size: Double

        public init(x: Double, y: Double, size: Double) {
            self.x = x
            self.y = y
            self.size = size
        }
    }

    /// The size of the picture the points are in.
    public let width: Int
    public let height: Int
    /// The picture's width over the canvas's.
    public let scale: Double
    /// The drawing's lines, each of two points or more.
    public let strokes: [Polyline]
    /// One per label of the template, in its order.
    public let numbers: [Number]
    /// The width a line is drawn at, in picture pixels.
    public let lineWidth: Double

    // SVGExport's: a number is at most 1/64 of the canvas's long side, a line is 1/1900 of it with
    // a floor, and a coloring book draws it three times as heavy. `ShowTemplateTests` compares
    // all of it with the SVG itself.
    private static let maxNumberSize: Float = 1.0 / 64
    private static let lineWidthDivisor: Float = 1900
    private static let bookWidth: Float = 3

    public init(_ t: Template, width: Int, height: Int) {
        self.width = width
        self.height = height
        let scale = t.width > 0 ? Double(width) / Double(t.width) : 1
        self.scale = scale
        // The SVG prints a coordinate to 0.01 (`SVGExport.fmt`), and the show reads what it printed.
        func printed(_ v: Float) -> Double { Double((v * 100).rounded()) / 100 }
        func scaled(_ points: some Sequence<SIMD2<Float>>) -> Polyline {
            Polyline(points.map { Point(printed($0.x) * scale, printed($0.y) * scale) })
        }

        var strokes: [Polyline] = []
        let plain = Float(max(t.width, t.height)) / Self.lineWidthDivisor
        var lineWidth = max(0.5, plain)
        if let lines = t.lineArt, lines.edgeLayers.count == t.edges.count {
            lineWidth *= Self.bookWidth
            let drawn = { (layer: UInt8) in layer != LineLayer.color.rawValue }
            for (k, edge) in t.edges.enumerated() where drawn(lines.edgeLayers[k]) && edge.pointCount >= 2 {
                strokes.append(scaled(t.points(of: edge)))
            }
            for stroke in lines.strokes where drawn(stroke.layer) && stroke.pointCount >= 2 {
                let start = Int(stroke.pointStart), end = start + Int(stroke.pointCount)
                guard end <= lines.strokePoints.count else { continue }
                strokes.append(scaled(lines.strokePoints[start..<end]))
            }
        } else {
            for edge in t.edges where edge.pointCount >= 2 { strokes.append(scaled(t.points(of: edge))) }
        }
        self.strokes = strokes
        self.lineWidth = printed(lineWidth) * scale

        let maxSize = Self.maxNumberSize * Float(max(t.width, t.height))
        numbers = t.labels.map { label in
            let region = Int(label.region)
            let digits = String(t.regions[region].colorIndex + 1).count
            let size = LabelSizing.fontSize(radius: label.radius, digits: digits, maximum: maxSize, detail: t.isDetailRegion(region))
            return Number(x: printed(label.position.x) * scale, y: printed(label.position.y) * scale, size: printed(size) * scale)
        }
    }
}
