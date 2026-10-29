import Foundation
import PaintCore

/// `pbn refine`'s gestures.json: Refine's gestures as a painter makes them, points normalized to
/// the picture (0…1, origin top-left), as the screen's touches arrive.
///
///     {"screen": {"width": 960, "zoom": 1},
///      "gestures": [
///        {"tool": "pen", "points": [[x, y], ...], "inked": true, "smoothing": 0.5, "snap": false},
///                                                                   a finger's samples; `inked`: ink alone;
///                                                                   `snap`: the Toolbox's Snap (on unless false)
///        {"tool": "splitter", "points": [[x, y], ...]},             the Color Splitter's
///        {"tool": "cellEdge", "points": [[x, y], ...]},             the Cell Edge's
///        {"tool": "shape", "shape": "line" | "rectangle" | "oval" | "polygon" | "star", "from": [x, y], "to": [x, y]},
///        {"tool": "shape", "shape": "curve", "from": [x, y], "to": [x, y], "bend": [x, y]},
///        {"tool": "eraser", "points": [[x, y], ...], "size": 20},   one point is a dab
///        {"tool": "merge", "points": [[x, y], ...]},                the Merge's drag
///        {"tool": "brush", "points": [[x, y], ...], "color": [L, a, b] | "rgb": [r, g, b] | "paint": n, "size": 12},
///                                                                   the Paint Brush's stroke
///        {"tool": "bucket", "at": [x, y], "color" | "rgb" | "paint"},  the Bucket
///        {"tool": "repaint", "paint": n | "fromRgb": [r, g, b], "color" | "rgb", "family": true},
///                                                                   Edit Paint: paint n becomes it
///        {"tool": "reshape", "points": [from, to], "target": "ink" | "edge"},
///                                                                   Bend Line's or Move Edge's drag
///        {"tool": "moveLabel", "points": [from, to]},               Move Number's drag
///        {"tool": "smartEraser", "at": [x, y]},
///        {"tool": "fill", "at": [x, y]},
///        {"tool": "undo"}, {"tool": "redo"}]}
///
/// `screen.width` is the picture's width on screen fitted (points; 960 by default, about a 13"
/// iPad's Refine), `zoom` how far it is zoomed in (1 to 12); a gesture may give its own `zoom`.
/// A pen's `smoothing` is the Pen's Smoothing (0 to 1: its line steadied on a string of up to
/// `RefineGestures.steadyString` points); an eraser's or a brush's `size` is its Size, its radius
/// on screen in points. Without them a pen is not steadied, an eraser's radius follows the view
/// (`RefineScreen.eraserRadius`) and a brush's is `RefineGestures.brushSize`.
/// A curve without `bend` is laid straight. A reshape without `target` grabs any line (an edge,
/// drawn or not, or a stroke); Bend Line's is `ink`, Move Edge's `edge`. Reshape and Move Number
/// reach a finger's width on screen (`RefineGestures.fingerReach`). A paint is `color` (OKLab), `rgb` (sRGB, 0…1, as
/// Refine's color picker resolves a color whatever the template's space) or `paint` (a number of the palette shown); a
/// brush or a bucket without one takes the photo's color under its point (the Eyedropper's). A repaint's toast is what
/// Edit Paint says (paints made alike, or nothing); a declined repaint, which the app keeps in refinements.json and
/// which changes nothing, is left out of edits.json. Any gesture may carry a `caption` for the sheet.
struct RefineScript: Decodable {
    struct Screen: Decodable {
        var width: Double?
        var zoom: Double?
    }
    struct Gesture: Decodable {
        var tool: String
        var shape: String?
        var points: [[Float]]?
        var from: [Float]?
        var to: [Float]?
        var bend: [Float]?
        var at: [Float]?
        var color: [Float]?
        /// A color as Refine's picker gives it: sRGB, 0...1.
        var rgb: [Float]?
        var paint: Int?
        /// A repaint's Similar Colors Too.
        var family: Bool?
        /// A repaint's paint picked as its swatch looks (sRGB, 0...1): the paint nearest it.
        var fromRgb: [Float]?
        /// A pen's line as the Toolbox's Pen draws it with Color from Photo off (its default): ink
        /// alone, the pieces it cuts keeping their paint (`RefineView.inked`).
        var inked: Bool?
        /// A pen's Smoothing, 0...1.
        var smoothing: Double?
        /// The Toolbox's Snap, on unless false: a pen's, a cell edge's or a shape's ends join the
        /// lines their ink touches.
        var snap: Bool?
        /// An eraser's or a brush's Size: its radius on screen, points.
        var size: Double?
        var zoom: Double?
        var caption: String?
        var target: String?
    }
    var screen: Screen?
    var gestures: [Gesture]
}

