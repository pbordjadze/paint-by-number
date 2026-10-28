#if canImport(CoreGraphics)
import CoreGraphics  // CGRect's geometry on Apple platforms; Foundation has it on Linux.
#endif
import Foundation

/// The shapes Refine's Shapes tool draws (`ShapePath`): a straight line from where a drag starts
/// to where it ends, a rectangle, an oval, a hexagon or a five-pointed star across it, and a
/// curve: a drag for its ends, then a second drag bends it through the finger (a tap leaves it
/// straight). New shapes go last: the app lists them in this order.
public enum RefineShape: CaseIterable, Hashable, Sendable {
    case line, rectangle, oval, curve, polygon, star

    /// The figure ends where it starts.
    public var isClosed: Bool {
        switch self {
        case .rectangle, .oval, .polygon, .star: true
        case .line, .curve: false
        }
    }
}

/// The fills a tap of the Fill tool takes out.
public enum EditFills {
    /// The positions in `edits` of the fills that made the detail area under `point` (canvas
    /// units) of `template`: those whose own point lies in that area. None where the tap is not in
    /// a detail area, or in one no fill made (a piece too small for the usual number is a detail
    /// area too); a tap there makes a fill.
    public static func cleared(by point: SIMD2<Float>, edits: [TemplateEditor.Edit], on template: Template) -> [Int] {
        guard let area = template.region(at: point), template.isDetailRegion(area) else { return [] }
        return edits.indices.filter { index in
            guard case .fill(let at, _) = edits[index] else { return false }
            return template.region(at: at) == area
        }
    }
}

/// The Refine screen as its gestures see it: how large the picture is on screen and at what
/// zoom. Points on the picture are normalized (0…1, origin top-left), as the screen's touches
/// arrive; the edits they make are in the template's canvas units.
public struct RefineScreen: Sendable, Equatable {
    /// The template's canvas, canvas units.
    public var canvas: CGSize
    /// The picture on screen at its zoom, points.
    public var picture: CGSize
    /// The canvas view the picture sits in, points (the eraser's size follows it).
    public var view: CGSize
    /// The drawing's line on screen, points (`LineArtDrawing.lineWidth` in the app).
    public var lineWidth: CGFloat

    public init(canvas: CGSize, picture: CGSize, view: CGSize, lineWidth: CGFloat) {
        self.canvas = canvas
        self.picture = picture
        self.view = view
        self.lineWidth = lineWidth
    }

    /// The template's canvas units per point on screen (0 before there is a picture).
    public var unitsPerPoint: CGFloat { picture.width > 0 ? canvas.width / picture.width : 0 }

    /// The shortest line on screen, in points (`RefineGestures.shortestLine`).
    public var shortestOnScreen: CGFloat {
        unitsPerPoint > 0 ? max(4, RefineGestures.shortestLine / unitsPerPoint) : 4
    }

    /// The eraser's reach, a fraction of the picture's long side: a thirtieth of the view's short
    /// side, between 10 and 20 points, so zoomed in it erases finer.
    public var eraserRadius: Float { eraserRadius(size: min(max(0.033 * min(view.width, view.height), 10), 20)) }

    /// An eraser of radius `size` points on screen (the app's Size) as a fraction of the picture's
    /// long side, as a brush's is (`brushRadius(size:)`).
    public func eraserRadius(size: CGFloat) -> Float { brushRadius(size: size) }

    /// The Paint Brush's reach, a fraction of the picture's long side: `RefineGestures.brushSize`
    /// on screen at any zoom, so zoomed in it paints finer, as the eraser erases.
    public var brushRadius: Float { brushRadius(size: RefineGestures.brushSize) }

    /// A brush of radius `size` points on screen as a fraction of the picture's long side.
    public func brushRadius(size: CGFloat) -> Float {
        let long = max(picture.width, picture.height)
        return long > 0 ? Float(size / long) : 0.02
    }

    /// A picture point on screen, in points from the picture's corner.
    public func onScreen(_ p: SIMD2<Float>) -> CGPoint {
        CGPoint(x: CGFloat(p.x) * picture.width, y: CGFloat(p.y) * picture.height)
    }

    /// A picture point in the template's canvas units.
    public func canvasPoint(_ p: SIMD2<Float>) -> SIMD2<Float> {
        SIMD2(p.x * Float(canvas.width), p.y * Float(canvas.height))
    }

    /// A point on screen as a picture point.
    public func picturePoint(_ p: CGPoint) -> SIMD2<Float> {
        SIMD2(Float(p.x / picture.width), Float(p.y / picture.height))
    }

