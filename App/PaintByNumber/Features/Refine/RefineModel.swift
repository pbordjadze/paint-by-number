import Accessibility
import Foundation
import Observation
import PaintCore
import SwiftUI
import UIKit

/// The Refine screen's state and what its gestures do with it (`RefineView` draws it and lays its
/// tools out): the tool in hand and its group, the layers, the template the screen draws over
/// (`base`) with the edits sent that it doesn't show yet (`submitted`), the stroke under the
/// finger, the current paint, the cell picked and its card. A touch from the canvas
/// (`RefineTouchSurface`) comes here (`draw`, `tap`, `held`, `hovered`, `dropped`, the Pencil's
/// `pencil`), is made one PaintCore edit by `RefineGestures` on the screen as it stands
/// (`screen`), and goes to the create flow's queue (`CreateModel.edit(_:)`); `land` then brings
/// `base` up to date with the template the flow made.
///
/// One per screen, owned by its view (a practice canvas made again has a new one). It starts no
/// work when made: the view makes one with every `init` and keeps the first.
@Observable
final class RefineModel {
    /// The create flow the screen refines.
    let model: CreateModel
    /// A Tool Guide page's practice canvas: the tool it teaches, kept (`pick`), and no tips.
    let practice: RefinePracticeSetup?

    /// Where the screen shows and how the painter's tools are set: what the gestures need of the
    /// view's environment and of the settings its controls keep (the painter's, or a practice
    /// canvas's own, `RefinePracticeSetup.settings`). The view keeps it current.
    struct Surroundings: Equatable {
        var reduceMotion = false
        /// Every tool stands in a rail along the leading edge (iPad), where an area's card opens
        /// beside its area.
        var usesRail = false
        var lineWeight = LineWeight.default
        /// Whether a line's ends join the lines they land near (`PenAssist`): the Toolbox's Snap.
        var snaps = SettingsDefault.refineSnaps
        /// Whether a drawn line gives the pieces it cuts the photo's colors (`TemplateEditor.painted`):
        /// the Toolbox's Color from Photo.
        var penColors = SettingsDefault.refinePenColors
        /// The Paint Brush's Size: its radius on screen, in points.
        var brushSize = SettingsDefault.refineBrushSize
        /// The Eraser's and the Line Eraser's Size: their radius on screen, in points.
        var eraserSize = SettingsDefault.refineEraserSize
        /// The Pen's Smoothing, 0 to 1 (`RefineGestures.steadied`, Procreate's StreamLine).
        var penSmoothing = SettingsDefault.refinePenSmoothing
    }

    var surroundings = Surroundings()

    private var reduceMotion: Bool { surroundings.reduceMotion }
    private var usesRail: Bool { surroundings.usesRail }
    private var lineWeight: LineWeight { surroundings.lineWeight }
    private var snaps: Bool { surroundings.snaps }
    private var penColors: Bool { surroundings.penColors }
    private var brushSize: Double { surroundings.brushSize }
    private var eraserSize: Double { surroundings.eraserSize }
    private var penSmoothing: Double { surroundings.penSmoothing }

    var tool = RefineTool.pen
    /// The tool picked before this one, for the Pencil's Switch to Previous Tool.
    var previousTool: RefineTool?
    var shape = RefineShape.line
    /// What shows: the numbers, the ink, the paint and the photo (`RefineLayers`).
    var layers = RefineLayers.painting
    /// The Layers panel is open.
    var showsLayers = false
    /// The template on screen painted, for the paint layer, with its preview's id.
    var painting: (preview: UUID, image: CGImage)?
    /// Whether the painting that landed last cross-fades in (`land`).
    var paintingFades = false
    /// The template the screen draws over: the newest at full resolution.
    var base: CreateModel.Preview?
    /// The edits sent that `base` doesn't show yet, which the screen draws over it.
    var submitted: [Submitted] = []
    /// The pen's line or the eraser's pass under the finger, until it lifts; for Shapes, where
    /// the drag began and where the finger is.
    var trace: [SIMD2<Float>]?
    /// The lines a pen's ends may join, as its stroke began.
    var snapLines: SnapLines?
    /// A curve's ends, drawn and waiting for the drag that bends it.
    var curve: (from: SIMD2<Float>, to: SIMD2<Float>)?
    /// The line of text being dragged out: where the drag began and where it is.
    var marking: (SIMD2<Float>, SIMD2<Float>)?
    /// The line the eraser was last tapped on, which flashes as it goes.
    var tapped: [SIMD2<Float>]?
    var flashes = false
    /// Where the picture is in the canvas, and its zoom (the touch surface's).
    var picture: CGRect = .zero
    var zoom: CGFloat = 1
    var canvasSize: CGSize = .zero
    /// Edit Paint's family follows the current paint while it is on.
    var colorFamily = true
    /// A part of the picture the touch surface is to bring up close.
    var focus: RefineFocus?
    #if DEBUG
    /// The demo's paint, cell or card is picked once its edits have landed.
    @ObservationIgnored var didPickDemoPaint = false
    /// Where the demo's card points (canvas units): the band Select's cell brings moves the
    /// picture after the card opened, so the card points again where the picture lands.
    @ObservationIgnored var demoCardAt: SIMD2<Float>?
    #endif
    /// The screen has begun refining (`CreateModel.beginRefining`), once.
    var opened = false
    /// The Eyedropper's hold under the finger: where it is and the color it would pick.
    var hold: RefineHold?
    /// What the Pencil's hover shows for the tool in hand (`hoverMark(at:)`), and the cell a
    /// swatch's drag is over: kept only as they change, so a hover's every move doesn't lay the
    /// screen out again.
    var hovering: RefineHoverMark.Mark?
    var dropCell: Int?
    /// The tools, bars and palette are hidden (a four-finger tap), the picture alone on screen.
    var fullScreen = false
    /// Counts the full screen's comings and goings, after which the canvas takes the keys again.
    var keysRequest = 0
    /// Where the Pencil asked for the tools and the palette (its double tap or squeeze), in the
    /// canvas's coordinates.
    var pencilPalette: CGRect?
    /// The current paint (OKLab, as on screen): the Bucket gives it, the palette, the Eyedropper
    /// and Edit Paint pick it. A color no paint has yet becomes one with the first Bucket tap.
    var currentPaint: SIMD3<Float>?
    /// The colors the color wheel picked that no paint has yet, in order: the palette shows them
    /// as new paints, so several picked in a row wait side by side to be poured (QA, November 3:
    /// only the last was kept). A color leaves once a paint has it (`landedColors`).
    var newColors: [SIMD3<Float>] = []
    /// The last repaint of the current paint sent, until a template has it (`RefinePalette.landing`):
    /// its paint is then the current one. Made current as the repaint was sent, before any
    /// template had it, the paint was none for a moment and the picker's next picks went nowhere
    /// (QA, October 26).
    var repainted: RefinePalette.Repainted?
    /// The cell Select picked, by a point in it (canvas units), so it follows its region through
    /// edits.
    var selection: SIMD2<Float>?
    /// The undrawn edges of the template on screen, made once per template (`RefineCellEdges`).
    var cellEdges: (id: UUID, path: Path)?
    /// Try Painting's painting, while it is open.
    var trial: RefineTrial?
    /// The Studio's group on screen (`RefineGroup`), and the tool last picked in each.
    var group = RefineGroup.ink
    var lastTool: [RefineGroup: RefineTool] = [:]
    /// The area whose card Select's Change Color opened (`RefineAreaCard`): beside the area on
    /// iPad, in Select's bar on iPhone (`barCard`), where nothing covers the picture.
    var card: RefineAreaPick?
    var barCard: RefineAreaPick?
    /// The sparkles where a line closed off an area last: the line's number, where its ends met
    /// on screen, and the shape's smaller side on screen.
    var sparkles: (id: Int, point: CGPoint, extent: CGFloat)?
    /// What a Merge drag joins, lit while the finger is down: the probe of the template on screen
    /// (with its preview's id), the areas found for the drag so far, and the drag waiting for
    /// the probe while it works on an earlier one.
    var mergeProbe: (preview: UUID, probe: TemplateEditor.MergeProbe)?
    var mergeAreas: [Int] = []
    var mergeWanted: [SIMD2<Float>]?
    var mergeProbing = false
    /// The Merge drag the lit areas are for: one found for an earlier drag never lights this one.
    var mergeStroke = 0
    /// The areas whose numbers are near the smallest (`RefineTinyAreas`), and the one shown last.
    var tiny: [(region: Int, label: PaintCore.Label)] = []
    var tinyShown = -1
    /// The tiny area the badge brought up close, glowing with the numbers shown, whatever Layers
    /// says, until the painter does something else: the zoom showed no number and marked nothing
    /// (QA, November 7). Move Number's numbers show so too.
    var tinyMarked: Int?
    /// The Tool Guide, open at a page.
    var guide: RefineGuideTopic?

