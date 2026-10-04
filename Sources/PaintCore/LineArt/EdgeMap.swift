/// Edge strength per pixel (0 = none … 255 = certain), the input of layered line art. The app
/// computes it from its line-drawing and HED models (`combined(drawing:contours:)`); `pbn`
/// reads it from a PGM (`--lines`, `--edges`, or both). Any resolution: the generator
/// resamples it to the working size, so a map from the photo's own aspect ratio lines up.
/// Quantized to 8 bits so that small floating-point differences between devices and compute
/// units cannot change the template.
public struct EdgeMap: Sendable, Equatable {
    public let width: Int
    public let height: Int
    /// Row-major, `width * height` values.
    public var values: [UInt8]

    public init(width: Int, height: Int, values: [UInt8]) {
        precondition(width > 0 && height > 0 && values.count == width * height, "EdgeMap size mismatch")
        self.width = width
        self.height = height
        self.values = values
    }

    /// How much of a contour map a drawing is combined with (`combined(drawing:contours:)`):
    /// the drawing's own lines win wherever it has them, and the contours fill in the closed
    /// silhouettes it draws faintly or not at all. Measured on the red fox and Arrieta's still
    /// life (`docs/coloring-book.md`).
    public static let contourWeight: Float = 0.85

    /// A line drawing (the app's line-drawing model, `pbn --lines`) over a contour map (HED,
    /// `pbn --edges`): per pixel the larger of the drawing and `contourWeight` × the contours,
    /// at the drawing's size (the contours resampled to it). The drawing supplies fur, petals
    /// and glass as lines; the contours keep every object's outer boundary closed and strong.
    public static func combined(drawing: EdgeMap, contours: EdgeMap, contourWeight: Float = contourWeight) -> EdgeMap {
        let c = contours.width == drawing.width && contours.height == drawing.height
            ? contours : contours.resampled(width: drawing.width, height: drawing.height)
        var values = drawing.values
        for i in values.indices {
            let scaled = UInt8(min(max((Float(c.values[i]) * contourWeight + 0.5).rounded(.down), 0), 255))
            values[i] = max(values[i], scaled)
        }
        return EdgeMap(width: drawing.width, height: drawing.height, values: values)
    }

    /// The map area-resampled to `width` × `height` (the generator's own resampler, so a map
    /// made at one size lines up with one made at another), each level rounded to the nearest.
    public func resampled(width w: Int, height h: Int) -> EdgeMap {
        precondition(w > 0 && h > 0, "EdgeMap size")
        if w == width && h == height { return self }
        let xw = Resample.Weights(inCount: width, outCount: w), yw = Resample.Weights(inCount: height, outCount: h)
        var horizontal = [Float](repeating: 0, count: w * height)
        for y in 0..<height {
            let row = y * width, out = y * w
            for x in 0..<w {
                var acc: Float = 0
                for k in xw.start[x]..<xw.start[x + 1] { acc += Float(values[row + Int(xw.index[k])]) * xw.weight[k] }
                horizontal[out + x] = acc
            }
        }
        var out = [UInt8](repeating: 0, count: w * h)
        for y in 0..<h {
            for x in 0..<w {
                var acc: Float = 0
                for k in yw.start[y]..<yw.start[y + 1] { acc += horizontal[Int(yw.index[k]) * w + x] * yw.weight[k] }
                out[y * w + x] = UInt8(min(max((acc + 0.5).rounded(.down), 0), 255))
            }
        }
        return EdgeMap(width: w, height: h, values: out)
    }
}

/// Everything layered line art needs beyond the photo.
public struct LineArtInput: Sendable, Equatable {
    /// What is drawn: the line drawing over the contours (`EdgeMap.combined`), or either alone.
    public var edges: EdgeMap
    /// Detected eyes as closed polygons (contours, then irises), in coordinates normalized to
    /// the source photo (0...1, origin top-left). Drawn as outlines when
    /// `LineArtSettings.outlineEyes` is on.
    public var eyes: [[SIMD2<Float>]]
    /// The subjects' silhouettes as closed polygons normalized like `eyes` (the app's Vision
    /// foreground masks, `pbn --objects`; `MaskContours.outlines` traces a mask). Where no drawn
    /// line runs along a stretch of a silhouette, that stretch is drawn as an outline
    /// (`LineArtSettings.outlineObjects`), so a subject is closed off from the background even
    /// where the detectors saw no contour (a white belly against snow).
    public var objects: [[SIMD2<Float>]]
    /// The contour map alone (HED) when `edges` combines it with a drawing: it decides which
    /// lines are outlines (`LineArtSettings.outlineThreshold` reads it), so an object's boundary
    /// is an outline wherever the contour detector found it and the drawing's strokes, however
    /// strong, are detail. Nil: `edges` decides, as a single map always did.
    public var contours: EdgeMap?

    public init(edges: EdgeMap, eyes: [[SIMD2<Float>]] = [], objects: [[SIMD2<Float>]] = [], contours: EdgeMap? = nil) {
        self.edges = edges
        self.eyes = eyes
        self.objects = objects
        self.contours = contours
    }

    /// The input `detector` draws from when both maps exist: the drawing over the contours with
    /// the contours deciding the outlines, or either map alone deciding everything. The app's
    /// detector setting and `pbn --line-art detector=` both go through here.
    public init(
        drawing: EdgeMap, contours: EdgeMap, detector: LineArtSettings.Detector,
        eyes: [[SIMD2<Float>]] = [], objects: [[SIMD2<Float>]] = [], contourWeight: Float = EdgeMap.contourWeight
    ) {
        switch detector {
        case .drawingAndContours:
            self.init(
                edges: EdgeMap.combined(drawing: drawing, contours: contours, contourWeight: contourWeight),
                eyes: eyes, objects: objects, contours: contours)
        case .drawing:
            self.init(edges: drawing, eyes: eyes, objects: objects)
        case .contours:
            self.init(edges: contours, eyes: eyes, objects: objects)
        }
    }
}