    /// A step between two picture points, in points on screen.
    public func onScreenLength(_ step: SIMD2<Float>) -> CGFloat {
        hypot(CGFloat(step.x) * picture.width, CGFloat(step.y) * picture.height)
    }
}

/// What Refine makes of a gesture: the edit it sends to the template (`TemplateEditor.Edit`),
/// from the touches as they arrive (picture points) and the screen they arrive on. The app's
/// `RefineView` and `pbn refine` both make their edits here, so a gesture replayed off the
/// device makes the edit the screen makes.
public enum RefineGestures {
    /// The shortest line the pen draws, in the template's canvas units: a touch shorter than a
    /// fingertip's slip is no line.
    public static let shortestLine: CGFloat = 8
    /// The Pen's ends move onto a line whose ink theirs touches: within one ink width (half of
    /// each), and at least this many points, so an end whose ink only seems to touch on screen
    /// joins too. At 2, a grid's lines that met its frame on screen ended 2 points short of it,
    /// and its tiles ran into each other with no word (QA, October 23).
    public static let touchFloor: CGFloat = 3
    /// A finger's reach on screen, in points: how near a tap must come to a line to take it out.
    public static let fingerReach: CGFloat = 16
    /// The Paint Brush's radius on screen, in points: about half a fingertip, so the paint is the
    /// width of the finger that lays it, at any zoom.
    public static let brushSize: CGFloat = 12
    /// The string the Pen's line is pulled on at full smoothing, points on screen
    /// (`PenPath.steadied`): several times the few points a slow hand wobbles, so the wobble hardly
    /// reaches the line, yet only 3 to 4 mm, inside the pad of the finger, so the line's tip trails
    /// out of sight beneath it. The lag a painter notices starts where the tip shows behind the
    /// finger.
    public static let steadyString: CGFloat = 20

    /// A finger's samples as the screen keeps them while it moves: a sample closer than a point
    /// to the last kept adds nothing the line shows; the last, where the finger lifts, is kept.
    public static func trace(_ samples: [SIMD2<Float>], on screen: RefineScreen) -> [SIMD2<Float>] {
        guard let first = samples.first else { return [] }
        var kept = [first]
        for p in samples.dropFirst().dropLast() where screen.onScreenLength(p - kept[kept.count - 1]) >= 1 { kept.append(p) }
        if samples.count > 1 { kept.append(samples[samples.count - 1]) }
        return kept
    }

    /// A pen's line from its samples (`trace`): steadied by the painter's `smoothing` (0…1, the
    /// Pen's slider: `steadied`), smoothed and thinned on screen's terms as it showed, its ends
    /// moved onto a line their ink touches (`touchFloor`). Nil for a touch too short to be a line,
    /// on screen or in the template.
    public static func pen(
        _ points: [SIMD2<Float>], on screen: RefineScreen, snapping lines: SnapLines?, smoothing: CGFloat = 0
    ) -> TemplateEditor.Edit? {
        let line = PenPath.steadied(points.map(screen.onScreen), string: string(for: smoothing))
        guard screen.picture.width > 0, PenPath.length(line) >= screen.shortestOnScreen else { return nil }
        let smooth = PenPath.simplified(PenPath.smoothed(line, spacing: 2), tolerance: 0.3)
        return drawEdit(touching(smooth, straight: false, on: screen, snapping: lines), on: screen)
    }

    /// A pen's samples (`trace`) as its line shows under the finger while it moves, steadied by
    /// the painter's `smoothing` as `pen` steadies them: unchanged at 0.
    public static func steadied(_ samples: [SIMD2<Float>], smoothing: CGFloat, on screen: RefineScreen) -> [SIMD2<Float>] {
        let length = string(for: smoothing)
        guard length > 0, screen.picture.width > 0, screen.picture.height > 0 else { return samples }
        return PenPath.steadied(samples.map(screen.onScreen), string: length).map(screen.picturePoint)
    }

    /// The Color Splitter's stroke: the Pen's line (`pen`), as a split, which divides the paint and
    /// draws nothing.
    public static func splitter(_ points: [SIMD2<Float>], on screen: RefineScreen, snapping lines: SnapLines?) -> TemplateEditor.Edit? {
        guard case .draw(let line, let closed, _)? = pen(points, on: screen, snapping: lines) else { return nil }
        return .split(points: line, closed: closed)
    }

    /// The Cell Edge's stroke: the Pen's line (`pen`), as a cell edge, which divides a cell and
    /// draws nothing, both pieces keeping its paint.
    public static func cellEdge(_ points: [SIMD2<Float>], on screen: RefineScreen, snapping lines: SnapLines?) -> TemplateEditor.Edit? {
        guard case .draw(let line, let closed, _)? = pen(points, on: screen, snapping: lines) else { return nil }
        return .cellEdge(points: line, closed: closed)
    }