    /// The screen's state as it opens on `model`'s template, or with `practice` a Tool Guide
    /// page's practice canvas on its tool.
    init(model: CreateModel, practice: RefinePracticeSetup?) {
        self.model = model
        self.practice = practice
        // Never a draft: its canvas is smaller than the one the edits will be laid on.
        base = model.preview.flatMap { $0.isDraft ? nil : $0 }
        // The Studio opens on the painting in its paints (the Lamplit Table, 6 to 0).
        if let practice {
            tool = practice.tool
            group = RefineGroup.of(practice.tool)
            layers = practice.layers
            if let shape = practice.shape { self.shape = shape }
            return
        }
        #if DEBUG
        if let demo = ShellDemo.current {
            let opens: RefineTool? =
                demo.picksColorPaint ? .editPaint : demo.opensColors ? .looks : demo.selectsCell || demo.opensCard ? .select : nil
            if let opens {
                tool = opens
                group = RefineGroup.of(opens)
            }
            if let topic = demo.opensGuide { guide = topic }
        }
        #endif
    }

    /// Whether this is a Tool Guide page's practice canvas.
    var isPractice: Bool {
        practice != nil
    }

    // MARK: Screen

    /// Whether the painting shows beneath the drawing: its layer is on.
    var showsPainting: Bool { layers.paint }

    /// The template's canvas, in canvas units (zero before there is a template).
    var templateSize: CGSize { base?.drawing.size ?? .zero }

    /// A picture point (0…1) in the template's canvas units.
    func canvasPoint(_ p: SIMD2<Float>) -> SIMD2<Float> {
        let size = templateSize
        return SIMD2(p.x * Float(size.width), p.y * Float(size.height))
    }

    /// A point of the picture (0…1) on screen.
    func onScreen(_ p: SIMD2<Float>) -> CGPoint {
        CGPoint(x: picture.minX + CGFloat(p.x) * picture.width, y: picture.minY + CGFloat(p.y) * picture.height)
    }

    /// A point in canvas units as a point of the picture (0…1).
    func picturePoint(_ p: SIMD2<Float>) -> SIMD2<Float> {
        let size = templateSize
        guard size.width > 0, size.height > 0 else { return .zero }
        return SIMD2(p.x / Float(size.width), p.y / Float(size.height))
    }

    /// Canvas points normalized to the picture.
    func normalized(_ points: [SIMD2<Float>]) -> [SIMD2<Float>] {
        let size = SIMD2(Float(max(templateSize.width, 1)), Float(max(templateSize.height, 1)))
        return points.map { $0 / size }
    }

    var aspectRatio: CGFloat {
        guard let image = model.source?.image, image.width > 0, image.height > 0 else { return 1 }
        return CGFloat(image.width) / CGFloat(image.height)
    }

    /// The drawing's line on screen, as the preview and the canvas draw it at this size.
    var lineWidth: CGFloat {
        (base?.drawing ?? model.preview?.drawing)?.lineWidth(scale: zoom, weight: lineWeight) ?? 1.5
    }

    /// The eraser keeps its Size on screen, so zoomed in it erases finer (`RefineScreen.eraserRadius(size:)`).
    var eraserRadius: Float { screen.eraserRadius(size: CGFloat(eraserSize)) }

    /// The screen as the gestures see it (`RefineGestures`, which `pbn refine` replays too).
    var screen: RefineScreen {
        RefineScreen(canvas: templateSize, picture: picture.size, view: canvasSize, lineWidth: lineWidth)
    }

    /// How near a drag must begin to a line or a number to take it: a finger's reach on screen, in
    /// canvas units (`RefineGestures.fingerReach`, as the edits it sends).
    var fingerReach: Float {
        picture.width > 0 ? Float(RefineGestures.fingerReach * templateSize.width / picture.width) : TemplateEditor.tapReach
    }

    /// The Tool Guide or Try Painting covers the screen.
    var isCovered: Bool { guide != nil || trial != nil }

    /// Start From is asked until the first edit, on a template with a photo to generate from,
    /// and out of the way while a note shows.
    var showsStartFrom: Bool {
        model.refinements.edits.isEmpty && submitted.isEmpty && model.hasLineArtInput && !model.isScratch && model.note == nil
    }

