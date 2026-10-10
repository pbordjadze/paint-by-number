import CoreGraphics
import Foundation
import PaintCore

/// What the painter refined in a new painting before painting it (the create flow's optional
/// Refine step, `RefineView`): lines drawn and erased, shapes filled, and, with Settings ›
/// Detail Brushes, areas brushed for more or less detail and corrections to the lines of text
/// the app found.
/// Refinements change what the generator reads, never a template, so they hold through every
/// draft and slider, and regenerating the painting reproduces them (its `refinements.json`):
/// - lines drawn and erased join the line art's input as the painter's edits
///   (`LineArtInput.edits`, in order), which PaintCore lays out with its own lines (`LineEdits`);
///   so do the shapes filled, each cell filled an area of its own in the photo's color there (a
///   detail area, `Template.detailRegions`);
/// - more detail raises the importance map toward 1 and strengthens the edge maps (`moreLines`):
///   smaller regions, gentler smoothing, more lines, and so more cells in a coloring book;
/// - less detail lowers it toward `lessImportance` and weakens the edge maps (`fewerLines`);
/// - the text corrections edit `LineArtInput.writing`: lines the app found and the painter turned
///   off go, lines the painter marked join.
/// A painting nobody refined has none, and its generation is untouched.
///
/// The strengths were measured with `pbn` on the corpus's parrots, lighthouse and barn, a box of
/// each brushed (24 colors, detail 0.5, as a book): more turned the barn's field from 35 regions
/// into 109 and the parrots' foliage from 13 into 19, less turned them into 2 and 3. In a book,
/// most of it is the edge maps', whose lines split cells.
nonisolated struct TemplateRefinements: Codable, Equatable, Sendable {
    /// One stroke of the brush.
    nonisolated struct Stroke: Codable, Equatable, Sendable {
        nonisolated enum Kind: String, Codable, Sendable {
            /// More detail and lines.
            case more
            /// Less detail, fewer lines.
            case less
            /// Back to the app's own.
            case erase
        }

        var kind: Kind
        /// The brush's radius, a fraction of the photo's long side.
        var radius: Float
        /// The brush's path, normalized to the photo (0...1, origin top-left); one point is a dab.
        var points: [SIMD2<Float>]
    }

    /// A line drawn with the pen, the eraser's pass, a line tapped away, or a shape filled
    /// (`LineEdit`).
    nonisolated struct Line: Codable, Equatable, Sendable {
        nonisolated enum Kind: String, Codable, Sendable {
            /// A line added to the drawing.
            case draw
            /// The lines under the path taken out.
            case erase
            /// The line along the path (its own) taken out from end to end.
            case eraseLine
            /// The cell under the point made an area of its own, in the photo's color there.
            case fill
        }

        var kind: Kind
        /// How far either side of its path the eraser reaches, a fraction of the photo's long
        /// side; 0 for a drawn line or a fill.
        var radius: Float
        /// The path, normalized to the photo (0...1, origin top-left); a fill's one point.
        var points: [SIMD2<Float>]
    }

    /// The lines drawn and erased and the shapes filled, in the order they were.
    var lines: [Line] = []
    var strokes: [Stroke] = []
    /// Lines of text the app found that the painter turned off, as they were found.
    var hiddenText: [[SIMD2<Float>]] = []
    /// Lines of text the painter marked: rectangles (top left, top right, bottom right, bottom
    /// left), normalized like `LineArtInput.writing`.
    var addedText: [[SIMD2<Float>]] = []

    init() {}

    var isEmpty: Bool { lines.isEmpty && strokes.isEmpty && hiddenText.isEmpty && addedText.isEmpty }

    /// How many things the painter changed: lines drawn and erased, shapes filled, strokes, and
    /// lines of text turned off or marked.
    var changeCount: Int { lines.count + strokes.count + hiddenText.count + addedText.count }

    // MARK: Strengths

    /// The edge maps' gain where more detail is brushed, and where less is.
    static let moreLines: Float = 1.3
    static let fewerLines: Float = 0.55
    /// Where less detail is brushed, importance falls toward this rather than to nothing, which
    /// left the barn's field one flat area.
    static let lessImportance: Float = 0.1
    /// The brush fades over this outer share of its radius, so a refined area blends in.
    static let softEdge: Float = 0.35
    /// The radii a stroke may have (of the photo's long side), and how much of a hostile file is
    /// read: the app writes far fewer.
    static let radiusRange: ClosedRange<Float> = 0.002...0.25
    static let maximumStrokes = 2000
    static let maximumPoints = 4000
    /// The neutral importance map's long side when Vision gave none, as `SubjectImportance`'s.
    static let neutralResolution = 256

    // MARK: Applying

    /// The generator's inputs refined. Importance moves toward 1 where more detail was brushed and
    /// toward `lessImportance` where less was, as far as the brush covers; without a map from
    /// Vision a neutral one (0.5, of `aspect`, the photo's width over height) stands in, brushed.
    /// The edge maps gain `moreLines` or `fewerLines` there, the text the app found is
    /// corrected, and the lines drawn and erased and the shapes filled become the line art's edits.
    func refining(
        importance: PaintCore.Grid<Float>?, lineArt: LineArtInput?, aspect: Float
    ) -> (importance: PaintCore.Grid<Float>?, lineArt: LineArtInput?) {
        guard !isEmpty else { return (importance, lineArt) }
        var importance = importance
        if !strokes.isEmpty {
            var map = importance ?? Self.neutralImportance(aspect: aspect)
            if let focus = focus(width: map.width, height: map.height) {
                for i in focus.indices where focus[i] != 0 {
                    let f = focus[i], v = map.storage[i]
                    let target = f > 0 ? 1 : min(v, Self.lessImportance)
                    map.storage[i] = v + abs(f) * (target - v)
                }
            }
            importance = map
        }
        guard var lineArt else { return (importance, nil) }
        if !strokes.isEmpty {
            lineArt.edges = refined(lineArt.edges)
            lineArt.contours = lineArt.contours.map(refined)
        }
        if !hiddenText.isEmpty || !addedText.isEmpty {
            let hidden = hiddenText.prefix(Self.maximumStrokes)
            lineArt.writing = lineArt.writing.filter { found in !hidden.contains { Self.sameLine(found, $0) } }
                + addedText.prefix(Self.maximumStrokes).filter(Self.isQuadrilateral)
        }
        if !lines.isEmpty { lineArt.edits = edits }
        return (importance, lineArt)
    }

    /// The lines drawn and erased and the shapes filled as PaintCore reads them (it checks and
    /// bounds them itself).
    var edits: [LineEdit] {
        lines.prefix(Self.maximumStrokes).map { line in
            let kind: LineEdit.Kind = switch line.kind {
            case .draw: .draw
            case .erase: .erase
            case .eraseLine: .eraseLine
            case .fill: .fill
            }
            return LineEdit(kind: kind, points: Array(line.points.prefix(Self.maximumPoints)), radius: line.radius)
        }
    }

    /// `map` with the edge gain of the brushed focus.
    private func refined(_ map: EdgeMap) -> EdgeMap {
        guard let focus = focus(width: map.width, height: map.height) else { return map }
        var values = map.values
        for i in values.indices where focus[i] != 0 {
            let f = focus[i]
            let gain = f > 0 ? 1 + (Self.moreLines - 1) * f : 1 - (1 - Self.fewerLines) * -f
            values[i] = UInt8(min(max((Float(values[i]) * gain).rounded(), 0), 255))
        }
        return EdgeMap(width: map.width, height: map.height, values: values)
    }

    /// The brushed focus over a `width` × `height` grid laid over the photo: +1 where more detail
    /// was brushed, −1 where less, 0 where nothing was or it was erased. Each stroke covers the
    /// ones before it, fully inside and fading over its outer `softEdge`; nil without strokes.
    /// Plain arithmetic in a fixed order: the same refinements give the same grid everywhere.
    func focus(width: Int, height: Int) -> [Float]? {
        guard !strokes.isEmpty, width > 0, height > 0 else { return nil }
        var focus = [Float](repeating: 0, count: width * height)
        let long = Float(max(width, height)), scale = SIMD2(Float(width), Float(height))
        for stroke in strokes.prefix(Self.maximumStrokes) {
            let points = stroke.points.prefix(Self.maximumPoints)
                .filter { $0.x.isFinite && $0.y.isFinite }
                .map { $0 * scale }
            guard let first = points.first, stroke.radius.isFinite else { continue }
            let radius = min(max(stroke.radius, Self.radiusRange.lowerBound), Self.radiusRange.upperBound) * long
            let target: Float = switch stroke.kind {
            case .more: 1
            case .less: -1
            case .erase: 0
            }
            var low = first, high = first
            for p in points {
                low = pointwiseMin(low, p)
                high = pointwiseMax(high, p)
            }
            let x0 = max(0, Int((low.x - radius).rounded(.down))), x1 = min(width - 1, Int((high.x + radius).rounded(.up)))
            let y0 = max(0, Int((low.y - radius).rounded(.down))), y1 = min(height - 1, Int((high.y + radius).rounded(.up)))
            guard x0 <= x1, y0 <= y1 else { continue }
            // This stroke's own coverage first (the most any of its segments gives a pixel), so
            // its overlapping segments don't count twice.
            let boxWidth = x1 - x0 + 1
            var coverage = [Float](repeating: 0, count: boxWidth * (y1 - y0 + 1))
            let segments = points.count == 1 ? [(first, first)] : Array(zip(points, points.dropFirst()))
            for (a, b) in segments {
                let sx0 = max(x0, Int((min(a.x, b.x) - radius).rounded(.down)))
                let sx1 = min(x1, Int((max(a.x, b.x) + radius).rounded(.up)))
                let sy0 = max(y0, Int((min(a.y, b.y) - radius).rounded(.down)))
                let sy1 = min(y1, Int((max(a.y, b.y) + radius).rounded(.up)))
                guard sx0 <= sx1, sy0 <= sy1 else { continue }
                for y in sy0...sy1 {
                    for x in sx0...sx1 {
                        let c = Self.coverage(distance: Self.distance(SIMD2(Float(x) + 0.5, Float(y) + 0.5), a, b), radius: radius)
                        let k = (y - y0) * boxWidth + (x - x0)
                        if c > coverage[k] { coverage[k] = c }
                    }
                }
            }
            for y in y0...y1 {
                for x in x0...x1 {
                    let c = coverage[(y - y0) * boxWidth + (x - x0)]
                    guard c > 0 else { continue }
                    let i = y * width + x
                    focus[i] += (target - focus[i]) * c
                }
            }
        }
        return focus
    }

    /// Full inside, fading to nothing over the outer `softEdge` of the radius (at least a pixel).
    static func coverage(distance d: Float, radius r: Float) -> Float {
        let soft = max(r * softEdge, 1)
        if d <= r - soft { return 1 }
        if d >= r { return 0 }
        let t = (r - d) / soft
        return t * t * (3 - 2 * t)
    }

    /// The distance from `p` to the segment `a`–`b`.
    static func distance(_ p: SIMD2<Float>, _ a: SIMD2<Float>, _ b: SIMD2<Float>) -> Float {
        let ab = b - a, length = (ab * ab).sum()
        let t = length > 0 ? min(max(((p - a) * ab).sum() / length, 0), 1) : 0
        let d = p - (a + ab * t)
        return (d * d).sum().squareRoot()
    }

    /// A neutral importance map (0.5 everywhere) of the photo's shape.
    static func neutralImportance(aspect: Float) -> PaintCore.Grid<Float> {
        let side = Float(neutralResolution)
        let ratio = aspect.isFinite && aspect > 0 ? aspect : 1
        let width = ratio >= 1 ? neutralResolution : max(1, Int((side * ratio).rounded()))
        let height = ratio >= 1 ? max(1, Int((side / ratio).rounded())) : neutralResolution
        return PaintCore.Grid(width: width, height: height, repeating: 0.5)
    }

    // MARK: Text

    /// Whether two lines of text are the same line: their bounds overlap by at least half of
    /// their union, so a line Vision finds a little differently when the painting is regenerated
    /// is still the one the painter turned off.
    static func sameLine(_ a: [SIMD2<Float>], _ b: [SIMD2<Float>]) -> Bool {
        guard let ba = bounds(a), let bb = bounds(b) else { return false }
        let overlap = ba.intersection(bb)
        guard !overlap.isNull, !overlap.isEmpty else { return false }
        let union = ba.width * ba.height + bb.width * bb.height - overlap.width * overlap.height
        return union > 0 && overlap.width * overlap.height >= 0.5 * union
    }

    /// The bounds of a line's polygon, nil for one with no finite points.
    static func bounds(_ polygon: [SIMD2<Float>]) -> CGRect? {
        let finite = polygon.filter { $0.x.isFinite && $0.y.isFinite }
        guard let first = finite.first else { return nil }
        var low = first, high = first
        for p in finite {
            low = pointwiseMin(low, p)
            high = pointwiseMax(high, p)
        }
        return CGRect(x: CGFloat(low.x), y: CGFloat(low.y), width: CGFloat(high.x - low.x), height: CGFloat(high.y - low.y))
    }

    private static func isQuadrilateral(_ polygon: [SIMD2<Float>]) -> Bool {
        polygon.count == 4 && polygon.allSatisfy { $0.x.isFinite && $0.y.isFinite }
    }

    /// A rectangle marked as a line of text, `a` and `b` its opposite corners (normalized), in
    /// `TextFinder`'s order and quantum, so marked lines read like found ones.
    static func textLine(from a: SIMD2<Float>, to b: SIMD2<Float>) -> [SIMD2<Float>] {
        func q(_ v: Float) -> Float { (min(max(v, 0), 1) * Float(TextFinder.quantum)).rounded() / Float(TextFinder.quantum) }
        let left = q(min(a.x, b.x)), right = q(max(a.x, b.x)), top = q(min(a.y, b.y)), bottom = q(max(a.y, b.y))
        return [SIMD2(left, top), SIMD2(right, top), SIMD2(right, bottom), SIMD2(left, bottom)]
    }

    // MARK: Coding

    private enum CodingKeys: String, CodingKey { case lines, strokes, hiddenText, addedText }

    /// Tolerant: a field, line or stroke it can't read (a kind from a newer app) is left out
    /// rather than costing the rest.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        lines = ((try? c.decodeIfPresent([Lossy<Line>].self, forKey: .lines)) ?? []).compactMap(\.value)
        strokes = ((try? c.decodeIfPresent([Lossy<Stroke>].self, forKey: .strokes)) ?? []).compactMap(\.value)
        hiddenText = (try? c.decodeIfPresent([[SIMD2<Float>]].self, forKey: .hiddenText)) ?? []
        addedText = (try? c.decodeIfPresent([[SIMD2<Float>]].self, forKey: .addedText)) ?? []
    }

    private struct Lossy<Value: Decodable>: Decodable {
        let value: Value?
        init(from decoder: Decoder) throws { value = try? Value(from: decoder) }
    }
}