    /// The eraser's pass as an edit: its path in canvas units, and its reach there, the radius it
    /// has on screen: `size` points (the app's Size), or without one the automatic
    /// (`RefineScreen.eraserRadius`). A dab is one point.
    public static func eraser(_ points: [SIMD2<Float>], on screen: RefineScreen, size: CGFloat? = nil) -> TemplateEditor.Edit? {
        let canvas = screen.canvas
        guard canvas.width > 0, canvas.height > 0 else { return nil }
        let path = simplified(points, tolerance: 0.5, on: screen).map(screen.canvasPoint)
        let radius = size.map { screen.eraserRadius(size: $0) } ?? screen.eraserRadius
        return .erase(path: path, radius: radius * Float(max(canvas.width, canvas.height)))
    }

    /// The Merge's drag as an edit: its path in canvas units, thinned as the eraser's is. Nil for
    /// no touch.
    public static func merge(_ points: [SIMD2<Float>], on screen: RefineScreen) -> TemplateEditor.Edit? {
        guard !points.isEmpty, screen.canvas.width > 0, screen.canvas.height > 0 else { return nil }
        return .merge(points: simplified(points, tolerance: 0.5, on: screen).map(screen.canvasPoint))
    }

    /// The Paint Brush's stroke as an edit: its path in canvas units, thinned as the eraser's is,
    /// its reach there the brush's on screen (`brushRadius(size:)`, `size` points; the app's Size),
    /// painting `color` (OKLab, a color of the template on screen). A dab is one point; nil for no
    /// touch.
    public static func brush(
        _ points: [SIMD2<Float>], on screen: RefineScreen, color: SIMD3<Float>, size: CGFloat = brushSize
    ) -> TemplateEditor.Edit? {
        let canvas = screen.canvas
        guard !points.isEmpty, canvas.width > 0, canvas.height > 0 else { return nil }
        let path = simplified(points, tolerance: 0.5, on: screen).map(screen.canvasPoint)
        return .brush(path: path, radius: screen.brushRadius(size: size) * Float(max(canvas.width, canvas.height)), color: color)
    }

    /// A drag of Bend Line or Move Edge as an edit: the line `target` grabs (Bend Line's `.ink`,
    /// Move Edge's `.edge`) within a finger's reach (`fingerReach` on screen) of where it started,
    /// moved so its point there goes where the finger lifts. Nil for a drag under a point on
    /// screen.
    public static func reshape(
        from a: SIMD2<Float>, to b: SIMD2<Float>, on screen: RefineScreen, target: TemplateEditor.ReshapeTarget = .any
    ) -> TemplateEditor.Edit? {
        guard let reach = fingerReachOnCanvas(screen), screen.onScreenLength(b - a) >= 1 else { return nil }
        return .reshape(from: screen.canvasPoint(a), to: screen.canvasPoint(b), reach: reach, target: target)
    }

    /// A drag of Move Number as an edit: the number under where it started (within its radius and
    /// a finger's reach, `fingerReach` on screen: `TemplateEditor.labelNear`) moved to where it
    /// ended, canvas units. Nil for a drag under a point on screen.
    public static func moveLabel(from a: SIMD2<Float>, to b: SIMD2<Float>, on screen: RefineScreen) -> TemplateEditor.Edit? {
        guard let reach = fingerReachOnCanvas(screen), screen.onScreenLength(b - a) >= 1 else { return nil }
        return .moveLabel(from: screen.canvasPoint(a), to: screen.canvasPoint(b), reach: reach)
    }

    /// A finger's reach (`fingerReach` points on screen) in canvas units; nil for a screen with no
    /// picture or canvas.
    public static func fingerReachOnCanvas(_ screen: RefineScreen) -> Float? {
        let size = screen.canvas
        guard screen.picture.width > 0, size.width > 0, size.height > 0 else { return nil }
        return Float(fingerReach * size.width / screen.picture.width)
    }