    // MARK: What shows until an edit lands

    /// An edit sent to the model, which draws it until the template on screen has it.
    struct Submitted: Identifiable {
        /// Its number (`CreateModel.edit(_:)`).
        let id: Int
        let edit: TemplateEditor.Edit
        /// A line tapped away, as the tap found it, normalized.
        var chain: [SIMD2<Float>]?
        /// A line Bend Line moved, as it was and as it goes, normalized, which shows until the
        /// template has it.
        var bent: (original: [SIMD2<Float>], moved: [SIMD2<Float>])?
        /// A swatch of the photo's color shows where a fill was tapped, until the template has it.
        var showsSwatch = false
    }

    /// The edits sent that the template on screen doesn't show yet, as the lines the ink layer
    /// draws (normalized to the picture). Fills change no line (`RefineFillLayer` shows them).
    var pending: [TemplateRefinements.Line] {
        let size = templateSize
        guard size.width > 0, size.height > 0 else { return [] }
        let long = Float(max(size.width, size.height))
        func normalized(_ p: SIMD2<Float>) -> SIMD2<Float> { SIMD2(p.x / Float(size.width), p.y / Float(size.height)) }
        var lines: [TemplateRefinements.Line] = []
        for item in submitted {
            switch item.edit {
            case .draw(let points, let closed, _):
                lines.append(.init(kind: .draw, radius: 0, points: (closed ? points + points.prefix(1) : points).map(normalized)))
            case .erase(let path, let radius):
                lines.append(.init(kind: .erase, radius: radius / long, points: path.map(normalized)))
            case .eraseLine:
                if let chain = item.chain { lines.append(.init(kind: .eraseLine, radius: 0, points: chain)) }
            case .reshape:
                // A line Bend Line moved: gone from where it was, drawn where it goes.
                if let bent = item.bent {
                    lines.append(.init(kind: .eraseLine, radius: 0, points: bent.original))
                    lines.append(.init(kind: .draw, radius: 0, points: bent.moved))
                }
            case .fill, .split, .cellEdge, .merge, .brush, .look, .repaint, .paintArea, .moveLabel:
                // `RefineFillLayer` shows fills, `brushes` the brush's strokes; a split, a cell
                // edge, a merge and paint draw nothing.
                break
            }
        }
        return lines
    }

    /// Where the fills the template on screen has were tapped (normalized to the picture): its
    /// edits', and the lines builds before them filled through the generator.
    var filledPoints: [SIMD2<Float>] {
        guard let base else { return [] }
        let size = SIMD2(Float(base.template.width), Float(base.template.height))
        var points = base.refinements.lines.filter { $0.kind == .fill }.compactMap(\.points.first)
        for case .fill(let at, _) in base.refinements.edits { points.append(at / size) }
        return points
    }

    /// The fills sent that the template on screen doesn't show yet, normalized to the picture.
    var swatches: [RefineFillLayer.Swatch] {
        let size = SIMD2(Float(templateSize.width), Float(templateSize.height))
        guard size.x > 0, size.y > 0 else { return [] }
        return submitted.compactMap { item in
            guard item.showsSwatch, case .fill(let at, let color) = item.edit else { return nil }
            return RefineFillLayer.Swatch(point: at / size, color: color)
        }
    }

    /// The brush's strokes sent that the template on screen doesn't show yet, and the one under
    /// the finger, as `RefineInkLayer` lays them.
    var brushes: [RefineInkLayer.Brush] {
        let size = templateSize
        guard size.width > 0, size.height > 0, let space = base?.template.colorSpace else { return [] }
        let long = Float(max(size.width, size.height))
        var strokes: [RefineInkLayer.Brush] = submitted.compactMap { item in
            guard case .brush(let path, let radius, let color) = item.edit else { return nil }
            return .init(
                points: path.map { SIMD2($0.x / Float(size.width), $0.y / Float(size.height)) }, radius: radius / long,
                color: RefinePalette.color(color, space: space))
        }
        if tool == .brush, let trace, let color = currentPaint {
            strokes.append(.init(points: trace, radius: screen.brushRadius(size: CGFloat(brushSize)), color: RefinePalette.color(color, space: space)))
        }
        return strokes
    }

    /// The line Bend Line (ink) or Move Edge (a cell's edge) holds, as it was and moved to the
    /// finger (canvas units), the same moved points the edit will lay (`TemplateEditor.reshapedChain`).
    var bend: (original: [SIMD2<Float>], moved: [SIMD2<Float>])? {
        guard tool == .bendLine || tool == .moveEdge, let trace, trace.count == 2, let template = base?.template,
              picture.width > 0, screen.onScreenLength(trace[1] - trace[0]) >= 1
        else { return nil }
        return TemplateEditor.reshapedChain(
            on: template, from: canvasPoint(trace[0]), to: canvasPoint(trace[1]), reach: fingerReach,
            target: tool == .bendLine ? .ink : .edge)
    }

    /// The number Move Number holds (its paint's index), the one the edit will move
    /// (`TemplateEditor.labelNear`), and where the finger has it, normalized.
    var heldNumber: (paint: Int, at: SIMD2<Float>)? {
        guard tool == .moveNumber, let trace, trace.count == 2, let template = base?.template,
              let held = TemplateEditor.labelNear(on: template, at: canvasPoint(trace[0]), reach: fingerReach)
        else { return nil }
        return (Int(template.regions[held.region].colorIndex), trace[1])
    }

    /// The stroke under the finger as it shows: the Pen's steadied by its Smoothing, as it will be
    /// laid (`RefineGestures.steadied`); the others as drawn.
    var penTrace: [SIMD2<Float>]? {
        guard let trace, tool == .pen, penSmoothing > 0 else { return trace }
        return RefineGestures.steadied(trace, smoothing: CGFloat(penSmoothing), on: screen)
    }

    /// The shape under the finger, or a curve waiting to be bent, as `RefineInkLayer` draws it.
    var shapeTrace: [SIMD2<Float>]? {
        guard tool == .shape, trace != nil || curve != nil else { return nil }
        return shapeFigure()?.map(screen.picturePoint)
    }