/// `pbn refine`'s refine.json: per gesture what Refine made of it.
struct RefineReport: Codable {
    struct Step: Codable {
        var tool: String
        var caption: String?
        /// The edit sent (EditCoding's shape, a drawn line with its paints), nil when the gesture
        /// made none (too short, a tap on no line, undo and redo).
        var edit: TemplateEditor.Edit?
        /// made, nothing, declined, none (no edit), cleared (a fill taken out), undo, redo.
        var verdict: String
        var declined: String?
        /// The toast Refine shows (`RefineNote`), in English.
        var toast: String?
        var regionsSplit = 0
        var recolored = 0
        var paintsAdded = 0
        var tooSmall = 0
        var joins = 0
        var strokes = 0
        var regionsMerged = 0
        /// A Merge's areas that Refine lit while the finger was down (`TemplateEditor.MergeProbe`).
        var lit: Int?
        /// The template after the gesture, and the same with its touches over it.
        var picture: String
        var touches: String
        /// Where the gesture was, canvas units [x0, y0, x1, y1]: its touches and its edit's points,
        /// padded (the sheet's close-ups).
        var focus: [Float]?
        var milliseconds: Double
    }
    var width: Int
    var height: Int
    var screen: Double
    var steps: [Step]
    var regions: Int
    var palette: Int
    var valid: Bool
    var validation: String
}

/// The screen a template is refined on: its picture `width` points wide fitted, zoomed `zoom`
/// times, the drawing's line as the app draws a book's at that zoom at the Regular weight
/// (`LineArtDrawing.lineWidth`, `ColoringBookLook.widthPoints`).
func refineScreen(for t: Template, width: Double, zoom: Double) -> RefineScreen {
    let aspect = Double(t.height) / Double(max(t.width, 1))
    let zoom = min(max(zoom, 1), 12)
    let line = max((1.5 + 0.7 * log2(zoom)) * min(zoom, 1), 0.5)
    return RefineScreen(
        canvas: CGSize(width: t.width, height: t.height), picture: CGSize(width: width * zoom, height: width * zoom * aspect),
        view: CGSize(width: width, height: width * aspect), lineWidth: CGFloat(line))
}

