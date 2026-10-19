import Foundation
import PaintCore

/// `pbn refine`'s gestures.json: Refine's gestures as a painter makes them, points normalized to
/// the picture (0…1, origin top-left), as the screen's touches arrive.
///
///     {"screen": {"width": 960, "zoom": 1},
///      "gestures": [
///        {"tool": "pen", "points": [[x, y], ...]},                  a finger's samples
///        {"tool": "splitter", "points": [[x, y], ...]},             the Color Splitter's
///        {"tool": "shape", "shape": "line" | "rectangle" | "oval", "from": [x, y], "to": [x, y]},
///        {"tool": "shape", "shape": "curve", "from": [x, y], "to": [x, y], "bend": [x, y]},
///        {"tool": "eraser", "points": [[x, y], ...]},               one point is a dab
///        {"tool": "smartEraser", "at": [x, y]},
///        {"tool": "fill", "at": [x, y]},
///        {"tool": "undo"}, {"tool": "redo"}]}
///
/// `screen.width` is the picture's width on screen fitted (points; 960 by default, about a 13"
/// iPad's Refine), `zoom` how far it is zoomed in (1 to 12); a gesture may give its own `zoom`.
/// A curve without `bend` is laid straight. Any gesture may carry a `caption` for the sheet.
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
        var zoom: Double?
        var caption: String?
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
        fail("usage: pbn refine <photo> <gestures.json> --out <dir> [--template t.pbnt | --edges map.pgm --lines drawing.pgm] [generate options]")
    }
    let photo = loadImage(options.positional[0])
    guard let data = FileManager.default.contents(atPath: options.positional[1]) else { fail("cannot read \(options.positional[1])") }
    let script: RefineScript
    do { script = try JSONDecoder().decode(RefineScript.self, from: data) } catch { fail("cannot decode \(options.positional[1]): \(error)") }
    let outDir = URL(fileURLWithPath: out)
    try FileManager.default.createDirectory(at: outDir.appendingPathComponent("steps"), withIntermediateDirectories: true)

    let base: Template
    if let path = options.template {
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
    for (k, g) in script.gestures.enumerated() {
        let began = ContinuousClock.now
        let t = trail.template
        let screen = refineScreen(for: t, width: width, zoom: g.zoom ?? script.screen?.zoom ?? 1)
        let drawing = RefineGestures.drawingLines(of: t)
        let lines = RefineGestures.snapLines(drawing: drawing, canvas: screen.canvas, pending: [])
        let samples = (g.points ?? []).enumerated().map { point($0.element, "points[\($0.offset)]", k) }
        var marks: [[SIMD2<Float>]] = [samples]
        var edit: TemplateEditor.Edit?
        var step = RefineReport.Step(tool: g.tool, caption: g.caption, verdict: "none", picture: "", touches: "", milliseconds: 0)
        var target: [TemplateEditor.Edit]?

        switch g.tool {
        case "pen":
            edit = RefineGestures.pen(RefineGestures.trace(samples, on: screen), on: screen, snapping: lines)
        case "splitter":
            edit = RefineGestures.splitter(RefineGestures.trace(samples, on: screen), on: screen, snapping: lines)
        case "eraser":
            edit = RefineGestures.eraser(RefineGestures.trace(samples, on: screen), on: screen)
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
            default: fail("gesture \(k + 1): a shape is line, rectangle, oval or curve")
            }
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
            fail("gesture \(k + 1): unknown tool \(g.tool) (pen, splitter, shape, eraser, smartEraser, fill, undo, redo)")
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
            case .nothing:
                step.verdict = "nothing"
            case .declined(let why):
                step.verdict = "declined"
                step.declined = why
                switch painted {
                case .draw: step.toast = "That line couldn’t be drawn there."
                case .split: step.toast = "That area couldn’t be split there."
                case .erase, .eraseLine: step.toast = "That couldn’t be erased."
                case .fill: step.toast = "That shape couldn’t be filled."
                case .look, .repaint: step.toast = "Those colors couldn’t be changed."
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
        let name = String(format: "steps/%02d-%@", k + 1, g.tool)
        let canvasMarks = marks.filter { !$0.isEmpty }.map { (points: $0.map(screen.canvasPoint), rgb: touch, width: Float(1.5)) }
        try writePPM(bookRaster(trail.template), name + ".ppm", in: outDir)
        try writePPM(bookRaster(trail.template, marks: canvasMarks), name + "-touches.ppm", in: outDir)
        step.picture = name + ".ppm"
        step.touches = name + "-touches.ppm"
        var around = canvasMarks.flatMap(\.points)
        switch step.edit {
        case .draw(let points, _, _)?, .split(let points, _, _)?: around += points
        case .erase(let path, _)?: around += path
        case .eraseLine(let at, _)?, .fill(let at, _)?: around.append(at)
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