    /// The areas that glow: the tiny one the badge brought up close, those a Merge drag joins, a
    /// card's paint's, the cell Select picked, or Edit Paint's paint's.
    var glowAreas: [Int] {
        guard let template = base?.template else { return [] }
        if let tinyMarked, tinyMarked < template.regions.count { return [tinyMarked] }
        if tool == .merge, trace != nil, let probe = mergeProbe, probe.preview == base?.id { return mergeAreas }
        if let card = card ?? barCard, let region = template.region(at: card.at) {
            return RefinePaintGlow.areas(of: Int(template.regions[region].colorIndex), in: template)
        }
        if tool == .select, let region = selectedRegion { return [region] }
        if tool == .editPaint, let index = currentIndex { return RefinePaintGlow.areas(of: index, in: template) }
        return []
    }

    // MARK: Touches

    func draw(_ touch: RefineTouch, at point: SIMD2<Float>) {
        if touch == .began { tinyMarked = nil }
        // Last, after the touch's own changes (`show`).
        defer { if touch == .began { revealLayer() } }
        switch tool {
        case .pen, .cellEdge, .merge, .brush, .eraser, .smartEraser: follow(touch, at: point)
        case .shape: drawShape(touch, at: point)
        case .text: mark(touch, at: point)
        // A fill is a tap, and so are selecting, painting a cell and picking a paint: a drag
        // does nothing.
        case .bendLine, .moveEdge, .moveNumber: drag(touch, at: point)
        case .fill, .select, .bucket, .eyedropper, .editPaint, .looks, .tryPainting: break
        }
    }

    /// The pen's line or the eraser's pass follows the finger; when it lifts, it is laid on the
    /// template, the pen's as it showed.
    func follow(_ touch: RefineTouch, at point: SIMD2<Float>) {
        switch touch {
        case .began:
            trace = [point]
            snapLines = tool.erases || tool == .merge || tool == .brush || !snapsOn ? nil : currentSnapLines()
            if tool == .merge { probeMerge() }
        case .moved:
            // Samples closer than a point add nothing the line shows.
            guard var current = trace, let last = current.last, screen.onScreenLength(point - last) >= 1 else { return }
            current.append(point)
            trace = current
            if tool == .merge { light(current) }
        case .ended:
            guard var current = trace else { return }
            current.append(point)
            let edit = tool.erases ? eraserEdit(current)
                : tool == .cellEdge ? RefineGestures.cellEdge(current, on: screen, snapping: snapLines)
                : tool == .merge ? RefineGestures.merge(current, on: screen)
                : tool == .brush ? brushEdit(current)
                : penEdit(current)
            endStroke()
            if let edit { submit(edit) }
        case .cancelled:
            endStroke()
        }
    }

    /// Sends an edit to the template (`CreateModel.edit(_:)`), which draws it in a moment; until
    /// then it shows over the template (`pending`).
    func submit(
        _ edit: TemplateEditor.Edit, chain: [SIMD2<Float>]? = nil, bent: (original: [SIMD2<Float>], moved: [SIMD2<Float>])? = nil
    ) {
        let edit = inked(edit)
        submitted.append(Submitted(id: model.edit(edit), edit: edit, chain: chain, bent: bent))
        if !isPractice {
            PaintTips.refineEdited()
        }
    }

    func endStroke() {
        trace = nil
        snapLines = nil
        mergeAreas = []
        mergeWanted = nil
    }

    /// Whether a line's ends join the lines they land near: the Toolbox's Snap.
    var snapsOn: Bool { snaps }

    /// A drawn line as the Studio lays it: ink alone (a draw with no paints to give, which lays
    /// nudged through junctions as any line now does) unless Color from Photo is on, when the
    /// model reads the photo's colors for the pieces it cuts (`TemplateEditor.painted`).
    func inked(_ edit: TemplateEditor.Edit) -> TemplateEditor.Edit {
        RefineView.inked(edit, colorsFromPhoto: penColors && !model.isScratch)
    }

    /// A pen's line from its samples (`RefineGestures.pen`), steadied by its Smoothing.
    func penEdit(_ points: [SIMD2<Float>]) -> TemplateEditor.Edit? {
        RefineGestures.pen(points, on: screen, snapping: snapLines, smoothing: tool == .pen ? CGFloat(penSmoothing) : 0)
    }

    /// The eraser's pass as an edit, at its Size (`RefineGestures.eraser`).
    func eraserEdit(_ points: [SIMD2<Float>]) -> TemplateEditor.Edit? {
        RefineGestures.eraser(points, on: screen, size: CGFloat(eraserSize))
    }

    /// Bend Line, Move Edge and Move Number follow the drag from where it began to the finger
    /// (`trace`, the two points), the line or number shown moving, and lay it when it lifts.
    func drag(_ touch: RefineTouch, at point: SIMD2<Float>) {
        switch touch {
        case .began:
            trace = [point, point]
        case .moved:
            guard let start = trace?.first else { return }
            trace = [start, point]
        case .ended:
            guard let start = trace?.first else { return }
            trace = [start, point]
            // Bend Line's line shows where it goes until the template has it; a cell edge has no ink.
            let shown = tool == .bendLine ? bend.map { (normalized($0.original), normalized($0.moved)) } : nil
            // What the drag holds, by the edit's own rule, on the template on screen: one that holds
            // nothing says where to start, unless edits are still on their way (it may hold what
            // they move: the queue lays it on the template they make, and says if it can't).
            let holds = tool == .moveNumber ? heldNumber != nil : bend != nil
            trace = nil
            guard holds || !submitted.isEmpty else {
                if screen.onScreenLength(point - start) >= 4 {
                    model.tell(tool == .moveNumber ? .grabNumber : tool == .bendLine ? .grabLine : .grabEdge)
                }
                return
            }
            let edit = tool == .moveNumber
                ? RefineGestures.moveLabel(from: start, to: point, on: screen)
                : RefineGestures.reshape(from: start, to: point, on: screen, target: tool == .bendLine ? .ink : .edge)
            if let edit { submit(edit, bent: shown) }
        case .cancelled:
            trace = nil
        }
    }

    /// The Paint Brush's stroke as an edit, in the current paint at the brush's Size
    /// (`RefineGestures.brush`).
    func brushEdit(_ points: [SIMD2<Float>]) -> TemplateEditor.Edit? {
        guard let color = currentPaint else { return nil }
        return RefineGestures.brush(points, on: screen, color: color, size: CGFloat(brushSize))
    }

    // MARK: Shapes