func runRefine(_ options: Options) throws {
    guard options.positional.count == 2, let out = options.out else {
        fail("usage: pbn refine <photo> <gestures.json> --out <dir> [--template t.pbnt | --blank | --edges map.pgm --lines drawing.pgm] [generate options]")
    }
    let photo = loadImage(options.positional[0])
    guard let data = FileManager.default.contents(atPath: options.positional[1]) else { fail("cannot read \(options.positional[1])") }
    let script: RefineScript
    do { script = try JSONDecoder().decode(RefineScript.self, from: data) } catch { fail("cannot decode \(options.positional[1]): \(error)") }
    let outDir = URL(fileURLWithPath: out)
    try FileManager.default.createDirectory(
        at: options.steps ? outDir.appendingPathComponent("steps") : outDir, withIntermediateDirectories: true)

    let base: Template
    if options.blank {
        // As the app starts from Blank (`ArtworkFactory.blank`).
        let size = options.settings.workingSize(sourceWidth: photo.width, sourceHeight: photo.height)
        do { base = try TemplateEditor.blank(width: size.width, height: size.height, photo: photo, colorSpace: photo.colorSpace) } catch {
            fail("no blank canvas: \(error)")
        }
    } else if let path = options.template {
        guard let bytes = FileManager.default.contents(atPath: path) else { fail("cannot read \(path)") }
        do { base = try Template(encoded: bytes) } catch { fail("cannot decode \(path): \(error)") }
    } else {
        // The app makes every template a coloring book.
        var settings = options.settings
        if options.lineStyle == nil { settings.lineArt = lineArtSettings(.coloringBook, fields: options.lineArtFields) }
        guard let input = loadLineArt(options) else { fail("pbn refine needs a coloring book: --edges (and --lines) or --template") }
        do {
            base = try TemplateGenerator(settings: settings).generate(from: photo, importance: loadImportance(options.importance), lineArt: input, cancel: .none).template
        } catch { fail("generation failed: \(error)") }
    }
    guard base.lineArt != nil else { fail("the template has no line art: Refine edits coloring books") }
    try base.encoded().write(to: outDir.appendingPathComponent("before.pbnt"))
    try writePPM(bookRaster(base), "before.ppm", in: outDir)

    let width = script.screen?.width ?? 960
    var trail = EditTrail(base: base)
    var undo: [[TemplateEditor.Edit]] = [], redo: [[TemplateEditor.Edit]] = []
    var steps: [RefineReport.Step] = []
    let touch = SIMD3<Float>(0.9, 0.1, 0.6)

    func point(_ p: [Float]?, _ what: String, _ k: Int) -> SIMD2<Float> {
        guard let p, p.count == 2 else { fail("gesture \(k + 1): \(what) is [x, y]") }
        return SIMD2(p[0], p[1])
    }
    /// A gesture's paint: `color` (OKLab), `rgb` (the picker's), or paint number `paint` of `t`.
    func chosen(_ g: RefineScript.Gesture, on t: Template, _ k: Int) -> SIMD3<Float>? {
        if let c = g.color {
            guard c.count == 3 else { fail("gesture \(k + 1): color is OKLab [L, a, b]") }
            return SIMD3(c[0], c[1], c[2])
        }
        if let c = g.rgb {
            guard c.count == 3 else { fail("gesture \(k + 1): rgb is [r, g, b], 0...1") }
            // As the app's pickers do: resolved in sRGB whatever the template's space.
            let linear = SIMD3(ColorScience.decodeSRGB(c[0]), ColorScience.decodeSRGB(c[1]), ColorScience.decodeSRGB(c[2]))
            return ColorScience.linearSRGBToOKLab(linear)
        }
        if let n = g.paint {
            guard (1...t.palette.count).contains(n) else { fail("gesture \(k + 1): there is no paint \(n)") }
            return t.palette[n - 1].oklab
        }
        return nil
    }
    /// A pen's `smoothing`, 0 without one.
    func smoothing(of g: RefineScript.Gesture, _ k: Int) -> CGFloat {
        guard let s = g.smoothing else { return 0 }
        guard (0...1).contains(s) else { fail("gesture \(k + 1): smoothing is 0...1") }
        return CGFloat(s)
    }
    /// An eraser's or a brush's `size`, points on screen.
    func size(of g: RefineScript.Gesture, _ k: Int) -> CGFloat? {
        guard let s = g.size else { return nil }
        guard s > 0, s.isFinite else { fail("gesture \(k + 1): size is a radius on screen, points above 0") }
        return CGFloat(s)
    }
    for (k, g) in script.gestures.enumerated() {
        let began = ContinuousClock.now
        let t = trail.template
        let screen = refineScreen(for: t, width: width, zoom: g.zoom ?? script.screen?.zoom ?? 1)
        let drawing = RefineGestures.drawingLines(of: t)
        // The Toolbox's Snap: off, the ends stay where the finger left them.
        let lines = g.snap == false ? nil : RefineGestures.snapLines(drawing: RefineGestures.drawingLines(of: t, writing: false), canvas: screen.canvas, pending: [])
        let samples = (g.points ?? []).enumerated().map { point($0.element, "points[\($0.offset)]", k) }
        var marks: [[SIMD2<Float>]] = [samples]
        var edit: TemplateEditor.Edit?
        var step = RefineReport.Step(tool: g.tool, caption: g.caption, verdict: "none", picture: "", touches: "", milliseconds: 0)
        var target: [TemplateEditor.Edit]?

        switch g.tool {
        case "pen":
            edit = RefineGestures.pen(
                RefineGestures.trace(samples, on: screen), on: screen, snapping: lines, smoothing: smoothing(of: g, k))
            if g.inked == true, case .draw(let points, let closed, nil)? = edit { edit = .draw(points: points, closed: closed, paints: []) }
        case "splitter":
            edit = RefineGestures.splitter(RefineGestures.trace(samples, on: screen), on: screen, snapping: lines)
        case "cellEdge":
            edit = RefineGestures.cellEdge(RefineGestures.trace(samples, on: screen), on: screen, snapping: lines)
        case "eraser":
            edit = RefineGestures.eraser(RefineGestures.trace(samples, on: screen), on: screen, size: size(of: g, k))
        case "merge":
            edit = RefineGestures.merge(RefineGestures.trace(samples, on: screen), on: screen)
            if case .merge(let path)? = edit { step.lit = (try? TemplateEditor.MergeProbe(t))?.areas(along: path).count }
        case "brush":
            let color: SIMD3<Float>
            if let c = chosen(g, on: t, k) {
                color = c
            } else if let first = samples.first {
                color = LineEdit.photoColor(at: first, in: photo)
            } else {
                fail("gesture \(k + 1): a brush needs points")
            }
            edit = RefineGestures.brush(
                RefineGestures.trace(samples, on: screen), on: screen, color: color, size: size(of: g, k) ?? RefineGestures.brushSize)
        case "reshape":
            guard samples.count == 2 else { fail("gesture \(k + 1): a reshape's points are [from, to]") }
            edit = RefineGestures.reshape(
                from: samples[0], to: samples[1], on: screen, target: reshapeTarget(g.target, "gesture \(k + 1): a reshape's"))
        case "moveLabel":
            guard samples.count == 2 else { fail("gesture \(k + 1): a moveLabel's points are [from, to]") }
            edit = RefineGestures.moveLabel(from: samples[0], to: samples[1], on: screen)
        case "shape":
            let a = point(g.from, "from", k), b = point(g.to, "to", k)
            marks = [[a, b]]
            switch g.shape {
            case "curve":
                if let ends = RefineGestures.curveEnds(from: a, to: b, on: screen, snapping: lines) {
                    if g.bend != nil {
                        let bend = point(g.bend, "bend", k)
                        marks.append([bend])
                        edit = RefineGestures.shape(.curve, from: bend, to: bend, curve: ends, on: screen, snapping: lines)
                    } else {
                        edit = RefineGestures.straightCurve(from: ends.from, to: ends.to, on: screen)
                    }
                }
            case "line": edit = RefineGestures.shape(.line, from: a, to: b, on: screen, snapping: lines)
            case "rectangle": edit = RefineGestures.shape(.rectangle, from: a, to: b, on: screen, snapping: lines)
            case "oval": edit = RefineGestures.shape(.oval, from: a, to: b, on: screen, snapping: lines)
            case "polygon": edit = RefineGestures.shape(.polygon, from: a, to: b, on: screen, snapping: lines)
            case "star": edit = RefineGestures.shape(.star, from: a, to: b, on: screen, snapping: lines)
            default: fail("gesture \(k + 1): a shape is line, rectangle, oval, polygon, star or curve")
            }
        case "bucket":
            // The Bucket with the current paint, or the Eyedropper's color of the photo there.
            let at = point(g.at, "at", k)
            marks = [[at]]
            edit = .paintArea(at: screen.canvasPoint(at), color: chosen(g, on: t, k) ?? LineEdit.photoColor(at: at, in: photo))
        case "repaint":
            // Edit Paint: paint `paint` (or the one whose swatch looks like `fromRgb`) becomes `color` or `rgb`.
            var picked = g.paint
            if let c = g.fromRgb {
                guard c.count == 3, g.paint == nil else { fail("gesture \(k + 1): a repaint names its paint by `paint` or by a `fromRgb` of three values") }
                let want = ColorScience.linearSRGBToOKLab(
                    SIMD3(ColorScience.decodeSRGB(c[0]), ColorScience.decodeSRGB(c[1]), ColorScience.decodeSRGB(c[2])))
                picked = t.palette.indices.min { ColorScience.distance(t.palette[$0].oklab, want) < ColorScience.distance(t.palette[$1].oklab, want) }
                    .map { $0 + 1 }
            }
            guard let n = picked, (1...t.palette.count).contains(n) else { fail("gesture \(k + 1): a repaint needs its paint") }
            var to = g
            to.paint = nil
            guard let color = chosen(to, on: t, k) else { fail("gesture \(k + 1): a repaint needs a color or rgb") }
            marks = []
            edit = .repaint(from: t.palette[n - 1].oklab, to: color, family: g.family ?? false)
        case "smartEraser":
            let at = point(g.at, "at", k)
            marks = [[at]]
            edit = RefineGestures.lineEraser(at: at, on: screen, chains: LineChains(lines: drawing))?.edit
        case "fill":
            let at = point(g.at, "at", k)
            marks = [[at]]
            let canvasAt = screen.canvasPoint(at)
            let cleared = EditFills.cleared(by: canvasAt, edits: trail.edits, on: t)
            if cleared.isEmpty {
                edit = .fill(at: canvasAt, color: LineEdit.photoColor(at: at, in: photo))
            } else {
                target = trail.edits.indices.filter { !cleared.contains($0) }.map { trail.edits[$0] }
                step.verdict = "cleared"
            }
        case "undo":
            if let previous = undo.popLast() {
                redo.append(trail.edits)
                target = previous
            }
            step.verdict = "undo"
        case "redo":
            if let next = redo.popLast() {
                undo.append(trail.edits)
                target = next
            }
            step.verdict = "redo"
        default:
            fail("gesture \(k + 1): unknown tool \(g.tool) (pen, splitter, cellEdge, shape, eraser, merge, brush, bucket, repaint, reshape, moveLabel, smartEraser, fill, undo, redo)")
        }

        if let target {
            if step.verdict == "cleared" {
                undo.append(trail.edits)
                redo.removeAll()
            }
            try trail.move(to: target)
        } else if let edit {
            // As the app lays it (`CreateModel.laying`): a drawn line with the photo's colors.
            let painted = TemplateEditor.painted(edit, on: t, photo: photo)
            step.edit = painted
            let (_, outcome) = try TemplateEditor.apply(painted, to: t)
            let before = trail.edits
            switch trail.add(painted) {
            case .made(let tooSmall):
                undo.append(before)
                redo.removeAll()
                step.verdict = "made"
                if tooSmall { step.toast = "That shape is too small for a number." }
                // Edit Paint says only this (`CreateModel.recolor`).
                if case .repaint = painted, trail.template.palette.count < t.palette.count {
                    step.toast = "Colors that came out alike share a number now."
                }
            case .nothing:
                step.verdict = "nothing"
            case .declined(let why):
                step.verdict = "declined"
                step.declined = why
                switch painted {
                case .draw: step.toast = "That line couldn’t be drawn there."
                case .split: step.toast = "That area couldn’t be split there."
                case .cellEdge: step.toast = "That area couldn’t be divided there."
                case .merge:
                    step.toast = why == TemplateEditor.mergeStaysInOneArea ? "That’s already one area." : "Those areas couldn’t be joined."
                case .brush: step.toast = "That couldn’t be painted there."
                case .reshape: step.toast = "That line couldn’t be moved there."
                case .moveLabel: step.toast = "There’s no room for that number there."
                case .erase, .eraseLine: step.toast = "That couldn’t be erased."
                case .fill: step.toast = "That shape couldn’t be filled."
                case .paintArea, .look: step.toast = "Those colors couldn’t be changed."
                case .repaint: break
                }
            }
            step.regionsSplit = outcome.regionsSplit
            step.recolored = outcome.recolored
            step.paintsAdded = outcome.paintsAdded
            step.tooSmall = outcome.tooSmall.count
            step.joins = outcome.joins
            step.strokes = outcome.strokes
            step.regionsMerged = outcome.regionsMerged
        }
        let took = ContinuousClock.now - began
        step.milliseconds = Double(took.components.seconds) * 1000 + Double(took.components.attoseconds) / 1e15
        let canvasMarks = marks.filter { !$0.isEmpty }.map { (points: $0.map(screen.canvasPoint), rgb: touch, width: Float(1.5)) }
        if options.steps {
            let name = String(format: "steps/%02d-%@", k + 1, g.tool)
            try writePPM(bookRaster(trail.template), name + ".ppm", in: outDir)
            try writePPM(bookRaster(trail.template, marks: canvasMarks), name + "-touches.ppm", in: outDir)
            step.picture = name + ".ppm"
            step.touches = name + "-touches.ppm"
        }
        var around = canvasMarks.flatMap(\.points)
        switch step.edit {
        case .draw(let points, _, _)?, .split(let points, _, _)?, .cellEdge(let points, _)?: around += points
        case .erase(let path, _)?, .merge(let path)?, .brush(let path, _, _)?: around += path
        case .reshape(let from, let to, _, _)?, .moveLabel(let from, let to, _)?: around += [from, to]
        case .eraseLine(let at, _)?, .fill(let at, _)?, .paintArea(let at, _)?: around.append(at)
        case .look?, .repaint?, nil: break
        }
        if let first = around.first {
            var lo = first, hi = first
            for p in around { lo = pointwiseMin(lo, p); hi = pointwiseMax(hi, p) }
            // Touches past the picture's edge would turn the box inside out.
            let corner = SIMD2(Float(t.width), Float(t.height))
            lo = lo.clamped(lowerBound: .zero, upperBound: corner)
            hi = hi.clamped(lowerBound: .zero, upperBound: corner)
            let pad = max(30, 0.25 * max(hi.x - lo.x, hi.y - lo.y))
            step.focus = [max(lo.x - pad, 0), max(lo.y - pad, 0), min(hi.x + pad, Float(t.width)), min(hi.y + pad, Float(t.height))]
        }
        steps.append(step)
    }

    let result = trail.template
    let report = result.validate(minLabelRadius: LabelSizing.minimumRadius)
    try result.encoded().write(to: outDir.appendingPathComponent("template.pbnt"))
    try writePPM(bookRaster(result), "after.ppm", in: outDir)
    try writePPM(photo, "photo.ppm", in: outDir)
    try jsonEncoder().encode(trail.edits).write(to: outDir.appendingPathComponent("edits.json"))
    let json = try jsonEncoder().encode(RefineReport(
        width: result.width, height: result.height, screen: width, steps: steps, regions: result.regions.count,
        palette: result.palette.count, valid: report.isValid, validation: "\(report)"))
    try json.write(to: outDir.appendingPathComponent("refine.json"))
    print(String(data: json, encoding: .utf8)!)
}
