/// What layered line art did (`pbn`'s `stats.json` `lineArt` section). Lengths in canvas units.
public struct LineArtStats: Sendable, Codable, Equatable {
    /// Regions of the color segmentation the lines split (a classic template's regions).
    public var segmentationRegions = 0
    /// Lines after tracing, layering, eyes and closing.
    public var strokes = 0
    /// Eyes outlined.
    public var eyes = 0
    /// Subjects whose silhouettes were given, and the stretches of them drawn where the
    /// drawing left a silhouette open.
    public var objects = 0
    public var objectStretches = 0
    /// Lines of text whose writing was traced (`Writing`), marks kept beside them, and the
    /// writing's line (also counted in `interiorLength`).
    public var writingAreas = 0
    public var writingMarks = 0
    public var writingLength: Float = 0
    /// Every line of text the writing stage looked at, in the input's order.
    public var writing: [WritingAreaStats] = []
    /// Free ends extended to a line, paint boundary or the frame.
    public var endsClosed = 0
    /// Cells right after splitting the segmentation along the lines.
    public var cellsSplit = 0
    /// Cells too small for their number merged inside their enclosed area.
    public var smallMerged = 0
    /// Cells too small for their number merged across a line.
    public var tinyMerged = 0
    /// Line-free neighbours merged for close paints (`keepColorEdges` off).
    public var closeColorsMerged = 0
    public var cellsBeforeJoin = 0
    /// Same-paint neighbours joined (`samePaint`).
    public var samePaintJoins = 0
    /// Cells of the template.
    public var cells = 0
    /// Paints no cell used any more.
    public var paintsDropped = 0
    /// Drawn line along cell boundaries per layer (outline, detail, texture).
    public var boundaryLength: [Float] = [0, 0, 0]
    /// Drawn line inside cells per layer.
    public var interiorLength: [Float] = [0, 0, 0]
    public var interiorStrokes = 0

    public init() {}

    mutating func add(_ line: DrawnLine, interior: Bool) {
        guard line.points.count > 1 else { return }
        for k in 1..<line.points.count {
            let l = Int(min(line.layer[k - 1], 2))
            let d = simdLength(line.points[k] - line.points[k - 1])
            if interior { interiorLength[l] += d } else { boundaryLength[l] += d }
        }
        if interior { interiorStrokes += 1 }
    }
}

/// One line of text the writing stage looked at (`Writing`): what it measured and what came of it.
public struct WritingAreaStats: Sendable, Codable, Equatable {
    /// The box's centre and height (canvas units).
    public var x: Float = 0
    public var y: Float = 0
    public var height: Float = 0
    /// The contrast from which a pixel is ink, the share of the core's pixels that are ink, the
    /// ground's grain (`Writing.maximumGrain`), the pen (`Writing.Ink.pen`), line traced per
    /// length of the box, pieces (strokes between ends and junctions, and dots) per height of line
    /// traced, and marks kept beside it.
    public var contrast: Float = 0
    public var coverage: Float = 0
    public var grain: Float = 0
    public var pen: Float = 0
    public var inkPerLength: Float = 0
    public var piecesPerHeight: Float = 0
    public var marks = 0
    /// `kept`, or why not: `size` (too small or large to take), `noInk`, `picture`, `bold`,
    /// `sparse`, `dense` or `texture` (see `Writing`).
    public var verdict = ""

    public init() {}
}