    /// Shapes follows the drag: the shape spans from where it began to the finger, and is laid on
    /// the template when it lifts. A curve takes two drags: its ends, then its bend.
    func drawShape(_ touch: RefineTouch, at point: SIMD2<Float>) {
        switch touch {
        case .began:
            if curve == nil { snapLines = snapsOn ? currentSnapLines() : nil }
            trace = [point, point]
        case .moved:
            guard let start = trace?.first else { return }
            trace = [start, point]
        case .ended:
            guard let start = trace?.first else { return }
            trace = [start, point]
            let figure = shapeFigure()
            trace = nil
            if shape == .curve && curve == nil {
                // The ends are down; the next drag bends the curve between them.
                if let figure, figure.count == 2 {
                    curve = (screen.picturePoint(figure[0]), screen.picturePoint(figure[1]))
                }
            } else {
                curve = nil
                snapLines = nil
                if let figure, let edit = RefineGestures.drawEdit(figure, closed: shape.isClosed, on: screen) { submit(edit) }
            }
        case .cancelled:
            trace = nil
        }
    }

    /// The shape as it will be drawn (points on screen), from the drag under way (`trace`) and,
    /// for a curve, its ends; nil while it is too small to draw.
    func shapeFigure() -> [CGPoint]? {
        guard picture.width > 0, picture.height > 0 else { return nil }
        if let curve {
            guard let bend = trace?.last else { return [screen.onScreen(curve.from), screen.onScreen(curve.to)] }
            return RefineGestures.figure(shape, from: bend, to: bend, curve: curve, on: screen, snapping: snapLines)
        }
        guard let trace, let first = trace.first, let last = trace.last else { return nil }
        return RefineGestures.figure(shape, from: first, to: last, on: screen, snapping: snapLines)
    }

    /// A curve whose ends are down and that wasn't bent is laid straight.
    func finishCurve() {
        guard let pending = curve else { return }
        curve = nil
        snapLines = nil
        if let edit = RefineGestures.straightCurve(from: pending.from, to: pending.to, on: screen) { submit(edit) }
    }

    /// The lines on screen, in the template's canvas units: its drawing, the lines drawn since,
    /// less what was erased since (the edits sent that it doesn't show yet).
    /// The lines a stroke's ends may join: the drawing's, but its writing, which the editor never
    /// joins a line to (an end snapped onto a letter would hang there and close nothing).
    func currentSnapLines() -> SnapLines? {
        guard let drawing = base?.drawing else { return nil }
        return RefineGestures.snapLines(
            drawing: drawing.lines.filter { !$0.isWriting }.map(\.points), canvas: drawing.size,
            pending: submitted.map { ($0.edit, $0.chain) })
    }

    // MARK: Landing

    /// Brings `base` up to date with the model's template, and with it the painting beneath the
    /// drawing (every area in its paint, with no line, at up to twice the canvas's resolution),
    /// then takes the edits the template shows off the ones still drawn over it. They change
    /// together, so an edit's ink never goes before the template that has it comes, and the
    /// painting never lags the drawing.
    func land() async {
        let preview = model.preview, settled = model.settledEdits
        if let preview, !preview.isDraft {
            var image = painting
            if showsPainting, painting?.preview != preview.id {
                let template = preview.template
                let long = min(2 * max(template.width, template.height), Self.paintingPixels)
                let made = await Background.run { TemplateRasterizer.image(template, style: .paintedAreas, maxPixelSize: long) }
                guard !Task.isCancelled else { return }
                if let made { image = (preview.id, made) }
            }
            // Changes of paint cross-fade in, the Lamplit Table's gentler landing (the Child at
            // Bedtime); every other edit is there the moment it lands.
            let fades = tool.paints && !reduceMotion && painting != nil && image?.preview != painting?.preview
            let before = base?.template.palette
            let renumbered = base?.id != preview.id
            // No `withAnimation` here: the landing's other changes follow in this same turn, and
            // SwiftUI flushed an animated change pending at the next write inside that write's
            // `willSet`, where a view read the value before it and was never told of it again
            // (`create-refine-layers` kept the paint whole over no photo). The painting fades by
            // its own animation (`paintingFades`, `RefinePaintedLayers`).
            paintingFades = fades
            base = preview
            // Only a painting of this template: an older one would show lines that are gone.
            painting = image?.preview == preview.id ? image : nil
            // Another template may number its areas anew: the mark goes with the one it was on.
            if renumbered { tinyMarked = nil }
            tiny = RefineTinyAreas.find(in: preview.template)
            if tinyShown >= tiny.count { tinyShown = -1 }
            let landed = RefinePalette.landing(
                currentPaint, from: before, to: preview.template.palette, repainted: repainted,
                lastEdit: preview.refinements.edits.last)
            currentPaint = landed.current
            if !landed.waiting { repainted = nil }
            if cellEdges?.id != preview.id { cellEdges = (preview.id, RefineCellEdges.path(of: preview.template)) }
            #if DEBUG
            if isPractice, !didPickDemoPaint, ShellDemo.current?.opensGuide != nil {
                didPickDemoPaint = true
                DemoMode.markReady()
            }
            // Pick from the refined template once its edits have landed, as a painter would.
            if !isPractice, !didPickDemoPaint, preview.refinements == model.refinements, let demo = ShellDemo.current {
                let template = preview.template
                let largest = template.regions.indices.max(by: { template.regions[$0].area < template.regions[$1].area })
                let at = largest.flatMap { template.labels(ofRegion: $0).max(by: { $0.radius < $1.radius })?.position }
                if demo.picksColorPaint {
                    let counts = template.regionCountsByColor
                    currentPaint = counts.indices.max { counts[$0] < counts[$1] }.map { template.palette[$0].oklab }
                }
                if demo.selectsCell || demo.opensCard { selection = at }
                if demo.opensLayers {
                    layers = .tracing
                    showsLayers = true
                }
                if demo.opensCard, let at {
                    let point = SIMD2(at.x / Float(template.width), at.y / Float(template.height))
                    if usesRail {
                        card = RefineAreaPick(at: at, screen: onScreen(point), template: template)
                        demoCardAt = at
                    } else {
                        barCard = RefineAreaPick(at: at, screen: .zero, template: template)
                    }
                }
                didPickDemoPaint = true
            }
            #endif
        }
        submitted.removeAll { $0.id <= settled }
    }

    /// The painting's long side, in pixels, at most.
    static let paintingPixels = 3200

    /// A color picked that a paint has now (poured) is that paint from then on: a look, a repaint
    /// or a merge that later takes its paint away doesn't bring it back as new.
    func landedColors() {
        let palette = base?.template.palette ?? []
        newColors.removeAll { RefinePalette.index(of: $0, in: palette) != nil }
    }

    // MARK: Taps

    func mark(_ touch: RefineTouch, at point: SIMD2<Float>) {
        switch touch {
        case .began:
            marking = (point, point)
        case .moved:
            if let start = marking?.0 { marking = (start, point) }
        case .ended:
            if let start = marking?.0 { mark(from: start, to: point) }
            marking = nil
        case .cancelled:
            marking = nil
        }
    }