    /// The shape a drag from `a` to `b` draws (points on screen), as it shows while the finger
    /// moves; for a curve whose ends are down (`curve`), the curve bent through `b`. Nil while it
    /// is too small to draw.
    public static func figure(
        _ shape: RefineShape, from a: SIMD2<Float>, to b: SIMD2<Float>, curve: (from: SIMD2<Float>, to: SIMD2<Float>)? = nil,
        on screen: RefineScreen, snapping lines: SnapLines?
    ) -> [CGPoint]? {
        guard screen.picture.width > 0, screen.picture.height > 0 else { return nil }
        if let curve {
            return ShapePath.curve(
                from: screen.onScreen(curve.from), to: screen.onScreen(curve.to), through: screen.onScreen(b), spacing: 2)
        }
        let p = screen.onScreen(a), q = screen.onScreen(b)
        let shortest = screen.shortestOnScreen
        switch shape {
        case .line, .curve:
            guard PenPath.distance(p, q) >= shortest else { return nil }
            return touching([p, q], straight: true, on: screen, snapping: lines)
        case .rectangle:
            guard abs(q.x - p.x) >= shortest, abs(q.y - p.y) >= shortest else { return nil }
            return ShapePath.rectangle(from: p, to: q)
        case .oval:
            guard abs(q.x - p.x) >= shortest, abs(q.y - p.y) >= shortest else { return nil }
            return ShapePath.oval(from: p, to: q, spacing: 2)
        case .polygon, .star:
            guard abs(q.x - p.x) >= shortest, abs(q.y - p.y) >= shortest else { return nil }
            return shape == .polygon ? ShapePath.polygon(from: p, to: q) : ShapePath.star(from: p, to: q)
        }
    }

    /// The edit a drag of Shapes sends when the finger lifts (nil for a curve's first drag, which
    /// only puts its ends down, or a shape too small to draw).
    public static func shape(
        _ shape: RefineShape, from a: SIMD2<Float>, to b: SIMD2<Float>, curve: (from: SIMD2<Float>, to: SIMD2<Float>)? = nil,
        on screen: RefineScreen, snapping lines: SnapLines?
    ) -> TemplateEditor.Edit? {
        guard let figure = figure(shape, from: a, to: b, curve: curve, on: screen, snapping: lines) else { return nil }
        return drawEdit(figure, closed: curve == nil && shape.isClosed, on: screen)
    }

    /// Where a curve's first drag puts its ends (picture points): the drag as a straight line,
    /// its ends moved onto the lines they touch. Nil for a drag too short to draw.
    public static func curveEnds(
        from a: SIMD2<Float>, to b: SIMD2<Float>, on screen: RefineScreen, snapping lines: SnapLines?
    ) -> (from: SIMD2<Float>, to: SIMD2<Float>)? {
        guard let ends = figure(.curve, from: a, to: b, on: screen, snapping: lines), ends.count == 2 else { return nil }
        return (screen.picturePoint(ends[0]), screen.picturePoint(ends[1]))
    }

    /// A curve whose ends are down and that wasn't bent is laid straight.
    public static func straightCurve(from a: SIMD2<Float>, to b: SIMD2<Float>, on screen: RefineScreen) -> TemplateEditor.Edit? {
        drawEdit([screen.onScreen(a), screen.onScreen(b)], on: screen)
    }

    /// A tap of the Line Eraser: the drawn line under it from junction to junction (`chains`,
    /// for the flash and the ink laid over it; the template's editor decides what goes), within a
    /// finger's reach. The chain is normalized to the picture.
    public static func lineEraser(
        at point: SIMD2<Float>, on screen: RefineScreen, chains: LineChains
    ) -> (edit: TemplateEditor.Edit, chain: [SIMD2<Float>])? {
        let size = screen.canvas
        guard screen.picture.width > 0, size.width > 0, size.height > 0 else { return nil }
        let tap = CGPoint(x: CGFloat(point.x) * size.width, y: CGFloat(point.y) * size.height)
        let reach = fingerReach * size.width / screen.picture.width
        guard let chain = chains.chain(near: tap, tolerance: reach) else { return nil }
        let normalized = chain.map { SIMD2(Float($0.x / size.width), Float($0.y / size.height)) }
        return (.eraseLine(at: screen.canvasPoint(point), reach: Float(reach)), normalized)
    }

