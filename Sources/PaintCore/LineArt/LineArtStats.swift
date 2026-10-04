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