    func tap(at point: SIMD2<Float>) {
        tinyMarked = nil
        // Last, after the tap's own changes (`show`).
        defer { revealLayer() }
        switch tool {
        case .pen, .cellEdge, .merge, .looks, .bendLine, .moveEdge, .moveNumber, .tryPainting:
            break
        case .brush:
            // A dab, of the brush's own reach.
            if let edit = brushEdit([point]) { submit(edit) }
        case .shape:
            finishCurve()
        case .eraser:
            // A dab, of the eraser's own reach.
            if let edit = eraserEdit([point]) { submit(edit) }
        case .smartEraser:
            eraseLine(at: point)
        case .fill:
            fill(at: point)
        case .text:
            toggleText(at: point)
        case .select, .bucket, .eyedropper, .editPaint:
            cellTapped(at: point)
        }
    }

    /// Takes out the drawn line under a tap from junction to junction (`LineChains` finds it for
    /// the flash and the ink laid over it; the template's editor decides what goes): the lines it
    /// meets stay whole. The line glows as it goes.
    func eraseLine(at point: SIMD2<Float>) {
        guard let drawing = base?.drawing else { return }
        guard let erased = RefineGestures.lineEraser(at: point, on: screen, chains: LineChains(drawing)) else {
            // A line drawn a moment ago isn't in the drawing yet: no word while edits are on their way.
            if submitted.isEmpty { model.tell(.tapLine) }
            return
        }
        let normalized = erased.chain
        submit(erased.edit, chain: normalized)
        FeedbackEngine.shared.selectionChanged()
        guard !reduceMotion else { return }
        tapped = normalized
        flashes = true
        Task {
            try? await Task.sleep(for: .milliseconds(60))
            withAnimation(.easeOut(duration: 0.45)) { flashes = false }
        }
    }

    /// Fills the shape under a tap, or clears a fill made there (`EditFills`; the model decides, in
    /// its turn, on the template as the edits before it left it). A swatch of the photo's color
    /// shows where a fill will be, unless the tap clears one.
    func fill(at point: SIMD2<Float>) {
        guard picture.width > 0, templateSize.width > 0, let photo = model.source?.image else { return }
        let color = LineEdit.photoColor(at: point, in: photo)
        let at = canvasPoint(point)
        let clears = base.map { !EditFills.cleared(by: at, edits: $0.refinements.edits, on: $0.template).isEmpty } ?? false
        submitted.append(Submitted(id: model.fill(at: at, color: color), edit: .fill(at: at, color: color), showsSwatch: !clears))
        FeedbackEngine.shared.selectionChanged()
        if !isPractice {
            PaintTips.refineEdited()
            PaintTips.refineFilled()
        }
    }

    /// A marked line is unmarked; a found line is turned off, or on again.
    func toggleText(at point: SIMD2<Float>) {
        if let marked = model.refinements.addedText.last(where: { Self.line($0, contains: point) }) {
            model.change(.unmarkText(marked))
            if !isPractice { PaintTips.refineEdited() }
        } else if let line = model.foundText.first(where: { Self.line($0, contains: point) }) {
            model.change(.toggleFound(line))
            if !isPractice { PaintTips.refineEdited() }
        }
    }

    /// Marks the line dragged out from `a` to `b`, unless the drag was too small to hold one. One
    /// small both ways is a tap that slid (a stroke and a tap exclude each other): it toggles the
    /// line under it, as a tap does.
    func mark(from a: SIMD2<Float>, to b: SIMD2<Float>) {
        let wide = abs(a.x - b.x) * Float(picture.width), tall = abs(a.y - b.y) * Float(picture.height)
        guard wide >= 12, tall >= 6 else {
            if wide < 12, tall < 6 { toggleText(at: a) }
            return
        }
        model.change(.markText(TemplateRefinements.textLine(from: a, to: b)))
        if !isPractice { PaintTips.refineEdited() }
    }

    /// Whether a tap at `point` falls on `line`, give or take a little for the finger.
    static func line(_ line: [SIMD2<Float>], contains point: SIMD2<Float>) -> Bool {
        guard let bounds = TemplateRefinements.bounds(line) else { return false }
        return bounds.insetBy(dx: -0.01, dy: -0.01).contains(CGPoint(x: CGFloat(point.x), y: CGFloat(point.y)))
    }

    // MARK: Changes

    func undo() {
        trace = nil
        // Undo while a curve waits to be bent takes the curve back, not the change before.
        if curve != nil {
            curve = nil
            snapLines = nil
            return
        }
        model.undo()
    }

    func redo() {
        model.redo()
    }

    /// A step of held fingers' undo or redo, once the last has landed and shows (a step that makes
    /// the template again, a text correction's, shows only once it's made); false when there's
    /// none left to take.
    func repeatStep(redo: Bool) -> Bool {
        guard model.historySteps == 0, base?.id == model.preview?.id, model.preview?.refinements == model.refinements
        else { return true }
        if redo {
            guard model.canRedo else { return false }
            self.redo()
        } else {
            guard model.canUndo || curve != nil else { return false }
            undo()
        }
        return true
    }

    // MARK: Tools

    func pickShape(_ kind: RefineShape) {
        if kind != shape { finishCurve() }
        shape = kind
        pick(.shape)
    }

    func pick(_ tool: RefineTool) {
        pencilPalette = nil
        hovering = nil
        guard tool != self.tool else { return }
        tinyMarked = nil
        // A practice canvas keeps the tool its page teaches (the card's link, the Pencil's double tap).
        if let practice, tool != practice.tool { return }
        FeedbackEngine.shared.selectionChanged()
        // A stroke under way was the other tool's, and a curve waiting to be bent stays straight.
        endStroke()
        finishCurve()
        previousTool = self.tool
        self.tool = tool
        if tool != .select {
            selection = nil
            barCard = nil
        }
        group = RefineGroup.of(tool)
        // What the tool works on shows: a cell edge and the paint tools the paint, Move Number the
        // numbers.
        if base != nil { revealLayer() }
    }

    /// The layer the tool changes, shown if it was hidden, so nothing it does goes unseen. Select and
    /// the Eyedropper change nothing (the Eyedropper over the photo alone picks the photo's
    /// colors), and Move Number's numbers show while it is picked.
    func revealLayer() {
        guard tool != .select, tool != .eyedropper, let layer = tool.layer, layer != .numbers else { return }
        show(layer)
    }

