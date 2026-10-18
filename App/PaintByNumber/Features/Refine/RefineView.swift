import PaintCore
import SwiftUI

/// What one finger (or the Pencil) does on the Refine screen.
nonisolated enum RefineTool: Hashable {
    /// Draws lines as they are drawn.
    case pen
    /// Draws the shape picked (`RefineShape`) across a drag.
    case shape
    /// Rubs out what it touches; a tap takes out a dab.
    case eraser
    /// Rubs lines out, or takes out the one tapped, junction to junction (`LineChains`).
    case smartEraser
    /// A tap makes the closed shape under it an area of its own in the photo's color there, or
    /// clears that again (`EditFills`).
    case fill
    /// Settings › Detail Brushes: areas brushed for more or less detail, that brushing cleared,
    /// and the text the app found corrected.
    case more, less, unbrush, text

    /// The tool the Pencil's double tap switches to: a drawing tool's eraser, an eraser's pen.
    var pencilPartner: RefineTool? {
        switch self {
        case .pen, .shape: .eraser
        case .eraser, .smartEraser: .pen
        case .fill, .more, .less, .unbrush, .text: nil
        }
    }

    var erases: Bool { self == .eraser || self == .smartEraser }
}

/// What shows beneath the drawing on the Refine screen.
nonisolated enum RefineBackdrop: Hashable {
    /// The drawing's paper.
    case paper
    /// The photo.
    case photo
    /// The template painted, every area in its paint: the picture once it's finished.
    case painting
}

/// The create flow's optional Refine step (`TemplateRefinements`): the drawing large, on its
/// paper, over the photo or over the painting finished (every area in its paint), where one
/// finger draws lines and takes them out, and two fingers zoom and move; a tap of two fingers
/// undoes. What the painter does is made by hand to the template (PaintCore's `TemplateEditor`,
/// `CreateModel.edit(_:)`): no image processing, no new template. A line is the line drawn, as the
/// outline of the areas it closes too, and nothing the painter didn't touch changes:
/// - the Pen draws a line as drawn (smoothed as it showed); only an end whose ink touches a
///   line's moves onto it, by no more than the ink's width, so the cell closes as it looks;
/// - Shapes draws a straight line, a rectangle, an oval or a curve across a drag
///   (`RefineShape`, `ShapePath`), shown as it will be while the finger is down; a line's or a
///   curve's ends move onto a line their ink touches, as the Pen's do;
/// - the Eraser rubs out what it touches (ink within its reach is cut at the edge of it), and a
///   tap takes out a dab;
/// - the Smart Eraser rubs too, and a tap takes the line out from junction to junction;
/// - Fill: a tap inside a closed shape makes it an area of its own, painted the photo's color
///   where it was tapped (`LineEdit.photoColor`), kept however small, its number allowed down to
///   about half the usual size and read zoomed in (a detail area, `Template.detailRegions`); a
///   tap in a filled area clears it (`EditFills`). A shape left open fills the area around it,
///   which shows at once, and Undo takes it back. Refine zooms in far
///   (`RefineSurfaceView.maximumZoom`), so a Pencil outlines a star of a few pixels comfortably.
/// An edit the template can't take (a line that doubles back on itself) changes nothing and says
/// so, in a toast VoiceOver announces; so does a shape a line closed that has no room for a
/// number (the line stays).
/// Once an Apple Pencil touches the canvas (or with Only Draw with Apple Pencil on), the Pencil
/// draws and taps and one finger moves the picture, so a palm leaves no mark; its double tap
/// switches between drawing and the Eraser. Photo and Painting show the photo, or the template
/// painted (every area in its paint, `TemplateRasterizer.Style.paintedAreas`), beneath the
/// drawing: the painting the changes make, once the template has them. With Settings › Detail
/// Brushes one finger also
/// brushes areas for more or less detail, clears that brushing, and corrects the text the app
/// found (a tap turns a found line off or on again, a drag across a line marks it).
///
/// An edit lands in a few hundredths of a second, off the main actor, and the screen then shows
/// the new template with no crossfade; until it does, the edit shows over the last template in the
/// drawing's own ink (`RefineInkLayer`), so a line is there the moment it is drawn and gone the
/// moment it is erased, and a fill shows as a swatch of its color where it was tapped
/// (`RefineFillLayer`, which then tints the areas fills made in their paint, under the drawing).
/// The brushes and the text corrections still make the template again, as the sliders do, and the
/// edits are laid on the new one. Undo and Redo (⌘Z, ⇧⌘Z) step through the changes
/// (`CreateModel.history`; an edit taken back or put back comes at once from the templates kept),
/// Cancel puts back what the screen opened with, Done keeps them.
struct RefineView: View {
    let model: CreateModel

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(SettingsKey.lineWeight) private var lineWeight = LineWeight.default
    /// Settings › Detail Brushes, as the screen opened (Settings isn't reachable from it).
    private let detailBrushes = Preferences().detailBrushes
    @State private var tool: RefineTool
    @State private var shape = RefineShape.line
    @State private var backdrop = RefineBackdrop.paper
    /// The template on screen painted, for `RefineBackdrop.painting`, with its preview's id.
    @State private var painting: (preview: UUID, image: CGImage)?
    /// The template the screen draws over: the newest at full resolution.
    @State private var base: CreateModel.Preview?
    /// The edits sent that `base` doesn't show yet, which the screen draws over it.
    @State private var submitted: [Submitted] = []
    /// The pen's line or the eraser's pass under the finger, until it lifts; for Shapes, where
    /// the drag began and where the finger is.
    @State private var trace: [SIMD2<Float>]?
    /// The lines a pen's ends may join, as its stroke began.
    @State private var snapLines: SnapLines?
    /// A curve's ends, drawn and waiting for the drag that bends it.
    @State private var curve: (from: SIMD2<Float>, to: SIMD2<Float>)?
    /// The brush stroke under the finger (detail brushes).
    @State private var stroke: TemplateRefinements.Stroke?
    /// The line of text being dragged out: where the drag began and where it is.
    @State private var marking: (SIMD2<Float>, SIMD2<Float>)?
    /// The line the eraser was last tapped on, which flashes as it goes.
    @State private var tapped: [SIMD2<Float>]?
    @State private var flashes = false
    /// Where the picture is in the canvas, and its zoom (the touch surface's).
    @State private var picture: CGRect = .zero
    @State private var zoom: CGFloat = 1
    @State private var canvasSize: CGSize = .zero