    /// The lines on screen a pen's end may meet, in canvas units: the template's drawing
    /// (`drawingLines`), the lines drawn since, less what was erased since: `pending`, the edits
    /// sent that the template doesn't show yet, each with the chain a line eraser's tap took
    /// (normalized).
    public static func snapLines(
        drawing: [[CGPoint]], canvas: CGSize, pending: [(edit: TemplateEditor.Edit, chain: [SIMD2<Float>]?)]
    ) -> SnapLines {
        var lines = drawing
        for item in pending {
            switch item.edit {
            case .draw(let points, let closed, _):
                lines.append((closed ? points + points.prefix(1) : points).map { CGPoint(x: CGFloat($0.x), y: CGFloat($0.y)) })
            case .erase(let path, let radius):
                lines = SnapLines.erasing(lines, by: [(path.map { CGPoint(x: CGFloat($0.x), y: CGFloat($0.y)) }, CGFloat(radius))])
            case .eraseLine:
                // The line itself: what meets it keeps its junction.
                if let chain = item.chain {
                    let inCanvas = chain.map { CGPoint(x: CGFloat($0.x) * canvas.width, y: CGFloat($0.y) * canvas.height) }
                    lines = SnapLines.erasing(lines, by: [(inCanvas, 1.5)])
                }
            case .fill, .paintArea, .split, .cellEdge, .merge, .brush, .reshape, .moveLabel, .look, .repaint:
                // The lines a merge takes out, or a reshape moves, go when the template shows it.
                break
            }
        }
        return SnapLines(lines)
    }

    /// The lines of a template's drawing, canvas units, as Refine shows them (the app's
    /// `LineArtDrawing`): each drawn edge (`LineLayer` other than `color`) inside the canvas, then
    /// each well-formed interior stroke of a drawn layer. A template without line art draws every
    /// edge inside the canvas. Without `writing`, the strokes of its writing are left out: the
    /// lines a drawn line's ends may join (`snapLines`), since the editor never joins one to a
    /// letter.
    public static func drawingLines(of t: Template, writing: Bool = true) -> [[CGPoint]] {
        let art = t.lineArt.flatMap { $0.edgeLayers.count == t.edges.count && $0.edgeWeights.count == t.edges.count ? $0 : nil }
        func points(_ slice: some Collection<SIMD2<Float>>) -> [CGPoint] { slice.map { CGPoint(x: CGFloat($0.x), y: CGFloat($0.y)) } }
        var lines: [[CGPoint]] = []
        for (e, edge) in t.edges.enumerated() where edge.right != BoundaryEdge.outside {
            if let art, !LineLayer.isDrawn(art.edgeLayers[e]) { continue }
            let line = points(t.points(of: edge))
            if line.count >= 2 { lines.append(line) }
        }
        guard let art else { return lines }
        for (k, s) in art.strokes.enumerated()
        where s.pointCount >= 2 && Int(s.pointStart) + Int(s.pointCount) <= art.strokePoints.count
            && Int(s.region) < t.regions.count && LineLayer.isDrawn(s.layer) && (writing || !art.isWritingStroke(k)) {
            lines.append(points(art.strokePoints[Int(s.pointStart)..<Int(s.pointStart + s.pointCount)]))
        }
        return lines
    }

    // MARK: - Helpers

    /// The string a pen's `smoothing` pulls its line on, points on screen: none at 0,
    /// `steadyString` at 1.
    static func string(for smoothing: CGFloat) -> CGFloat { min(max(smoothing, 0), 1) * steadyString }

    /// `line` (points on screen) with its ends moved onto a line of the drawing their ink touches.
    static func touching(_ line: [CGPoint], straight: Bool, on screen: RefineScreen, snapping lines: SnapLines?) -> [CGPoint] {
        let units = screen.unitsPerPoint
        guard let lines, units > 0 else { return line }
        let reach = max(screen.lineWidth, touchFloor) * units
        let inCanvas = line.map { CGPoint(x: $0.x * units, y: $0.y * units) }
        return PenAssist.joined(inCanvas, to: lines, reach: reach, straight: straight)
            .map { CGPoint(x: $0.x / units, y: $0.y / units) }
    }

    /// A line of points on screen as the edit that draws it, in the template's canvas units. A
    /// closed figure ends where it starts: the edit has that point once and says it is closed.
    public static func drawEdit(_ points: [CGPoint], closed: Bool = false, on screen: RefineScreen) -> TemplateEditor.Edit? {
        let units = screen.unitsPerPoint
        guard units > 0 else { return nil }
        let canvas = points.map { SIMD2(Float($0.x * units), Float($0.y * units)) }
        return .draw(points: closed ? Array(canvas.dropLast()) : canvas, closed: closed)
    }

    /// `points` thinned to within `tolerance` points on screen.
    static func simplified(_ points: [SIMD2<Float>], tolerance: CGFloat, on screen: RefineScreen) -> [SIMD2<Float>] {
        let size = screen.picture
        guard size.width > 0, size.height > 0 else { return points }
        let onScreen = points.map { CGPoint(x: CGFloat($0.x) * size.width, y: CGFloat($0.y) * size.height) }
        return PenPath.simplified(onScreen, tolerance: tolerance).map {
            SIMD2(Float($0.x / size.width), Float($0.y / size.height))
        }
    }
}