    /// Fades the layer in: the last change of its turn, wherever it is called. A change written
    /// after it in the same turn has SwiftUI flush the fade inside that change's `willSet`, where
    /// a view reads the value before the change and is never told of it (`land`).
    func show(_ layer: RefineLayers.Layer) {
        guard !layers.shows(layer) else { return }
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { layers.set(layer, shown: true) }
    }

    /// How `tool` works, with the figure and the curve in hand (`RefineView.hint(for:shape:bending:)`).
    func hint(for tool: RefineTool) -> String {
        RefineView.hint(for: tool, shape: shape, bending: curve != nil)
    }

    /// A tool's symbol; Shapes' is the figure's in hand.
    func symbol(_ kind: RefineTool) -> String { RefineView.symbol(kind, shape: shape) }

    /// A tool's button: picks it; Try Painting opens the painting screen instead.
    func toolTapped(_ tool: RefineTool) {
        if tool == .tryPainting {
            tryPainting()
            return
        }
        pick(tool)
    }

    /// Another group on screen, with the tool last picked there.
    func choose(_ next: RefineGroup) {
        guard next != group else { return }
        lastTool[group] = tool
        pick(lastTool[next] ?? next.tools[0])
        group = next
    }

    /// The Pencil's double tap or squeeze, as iPadOS's Apple Pencil settings ask: a pen's eraser
    /// or an eraser's pen, the tool before, or the tools and the palette beside the Pencil
    /// (`location`, where it hovers; else the picture's middle).
    func pencil(_ action: RefinePencilAction, at location: CGPoint?) {
        guard model.hasLineArtInput else { return }
        switch action {
        case .switchEraser:
            if let partner = tool.pencilPartner { pick(partner) }
        case .switchPrevious:
            if let previousTool { pick(previousTool) }
        case .showPalette:
            // A practice canvas has its one tool.
            guard !isPractice else { return }
            FeedbackEngine.shared.selectionChanged()
            let at = location ?? CGPoint(x: picture.midX, y: picture.midY)
            pencilPalette = CGRect(x: at.x - 12, y: at.y - 12, width: 24, height: 24)
        }
    }

    /// Try Painting: the painting screen on the template on screen, once the canvas's renderer is
    /// made (`ArtworkPaintingView` waits for it too). Its fills go when it closes.
    func tryPainting() {
        guard let template = base?.template else { return }
        FeedbackEngine.shared.selectionChanged()
        Task {
            _ = await RenderContext.ready()
            // Named as the painting Start makes will be: by its id, at the version it records.
            trial = RefineTrial(session: PaintingSession(
                template: template, nicknameSeed: ColorNickname.seed(for: model.paintingID),
                nicknameVersion: ColorNickname.currentVersion))
        }
    }

    /// The picture alone on screen (a four-finger tap, ⌃⌘F), or the tools and bars back.
    func toggleFullScreen() {
        FeedbackEngine.shared.selectionChanged()
        // One change of one turn (`show`): the keys asked again in the full screen's own transaction.
        withAnimation(reduceMotion ? nil : .snappy) {
            fullScreen.toggle()
            keysRequest += 1
        }
    }

    /// The whole picture on screen (⌘0), as a quick pinch in fits it.
    func fit() {
        focus = RefineFocus(id: (focus?.id ?? 0) + 1, rect: CGRect(x: 0, y: 0, width: 1, height: 1), animated: !reduceMotion)
    }

    // MARK: Holding, hovering and dropping

    /// The Eyedropper's hold, with any tool: a loupe shows the color under the finger over the
    /// current paint while it holds and moves, and lifting makes that color the current paint.
    func held(_ touch: RefineTouch, at point: SIMD2<Float>) {
        guard base != nil, model.hasLineArtInput else {
            hold = nil
            return
        }
        switch touch {
        case .began:
            endStroke()
            FeedbackEngine.shared.selectionChanged()
            hold = RefineHold(at: point, color: sampled(at: point))
        case .moved:
            hold = RefineHold(at: point, color: sampled(at: point))
        case .ended:
            let color = sampled(at: point)
            hold = nil
            guard let color, let template = base?.template else { return }
            currentPaint = color
            FeedbackEngine.shared.selectionChanged()
            announceCurrentPaint(in: template)
        case .cancelled:
            hold = nil
        }
    }

    /// The color the Eyedropper picks at `point`: the photo's (or the paint within a just-noticeable
    /// difference of it) where the photo is what shows most, else the paint of the cell there.
    func sampled(at point: SIMD2<Float>) -> SIMD3<Float>? {
        guard let template = base?.template else { return nil }
        if layers.photoReads, let photo = model.source?.image {
            return RefinePalette.snapped(LineEdit.photoColor(at: point, in: photo), to: template.palette)
        }
        guard let region = template.region(at: canvasPoint(point)) else { return nil }
        return template.palette[Int(template.regions[region].colorIndex)].oklab
    }

    /// The Pencil's hover over the picture (nil once it leaves), kept as what it shows.
    func hovered(_ point: SIMD2<Float>?) {
        let mark = point.flatMap(hoverMark(at:))
        if mark != hovering { hovering = mark }
    }

    /// What the Pencil's hover at `point` shows for the tool in hand: the Eraser's and the Brush's
    /// reach, or the cell a tap would take.
    func hoverMark(at point: SIMD2<Float>) -> RefineHoverMark.Mark? {
        switch tool {
        case .eraser, .smartEraser: RefineHoverMark.Mark.ring(at: point, radius: eraserRadius)
        case .brush: RefineHoverMark.Mark.ring(at: point, radius: screen.brushRadius(size: CGFloat(brushSize)))
        case .bucket, .fill, .select, .eyedropper, .editPaint: base?.template.region(at: canvasPoint(point)).map(RefineHoverMark.Mark.cell)
        default: nil
        }
    }

    /// A swatch dragged over the picture: the cell it would paint is outlined, and only a cell
    /// takes it.
    func dropHovered(_ point: SIMD2<Float>?) -> Bool {
        let cell = point.flatMap { model.hasLineArtInput ? base?.template.region(at: canvasPoint($0)) : nil }
        if cell != dropCell { dropCell = cell }
        return cell != nil
    }