    init(model: CreateModel) {
        self.model = model
        // Never a draft: its canvas is smaller than the one the edits will be laid on.
        _base = State(initialValue: model.preview.flatMap { $0.isDraft ? nil : $0 })
        // Without a drawing to draw on (its line art failed), only the brushes are left.
        _tool = State(initialValue: model.hasLineArtInput ? .pen : .more)
    }

    var body: some View {
        NavigationStack {
            canvas
                .safeAreaInset(edge: .bottom, spacing: 0) { tools }
                .background(Theme.paper)
                .navigationTitle("Refine")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbar }
        }
        .onAppear {
            model.beginRefining()
            PaintTips.desk.enter(.refine)
        }
        .onDisappear {
            model.dismissNote()
            PaintTips.desk.leave(.refine)
        }
        .task(id: Landing(preview: model.preview?.id, settled: model.settledEdits, showsPainting: backdrop == .painting)) {
            await land()
        }
    }

    /// An edit sent to the model, which draws it until the template on screen has it.
    private struct Submitted: Identifiable {
        /// Its number (`CreateModel.edit(_:)`).
        let id: Int
        let edit: TemplateEditor.Edit
        /// A line tapped away, as the tap found it, normalized.
        var chain: [SIMD2<Float>]?
        /// A swatch of the photo's color shows where a fill was tapped, until the template has it.
        var showsSwatch = false
    }

    /// What the screen draws over: when any of it changes, `land` brings `base` up to date.
    private struct Landing: Hashable {
        var preview: UUID?
        var settled: Int
        var showsPainting: Bool
    }

    // MARK: Canvas

    private var canvas: some View {
        ZStack {
            if let photo = model.source?.preview {
                // A card, as the preview's comparison is; zoomed in, its corners leave the screen.
                Self.card
                    .fill(Theme.surface)
                    .shadow(color: .black.opacity(0.12), radius: 20, x: 0, y: 10)
                    .frame(width: picture.width, height: picture.height)
                    .position(x: picture.midX, y: picture.midY)
                let showsPhoto = backdrop == .photo || base == nil
                let painted = backdrop == .painting && base != nil && painting?.preview == base?.id ? painting?.image : nil
                ZStack {
                    if showsPhoto {
                        Image(decorative: photo, scale: 1)
                            .resizable()
                            .interpolation(.high)
                            .frame(width: picture.width, height: picture.height)
                            .position(x: picture.midX, y: picture.midY)
                    } else if let painted {
                        Image(decorative: painted, scale: 1)
                            .resizable()
                            .interpolation(.high)
                            .frame(width: picture.width, height: picture.height)
                            .position(x: picture.midX, y: picture.midY)
                    }
                    if let base {
                        LineArtLayer(
                            drawing: base.drawing, picture: picture, scale: zoom, overPhoto: showsPhoto,
                            overPaint: painted != nil)
                            .equatable()
                    }
                    RefineFillLayer(
                        base: base, fills: filledPoints, swatches: swatches, space: model.source?.image.colorSpace, rect: picture,
                        showsAreas: painted == nil)
                        .equatable()
                    let figure = shapeTrace
                    RefineInkLayer(
                        lines: pending, trace: tool == .shape ? figure : trace, traceIsDrawn: tool == .shape, erasing: tool.erases,
                        eraserRadius: eraserRadius, rect: picture, lineWidth: lineWidth,
                        beneath: showsPhoto ? photo : painted, halo: showsPhoto)
                    if let tapped {
                        RefineTappedLine(points: tapped, rect: picture, lineWidth: lineWidth)
                            .opacity(flashes ? 1 : 0)
                    }
                    if showsDetailMarks {
                        RefineMarks(
                            refinements: shown, found: model.foundText, marking: marking, rect: picture,
                            emphasizesText: tool == .text)
                    }
                }
                // Drawing past the picture's edge stays on the picture.
                .mask {
                    Self.card
                        .frame(width: picture.width, height: picture.height)
                        .position(x: picture.midX, y: picture.midY)
                }
            }
            RefineTouchSurface(
                aspectRatio: aspectRatio,
                onLayout: { rect, zoom in
                    picture = rect
                    self.zoom = zoom
                },
                onDraw: draw, onTap: tap, onUndo: undo, onPencilTap: pencilTap)
        }
        .clipped()
        .overlay(alignment: .bottom) { status.padding(12) }
        .overlay(alignment: .top) { RefineNoteToast(note: model.note).padding(.top, 12) }
        .animation(.easeInOut(duration: 0.2), value: model.phase)
        .animation(reduceMotion ? nil : .snappy, value: model.note)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { canvasSize = $0 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(String(
            localized: "refine.canvas", defaultValue: "Painting to refine",
            comment: "VoiceOver label of the Refine screen's picture, where lines are drawn and erased; its value counts the changes")))
        .accessibilityValue(Self.changes(model.refinements.changeCount))
        .accessibilityIdentifier("refine-canvas")
    }

    private static let card = RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)

    /// The template's canvas, in canvas units (zero before there is a template).
    private var templateSize: CGSize { base?.drawing.size ?? .zero }

    /// A picture point (0…1) in the template's canvas units.
    private func canvasPoint(_ p: SIMD2<Float>) -> SIMD2<Float> {
        let size = templateSize
        return SIMD2(p.x * Float(size.width), p.y * Float(size.height))
    }

    /// The edits sent that the template on screen doesn't show yet, as the lines the ink layer
    /// draws (normalized to the picture). Fills change no line (`RefineFillLayer` shows them).
    private var pending: [TemplateRefinements.Line] {
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
            case .fill:
                break
            }
        }
        return lines
    }

    /// Where the fills the template on screen has were tapped (normalized to the picture): its
    /// edits', and the lines builds before them filled through the generator.
    private var filledPoints: [SIMD2<Float>] {
        guard let base else { return [] }
        let size = SIMD2(Float(base.template.width), Float(base.template.height))
        var points = base.refinements.lines.filter { $0.kind == .fill }.compactMap(\.points.first)
        for case .fill(let at, _) in base.refinements.edits { points.append(at / size) }
        return points
    }

    /// The fills sent that the template on screen doesn't show yet, normalized to the picture.
    private var swatches: [RefineFillLayer.Swatch] {
        let size = SIMD2(Float(templateSize.width), Float(templateSize.height))
        guard size.x > 0, size.y > 0 else { return [] }
        return submitted.compactMap { item in
            guard item.showsSwatch, case .fill(let at, let color) = item.edit else { return nil }
            return RefineFillLayer.Swatch(point: at / size, color: color)
        }
    }

    /// The detail brushing and text corrections show while their tools are offered, or once
    /// there are any.
    private var showsDetailMarks: Bool {
        detailBrushes || !model.refinements.strokes.isEmpty || !model.refinements.hiddenText.isEmpty
            || !model.refinements.addedText.isEmpty
    }

    /// The refinements with the brush stroke still under the finger.
    private var shown: TemplateRefinements {
        guard let stroke else { return model.refinements }
        var shown = model.refinements
        shown.strokes.append(stroke)
        return shown
    }

    private var aspectRatio: CGFloat {
        guard let image = model.source?.image, image.width > 0, image.height > 0 else { return 1 }
        return CGFloat(image.width) / CGFloat(image.height)
    }

    /// The picture's long side on screen, in points.
    private var pictureLong: CGFloat { max(picture.width, picture.height) }

    /// The drawing's line on screen, as the preview and the canvas draw it at this size.
    private var lineWidth: CGFloat {
        (base?.drawing ?? model.preview?.drawing)?.lineWidth(scale: zoom, weight: lineWeight) ?? 1.5
    }

    /// The detail brush keeps its size on screen, so zoomed in it brushes finer: a twenty-fifth of
    /// the canvas's short side, between 14 and 30 points.
    private var brushRadius: Float {
        let points = min(max(0.04 * min(canvasSize.width, canvasSize.height), 14), 30)
        return pictureLong > 0 ? Float(points / pictureLong) : 0.03
    }

    /// The eraser too, a little finer (`RefineScreen.eraserRadius`).
    private var eraserRadius: Float { screen.eraserRadius }

    /// The screen as the gestures see it (`RefineGestures`, which `pbn refine` replays too).
    private var screen: RefineScreen {
        RefineScreen(canvas: templateSize, picture: picture.size, view: canvasSize, lineWidth: lineWidth)
    }

    @ViewBuilder
    private var status: some View {
        if model.phase == .generating {
            HStack(spacing: 10) {
                ProgressView(value: model.progress)
                    .frame(width: 64)
                Text("Updating…")
            }
            .font(.footnote.weight(.medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .glassEffect(.regular, in: .capsule)
            .transition(.opacity)
        }
    }

    // MARK: Touches

    private func draw(_ touch: RefineTouch, at point: SIMD2<Float>) {
        switch tool {
        case .pen, .eraser, .smartEraser: follow(touch, at: point)
        case .shape: drawShape(touch, at: point)
        case .text: mark(touch, at: point)
        case .more, .less, .unbrush: brush(touch, at: point)
        // A fill is a tap: a drag does nothing.
        case .fill: break
        }
    }

    /// The pen's line or the eraser's pass follows the finger; when it lifts, it is laid on the
    /// template, the pen's as it showed.
    private func follow(_ touch: RefineTouch, at point: SIMD2<Float>) {
        switch touch {
        case .began:
            trace = [point]
            snapLines = tool.erases ? nil : currentSnapLines()
        case .moved:
            // Samples closer than a point add nothing the line shows.
            guard var current = trace, let last = current.last, screen.onScreenLength(point - last) >= 1 else { return }
            current.append(point)
            trace = current
        case .ended:
            guard var current = trace else { return }
            current.append(point)
            let edit = tool.erases ? eraserEdit(current) : penEdit(current)
            endStroke()
            if let edit { submit(edit) }
        case .cancelled:
            endStroke()
        }
    }

    /// Sends an edit to the template (`CreateModel.edit(_:)`), which draws it in a moment; until
    /// then it shows over the template (`pending`).
    private func submit(_ edit: TemplateEditor.Edit, chain: [SIMD2<Float>]? = nil) {
        submitted.append(Submitted(id: model.edit(edit), edit: edit, chain: chain))
        if case .draw = edit { PaintTips.refineLineDrawn() }
    }

    private func endStroke() {
        trace = nil
        snapLines = nil
    }

    /// A pen's line from its samples (`RefineGestures.pen`).
    private func penEdit(_ points: [SIMD2<Float>]) -> TemplateEditor.Edit? {
        RefineGestures.pen(points, on: screen, snapping: snapLines)
    }

    /// The eraser's pass as an edit (`RefineGestures.eraser`).
    private func eraserEdit(_ points: [SIMD2<Float>]) -> TemplateEditor.Edit? {
        RefineGestures.eraser(points, on: screen)
    }

    // MARK: Shapes

    /// Shapes follows the drag: the shape spans from where it began to the finger, and is laid on
    /// the template when it lifts. A curve takes two drags: its ends, then its bend.
    private func drawShape(_ touch: RefineTouch, at point: SIMD2<Float>) {
        switch touch {
        case .began:
            if curve == nil { snapLines = currentSnapLines() }
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
    private func shapeFigure() -> [CGPoint]? {
        guard picture.width > 0, picture.height > 0 else { return nil }
        if let curve {
            guard let bend = trace?.last else { return [screen.onScreen(curve.from), screen.onScreen(curve.to)] }
            return RefineGestures.figure(shape, from: bend, to: bend, curve: curve, on: screen, snapping: snapLines)
        }
        guard let trace, let first = trace.first, let last = trace.last else { return nil }
        return RefineGestures.figure(shape, from: first, to: last, on: screen, snapping: snapLines)
    }

    /// The shape under the finger, or a curve waiting to be bent, as `RefineInkLayer` draws it.
    private var shapeTrace: [SIMD2<Float>]? {
        guard tool == .shape, trace != nil || curve != nil else { return nil }
        return shapeFigure()?.map(screen.picturePoint)
    }

    /// A curve whose ends are down and that wasn't bent is laid straight.
    private func finishCurve() {
        guard let pending = curve else { return }
        curve = nil
        snapLines = nil
        if let edit = RefineGestures.straightCurve(from: pending.from, to: pending.to, on: screen) { submit(edit) }
    }

    /// The lines on screen, in the template's canvas units: its drawing, the lines drawn since,
    /// less what was erased since (the edits sent that it doesn't show yet).
    private func currentSnapLines() -> SnapLines? {
        guard let drawing = base?.drawing else { return nil }
        return RefineGestures.snapLines(
            drawing: drawing.lines.map(\.points), canvas: drawing.size, pending: submitted.map { ($0.edit, $0.chain) })
    }

    // MARK: Landing

    /// Brings `base` up to date with the model's template, and with it the painting beneath the
    /// drawing (every area in its paint, with no line, at up to twice the canvas's resolution),
    /// then takes the edits the template shows off the ones still drawn over it. They change
    /// together, so an edit's ink never goes before the template that has it comes, and the
    /// painting never lags the drawing.
    private func land() async {
        let preview = model.preview, settled = model.settledEdits
        if let preview, !preview.isDraft {
            var image = painting
            if backdrop == .painting, painting?.preview != preview.id {
                let template = preview.template
                let long = min(2 * max(template.width, template.height), Self.paintingPixels)
                let made = await Background.run { TemplateRasterizer.image(template, style: .paintedAreas, maxPixelSize: long) }
                guard !Task.isCancelled else { return }
                if let made { image = (preview.id, made) }
            }
            base = preview
            // Only a painting of this template: an older one would show lines that are gone.
            painting = image?.preview == preview.id ? image : nil
        }
        submitted.removeAll { $0.id <= settled }
    }

    /// The painting's long side, in pixels, at most.
    static let paintingPixels = 3200

    private var brushKind: TemplateRefinements.Stroke.Kind {
        switch tool {
        case .less: .less
        case .unbrush: .erase
        default: .more
        }
    }

    private func brush(_ touch: RefineTouch, at point: SIMD2<Float>) {
        switch touch {
        case .began:
            stroke = TemplateRefinements.Stroke(kind: brushKind, radius: brushRadius, points: [point])
        case .moved:
            // Points closer than a fifth of the brush add nothing a round brush shows.
            guard var current = stroke, let last = current.points.last else { return }
            let step = point - last
            guard (step * step).sum().squareRoot() >= 0.2 * current.radius else { return }
            current.points.append(point)
            stroke = current
        case .ended:
            guard var current = stroke else { return }
            current.points.append(point)
            stroke = nil
            model.change(.stroke(current))
        case .cancelled:
            stroke = nil
        }
    }

    private func mark(_ touch: RefineTouch, at point: SIMD2<Float>) {
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

    private func tap(at point: SIMD2<Float>) {
        switch tool {
        case .pen:
            break
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
        case .more, .less, .unbrush:
            // A dab.
            model.change(.stroke(TemplateRefinements.Stroke(kind: brushKind, radius: brushRadius, points: [point])))
        }
    }

    /// Takes out the drawn line under a tap from junction to junction (`LineChains` finds it for
    /// the flash and the ink laid over it; the template's editor decides what goes): the lines it
    /// meets stay whole. The line glows as it goes.
    private func eraseLine(at point: SIMD2<Float>) {
        guard let drawing = base?.drawing,
              let erased = RefineGestures.lineEraser(at: point, on: screen, chains: LineChains(drawing))
        else { return }
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
    private func fill(at point: SIMD2<Float>) {
        guard picture.width > 0, templateSize.width > 0, let photo = model.source?.image else { return }
        let color = LineEdit.photoColor(at: point, in: photo)
        let at = canvasPoint(point)
        let clears = base.map { !EditFills.cleared(by: at, edits: $0.refinements.edits, on: $0.template).isEmpty } ?? false
        submitted.append(Submitted(id: model.fill(at: at, color: color), edit: .fill(at: at, color: color), showsSwatch: !clears))
        FeedbackEngine.shared.selectionChanged()
        PaintTips.refineFilled()
    }

    /// A marked line is unmarked; a found line is turned off, or on again.
    private func toggleText(at point: SIMD2<Float>) {
        if let marked = model.refinements.addedText.last(where: { Self.line($0, contains: point) }) {
            model.change(.unmarkText(marked))
        } else if let line = model.foundText.first(where: { Self.line($0, contains: point) }) {
            model.change(.toggleFound(line))
        }
    }

    /// Marks the line dragged out from `a` to `b`, unless the drag was too small to hold one.
    private func mark(from a: SIMD2<Float>, to b: SIMD2<Float>) {
        guard abs(a.x - b.x) * Float(picture.width) >= 12, abs(a.y - b.y) * Float(picture.height) >= 6 else { return }
        model.change(.markText(TemplateRefinements.textLine(from: a, to: b)))
    }

    /// Whether a tap at `point` falls on `line`, give or take a little for the finger.
    private static func line(_ line: [SIMD2<Float>], contains point: SIMD2<Float>) -> Bool {
        guard let bounds = TemplateRefinements.bounds(line) else { return false }
        return bounds.insetBy(dx: -0.01, dy: -0.01).contains(CGPoint(x: CGFloat(point.x), y: CGFloat(point.y)))
    }

    // MARK: Changes

    private func undo() {
        trace = nil
        // Undo while a curve waits to be bent takes the curve back, not the change before.
        if curve != nil {
            curve = nil
            snapLines = nil
            return
        }
        model.undo()
    }

    private func cancel() {
        model.cancelRefining()
        dismiss()
    }

    /// Keeps the changes, a curve waiting to be bent among them (as switching tools keeps it).
    private func done() {
        finishCurve()
        dismiss()
    }

    /// The number of changes, for VoiceOver.
    static func changes(_ count: Int) -> String {
        guard count > 0 else {
            return String(
                localized: "refine.changes.none", defaultValue: "No changes",
                comment: "VoiceOver value of the Refine button and the Refine screen's picture before anything was refined")
        }
        return String(
            localized: "refine.changes", defaultValue: "\(count) changes",
            comment: "VoiceOver value of the Refine button and the Refine screen's picture: how many lines were drawn or erased, areas brushed and text lines changed")
    }

    // MARK: Bars

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel", systemImage: "xmark", action: cancel)
                .accessibilityIdentifier("refine-cancel")
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Button("Undo", systemImage: "arrow.uturn.backward", action: undo)
                .disabled(!model.canUndo)
                .keyboardShortcut("z")
                .accessibilityIdentifier("refine-undo")
            Button("Redo", systemImage: "arrow.uturn.forward", action: model.redo)
                .disabled(!model.canRedo)
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .accessibilityIdentifier("refine-redo")
        }
        ToolbarItem(placement: .confirmationAction) {
            Button("Done", systemImage: "checkmark", action: done)
                .tint(Theme.signature)
                .accessibilityIdentifier("refine-done")
        }
    }

    /// What the finger does, with a line on how to use it, along the bottom: the pens, the
    /// erasers and the photo beneath, and the detail brushes in a row of their own where there
    /// isn't room for one.
    private var tools: some View {
        VStack(spacing: 12) {
            Text(hint)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 480)
                .accessibilityIdentifier("refine-hint")
            if detailBrushes {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) {
                        lineTools
                        detailTools
                    }
                    VStack(spacing: 10) {
                        detailTools
                        lineTools
                    }
                }
            } else {
                lineTools
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .background(Theme.paper)
        // Like the painting's bars: larger text sizes reach the buttons through the Large
        // Content Viewer.
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
    }

    /// The pens, erasers and Fill, then the photo: one row where it fits, else the pens and
    /// erasers above Fill and the photo (a phone's width holds about five of these buttons).
    private var lineTools: some View {
        ViewThatFits(in: .horizontal) {
            GlassEffectContainer(spacing: 10) {
                HStack(spacing: 8) {
                    drawingTools
                    fillAndPhoto
                }
            }
            GlassEffectContainer(spacing: 10) {
                VStack(spacing: 10) {
                    HStack(spacing: 8) { drawingTools }
                    HStack(spacing: 8) { fillAndPhoto }
                }
            }
        }
    }

    @ViewBuilder
    private var drawingTools: some View {
        toolButton(.pen, systemImage: "pencil.tip", label: Text("Pen"), id: "pen")
            .disabled(!model.hasLineArtInput)
        shapesButton
            .disabled(!model.hasLineArtInput)
        toolButton(.eraser, systemImage: "eraser", label: Text("Eraser"), id: "eraser")
            .disabled(!model.hasLineArtInput)
        toolButton(.smartEraser, systemImage: "wand.and.stars", label: Text("Smart Eraser"), id: "smart-eraser")
            .disabled(!model.hasLineArtInput)
    }

    @ViewBuilder
    private var fillAndPhoto: some View {
        toolButton(.fill, systemImage: "drop.fill", label: Text("Fill"), id: "fill")
            .disabled(!model.hasLineArtInput)
            // Make a Shape Its Own: over the tools, which sit at the bottom.
            .gentleTip(.refineFill, arrowEdge: .bottom)
        Capsule()
            .fill(Color.primary.opacity(0.15))
            .frame(width: 1, height: 24)
            .padding(.horizontal, 4)
            .accessibilityHidden(true)
        backdropButton(.photo, systemImage: "photo", label: Text("Photo"), id: "refine-photo")
        backdropButton(.painting, systemImage: "paintpalette", label: Text("Painting"), id: "refine-painting")
            .disabled(base == nil)
    }

    private var detailTools: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 8) {
                toolButton(.more, systemImage: "plus", label: Text("More Detail"), id: "more")
                toolButton(.less, systemImage: "minus", label: Text("Less Detail"), id: "less")
                if model.hasLineArtInput {
                    toolButton(.text, systemImage: "text.viewfinder", label: Text("Text"), id: "text")
                }
                toolButton(.unbrush, systemImage: "eraser.line.dashed", label: Text("Clear Brushing"), id: "unbrush")
            }
        }
    }

    private var hint: String {
        switch tool {
        case .pen:
            String(localized: "refine.hint.pen",
                   defaultValue: "Draw lines exactly as you draw them. Two fingers zoom and move, and a two‑finger tap undoes.",
                   comment: "Refine screen: how the Pen works (it draws lines into the painting's drawing just where they are drawn), shown while it is picked")
        case .shape:
            switch shape {
            case .line:
                String(localized: "refine.hint.line",
                       defaultValue: "Drag to draw a straight line. Two fingers zoom and move.",
                       comment: "Refine screen: how the Shapes tool's Line works (a drag draws a straight line from where it starts to where it ends), shown while it is picked")
            case .rectangle:
                String(localized: "refine.hint.rectangle",
                       defaultValue: "Drag from corner to corner to draw a rectangle. Two fingers zoom and move.",
                       comment: "Refine screen: how the Shapes tool's Rectangle works (a drag spans the rectangle from one corner to the opposite one), shown while it is picked")
            case .oval:
                String(localized: "refine.hint.oval",
                       defaultValue: "Drag across to draw an oval. Two fingers zoom and move.",
                       comment: "Refine screen: how the Shapes tool's Oval works (a drag spans the box the oval fills), shown while it is picked")
            case .curve:
                curve == nil
                    ? String(localized: "refine.hint.curve",
                             defaultValue: "Drag from one end of the curve to the other, then drag to bend it. Two fingers zoom and move.",
                             comment: "Refine screen: how the Shapes tool's Curve works (a first drag places the curve's ends, a second bends it through the finger), shown while it is picked")
                    : String(localized: "refine.hint.curve.bend",
                             defaultValue: "Drag to bend the curve, or tap to keep it straight.",
                             comment: "Refine screen: the Shapes tool's Curve once its ends are placed: a drag bends it through the finger, a tap keeps it a straight line")
            }
        case .eraser:
            String(localized: "refine.hint.eraser",
                   defaultValue: "Rub out just what you touch, or tap to erase a spot. Two fingers zoom and move.",
                   comment: "Refine screen: how the Eraser works (it takes out exactly the parts of lines it touches), shown while it is picked")
        case .smartEraser:
            String(localized: "refine.hint.smartEraser",
                   defaultValue: "Rub lines out, or tap a line to erase all of it. Two fingers zoom and move.",
                   comment: "Refine screen: how the Smart Eraser works (it takes lines out of the painting's drawing; a tap takes a whole line), shown while it is picked")
        case .fill:
            String(localized: "refine.hint.fill",
                   defaultValue: "Tap inside a closed shape to make it an area of its own, in the photo’s color there. Tap it again to clear it. Two fingers zoom and move.",
                   comment: "Refine screen: how the Fill tool works (a tap makes the closed shape of the drawing under it an area of its own, painted the photo's color where it was tapped; a tap in a filled area clears it), shown while it is picked")
        case .more:
            String(localized: "refine.hint.more",
                   defaultValue: "Brush where the painting should have more detail and lines. Two fingers zoom and move.",
                   comment: "Refine screen: how the More Detail brush works, shown while it is picked")
        case .less:
            String(localized: "refine.hint.less",
                   defaultValue: "Brush where the painting should be simpler, with fewer lines. Two fingers zoom and move.",
                   comment: "Refine screen: how the Less Detail brush works, shown while it is picked")
        case .text:
            String(localized: "refine.hint.text",
                   defaultValue: "Tap a line of text to keep or ignore it, or drag across a line the app missed.",
                   comment: "Refine screen: how the Text tool works (lines of text in the photo are drawn as writing), shown while it is picked")
        case .unbrush:
            String(localized: "refine.hint.unbrush", defaultValue: "Brush over marked areas to clear them.",
                   comment: "Refine screen: how Clear Brushing works (it clears areas brushed for more or less detail), shown while it is picked")
        }
    }

    /// A tool, prominent while it's the finger's.
    @ViewBuilder
    private func toolButton(_ tool: RefineTool, systemImage: String, label: Text, id: String) -> some View {
        let selected = self.tool == tool
        let button = Button { pick(tool) } label: {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(selected ? Color.white : Color.primary)
                .frame(width: 30, height: 30)
        }
        .buttonBorderShape(.circle)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("refine-tool-\(id)")
        .accessibilityShowsLargeContentViewer { Label { label } icon: { Image(systemName: systemImage) } }
        if selected {
            button.buttonStyle(.glassProminent).tint(Theme.signature)
        } else {
            button.buttonStyle(.glass)
        }
    }

    /// Shows the photo or the painting beneath the drawing while it is on (one at a time).
    @ViewBuilder
    private func backdropButton(_ kind: RefineBackdrop, systemImage: String, label: Text, id: String) -> some View {
        let selected = backdrop == kind
        let button = Button { backdrop = selected ? .paper : kind } label: {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(selected ? Color.white : Color.primary)
                .frame(width: 30, height: 30)
        }
        .buttonBorderShape(.circle)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier(id)
        .accessibilityShowsLargeContentViewer { Label { label } icon: { Image(systemName: systemImage) } }
        if selected {
            button.buttonStyle(.glassProminent).tint(Theme.signature)
        } else {
            button.buttonStyle(.glass)
        }
    }

    /// Shapes: a menu of the shapes, each picking the tool with that shape; it shows the shape
    /// last picked, prominent while it's the finger's.
    @ViewBuilder
    private var shapesButton: some View {
        let selected = tool == .shape
        let menu = Menu {
            ForEach(RefineShape.allCases, id: \.self) { kind in
                Button { pickShape(kind) } label: {
                    Label { shapeName(kind) } icon: { Image(systemName: kind.systemImage) }
                }
            }
        } label: {
            Image(systemName: shape.systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(selected ? Color.white : Color.primary)
                .frame(width: 30, height: 30)
        }
        .buttonBorderShape(.circle)
        .accessibilityLabel(Text("Shapes"))
        .accessibilityValue(shapeName(shape))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("refine-tool-shapes")
        .accessibilityShowsLargeContentViewer { Label { Text("Shapes") } icon: { Image(systemName: shape.systemImage) } }
        if selected {
            menu.buttonStyle(.glassProminent).tint(Theme.signature)
        } else {
            menu.buttonStyle(.glass)
        }
    }

    private func shapeName(_ kind: RefineShape) -> Text {
        switch kind {
        case .line: Text("Line")
        case .rectangle: Text("Rectangle")
        case .oval: Text("Oval")
        case .curve: Text("Curve")
        }
    }

    private func pickShape(_ kind: RefineShape) {
        if kind != shape { finishCurve() }
        shape = kind
        pick(.shape)
    }

    private func pick(_ tool: RefineTool) {
        guard tool != self.tool else { return }
        FeedbackEngine.shared.selectionChanged()
        // A stroke under way was the other tool's, and a curve waiting to be bent stays straight.
        endStroke()
        finishCurve()
        self.tool = tool
    }

    /// The Pencil's double tap: a pen's eraser, or an eraser's pen, of the same kind.
    private func pencilTap() {
        guard model.hasLineArtInput, let partner = tool.pencilPartner else { return }
        pick(partner)
    }
}