    /// A swatch dropped on a cell pours its paint there, as the Bucket does, and becomes the
    /// current paint (Procreate's ColorDrop); the paint shows if it was hidden.
    func dropped(_ payload: String, at point: SIMD2<Float>) {
        dropCell = nil
        guard let template = base?.template, model.hasLineArtInput, let color = RefinePaletteBar.color(of: payload, in: template),
              template.region(at: canvasPoint(point)) != nil
        else { return }
        FeedbackEngine.shared.selectionChanged()
        currentPaint = color
        let at = canvasPoint(point)
        submitted.append(Submitted(id: model.paintArea(at: at, color: color), edit: .paintArea(at: at, color: color)))
        show(.paint)
        if !isPractice { PaintTips.refineEdited() }
    }

    // MARK: Cells and paint

    /// The region Select picked, on the template on screen.
    var selectedRegion: Int? {
        guard let selection else { return nil }
        return base?.template.region(at: selection)
    }

    /// The current paint's number less one, when the painting has it.
    var currentIndex: Int? {
        RefinePalette.index(of: currentPaint, in: base?.template.palette ?? [])
    }

    /// What a swatch dropped on another does: in Edit Paint, `mergePaints`; elsewhere nothing.
    var paletteMerge: ((Int, Int) -> Void)? {
        guard tool == .editPaint else { return nil }
        return { from, into in self.mergePaints(from, into: into) }
    }

    /// Edit Paint's swatch dropped on another: paint `from` takes the color of `into`, so the two
    /// become one (`TemplateEditor.Edit.repaint`, whose paints made alike merge), which a note
    /// says; the current paint follows.
    func mergePaints(_ from: Int, into: Int) {
        guard let palette = base?.template.palette, palette.indices.contains(from), palette.indices.contains(into) else { return }
        FeedbackEngine.shared.selectionChanged()
        if currentPaint == palette[from].oklab { currentPaint = palette[into].oklab }
        model.recolor(.repaint(from: palette[from].oklab, to: palette[into].oklab, family: false))
    }

    /// Edit Paint's paint, as the colors panel picks it: the current paint.
    /// Looks and Edit Paint's change. A repaint of the current paint keeps it the current paint
    /// once it lands, in the color the repaint gives it (`repainted`), so a picker still open goes
    /// on with it; a repaint of another (a color still waiting as another paint was chosen) leaves
    /// the choice alone.
    func recolor(_ change: RefineColors) {
        if case .repaint(let from, let to, let family) = change, from == currentPaint {
            let edit = TemplateEditor.Edit.repaint(from: from, to: to, family: family)
            repainted = RefinePalette.Repainted(edit: edit, color: TemplateEditor.recolor(from, by: edit), current: currentPaint)
        }
        model.recolor(change)
    }

    /// A Merge drag begins: the template on screen gets its probe, unless it has one.
    func probeMerge() {
        mergeStroke += 1
        mergeAreas = []
        guard let base, mergeProbe?.preview != base.id else { return }
        mergeProbe = (try? TemplateEditor.MergeProbe(base.template)).map { (base.id, $0) }
    }

    /// The areas the Merge drag so far joins, found off the main actor; a drag that moves on while
    /// they are being found waits for that, and only its newest points are looked at.
    func light(_ points: [SIMD2<Float>]) {
        mergeWanted = points
        guard !mergeProbing else { return }
        lightNext()
    }

    func lightNext() {
        guard let points = mergeWanted, let probe = mergeProbe,
              case .merge(let path)? = RefineGestures.merge(points, on: screen)
        else { return }
        mergeWanted = nil
        mergeProbing = true
        let stroke = mergeStroke
        Task {
            let areas = await Self.areas(of: probe.probe, along: path)
            mergeProbing = false
            // The finger may have lifted, another drag begun or the template changed meanwhile.
            if trace != nil, stroke == mergeStroke, probe.preview == mergeProbe?.preview { mergeAreas = areas }
            if mergeWanted != nil { lightNext() }
        }
    }

    @concurrent
    static func areas(of probe: TemplateEditor.MergeProbe, along path: [SIMD2<Float>]) async -> [Int] {
        probe.areas(along: path)
    }

    /// A tap of Select, the Bucket, the Eyedropper or Edit Paint on the cell under it.
    func cellTapped(at point: SIMD2<Float>) {
        guard let template = base?.template, model.hasLineArtInput else { return }
        let at = canvasPoint(point)
        let region = template.region(at: at)
        switch tool {
        case .select:
            FeedbackEngine.shared.selectionChanged()
            selection = region != nil && region != selectedRegion ? at : nil
            barCard = nil
        case .bucket:
            guard region != nil, let color = currentPaint else { return }
            FeedbackEngine.shared.selectionChanged()
            submitted.append(Submitted(id: model.paintArea(at: at, color: color), edit: .paintArea(at: at, color: color)))
            if !isPractice { PaintTips.refineEdited() }
        case .eyedropper:
            guard let color = sampled(at: point) else { return }
            currentPaint = color
            FeedbackEngine.shared.selectionChanged()
            announceCurrentPaint(in: template)
        case .editPaint:
            guard let region else { return }
            FeedbackEngine.shared.selectionChanged()
            currentPaint = template.palette[Int(template.regions[region].colorIndex)].oklab
            announceCurrentPaint(in: template)
        default:
            break
        }
    }

    /// VoiceOver hears the paint a tap picked: its number and how many areas use it, or that it is
    /// a new one.
    func announceCurrentPaint(in template: Template) {
        let announcement: String
        if let paint = RefinePalette.index(of: currentPaint, in: template.palette) {
            let number = (paint + 1).formatted()
            let areas = TemplateCounts.areas(RefinePaintGlow.areas(of: paint, in: template).count)
            announcement = String(
                localized: "refine.colors.areas", defaultValue: "Paint \(number): \(areas)",
                comment: "VoiceOver announcement when picking a paint in Refine: the formatted paint number, then how many areas use it (\"3 areas\")")
        } else {
            announcement = String(localized: "New Paint")
        }
        AccessibilityNotification.Announcement(announcement).post()
    }

    /// A line or a cell edge closed off an area of its own: a soft tap, VoiceOver hears of it, and
    /// the sparkles pop where its ends met (none under Reduce Motion).
    func closed(_ shape: CreateModel.ClosedShape) {
        FeedbackEngine.shared.areaMade()
        AccessibilityNotification.Announcement(String(
            localized: "refine.areaMade", defaultValue: "New area",
            comment: "VoiceOver announcement on the Refine screen when a line the painter drew closed off an area of its own")).post()
        let size = templateSize
        guard !reduceMotion, size.width > 0, size.height > 0 else { return }
        let point = onScreen(SIMD2(shape.at.x / Float(size.width), shape.at.y / Float(size.height)))
        sparkles = (shape.serial, point, CGFloat(shape.extent) * picture.width / size.width)
    }
}
