import PaintCore
import SwiftUI

/// What one finger (or the Pencil) does on the Refine screen.
nonisolated enum RefineTool: Hashable {
    /// Draws lines as they are drawn.
    case pen
    /// Draws lines that come out straight when nearly straight, or held at the end, and whose
    /// ends join the lines they come near (`PenAssist`).
    case smartPen
    /// Rubs out what it touches; a tap takes out a dab.
    case eraser
    /// Rubs lines out, or takes out the one tapped, junction to junction (`LineChains`).
    case smartEraser
    /// A tap makes the closed shape under it an area of its own in the photo's color there, or
    /// clears that again (`RefineFills`).
    case fill
    /// Settings › Detail Brushes: areas brushed for more or less detail, that brushing cleared,
    /// and the text the app found corrected.
    case more, less, unbrush, text

    /// The tool the Pencil's double tap switches to: a pen's eraser, an eraser's pen.
    var pencilPartner: RefineTool? {
        switch self {
        case .pen: .eraser
        case .eraser: .pen
        case .smartPen: .smartEraser
        case .smartEraser: .smartPen
        case .fill, .more, .less, .unbrush, .text: nil
        }
    }

    var erases: Bool { self == .eraser || self == .smartEraser }
}

/// The create flow's optional Refine step (`TemplateRefinements`): the drawing large, on its
/// paper or over the photo, where one finger draws lines and takes them out, and two fingers
/// zoom and move; a tap of two fingers undoes. Two kinds of tools, exact and assisted:
/// - the Pen draws a line as drawn (smoothed as it showed); only an end whose ink touches a
///   line's moves onto it, by no more than the ink's width, so the cell closes as it looks;
/// - the Smart Pen straightens a nearly straight line, or one held still at its end, and joins
///   each end to a line within `joinReach` (a break's ends first); the line under the finger
///   shows as it will be, rings where its ends join;
/// - the Eraser rubs out what it touches, and a tap takes out a dab;
/// - the Smart Eraser rubs too, and a tap takes the line out from junction to junction
///   (`LineChains`);
/// - Fill: a tap inside a closed shape makes it an area of its own, painted the photo's color
///   where it was tapped (`LineEdit.photoColor`), kept however small, its number allowed down to
///   about half the usual size and read zoomed in (a detail area, `Template.detailRegions`); a
///   tap in a filled area clears it (`RefineFills`). A shape left open fills the area around it,
///   which shows at once, and Undo takes it back. Refine zooms in far
///   (`RefineSurfaceView.maximumZoom`), so a Pencil outlines a star of a few pixels comfortably.
/// Once an Apple Pencil touches the canvas (or with Only Draw with Apple Pencil on), the Pencil
/// draws and taps and one finger moves the picture, so a palm leaves no mark; its double tap
/// switches between a kind's pen and eraser. With Settings › Detail Brushes one finger also
/// brushes areas for more or less detail, clears that brushing, and corrects the text the app
/// found (a tap turns a found line off or on again, a drag across a line marks it).
///
/// Each change regenerates the template at full resolution (`CreateModel.refine`); until the new
/// template comes, what the painter did shows over the last one in the drawing's own ink
/// (`RefineInkLayer`), so a line is there the moment it is drawn and gone the moment it is
/// erased, and a fill shows as a swatch of its color where it was tapped (`RefineFillLayer`,
/// which then tints the areas fills made in their paint, under the drawing). Undo and Redo (⌘Z,
/// ⇧⌘Z) step through the changes (a template already made comes back at once), Cancel puts back
/// what the screen opened with, Done keeps them.
struct RefineView: View {
    let model: CreateModel

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(SettingsKey.lineWeight) private var lineWeight = LineWeight.default
    /// Settings › Detail Brushes, as the screen opened (Settings isn't reachable from it).
    private let detailBrushes = Preferences().detailBrushes
    @State private var tool: RefineTool
    @State private var showsPhoto = false
    /// What the screen opened with: Cancel puts it back.
    @State private var opening: TemplateRefinements
    @State private var undoStack: [TemplateRefinements] = []
    @State private var redoStack: [TemplateRefinements] = []
    /// The template the screen draws over: the newest at full resolution.
    @State private var base: CreateModel.Preview?
    /// The pen's line or the eraser's pass under the finger, until it lifts.
    @State private var trace: [SIMD2<Float>]?
    /// The lines a pen's ends may join, as its stroke began.
    @State private var snapLines: SnapLines?
    /// The Smart Pen rested `holdDelay` at the end of its line: the line is straight.
    @State private var held = false
    /// Where the Smart Pen last came to rest, and a count of its rests (a hold checks its own).
    @State private var restPoint: SIMD2<Float>?
    @State private var rests = 0
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
        _opening = State(initialValue: model.refinements)
        _base = State(initialValue: model.preview)
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
        .onChange(of: model.preview?.id) {
            if let preview = model.preview, !preview.isDraft || base == nil { base = preview }
        }
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
                ZStack {
                    if showsPhoto || base == nil {
                        Image(decorative: photo, scale: 1)
                            .resizable()
                            .interpolation(.high)
                            .frame(width: picture.width, height: picture.height)
                            .position(x: picture.midX, y: picture.midY)
                    }
                    if let base {
                        LineArtLayer(drawing: base.drawing, picture: picture, scale: zoom, overPhoto: showsPhoto)
                            .equatable()
                    }
                    RefineFillLayer(
                        base: base, fills: model.refinements.lines.filter { $0.kind == .fill }, photo: model.source?.image,
                        rect: picture)
                        .equatable()
                    let assisted = assistedTrace
                    RefineInkLayer(
                        lines: pending, trace: assisted?.points ?? trace, traceIsDrawn: assisted != nil,
                        joins: assisted?.joins ?? [], erasing: tool.erases, eraserRadius: eraserRadius,
                        rect: picture, lineWidth: lineWidth, photo: showsPhoto || base == nil ? photo : nil)
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
        .animation(.easeInOut(duration: 0.2), value: model.phase)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { canvasSize = $0 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(String(
            localized: "refine.canvas", defaultValue: "Painting to refine",
            comment: "VoiceOver label of the Refine screen's picture, where lines are drawn and erased; its value counts the changes")))
        .accessibilityValue(Self.changes(model.refinements.changeCount))
        .accessibilityIdentifier("refine-canvas")
    }

    private static let card = RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)

    /// The lines drawn and erased that the template on screen doesn't have yet: those after
    /// the ones it was made with. Fills change no line (`RefineFillLayer` shows them).
    private var pending: [TemplateRefinements.Line] {
        let lines = model.refinements.lines.filter { $0.kind != .fill }
        let made = (base?.refinements.lines ?? []).filter { $0.kind != .fill }
        var common = 0
        while common < lines.count && common < made.count && lines[common] == made[common] { common += 1 }
        return Array(lines[common...])
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

    /// The eraser too, a little finer: a thirtieth of the short side, between 10 and 20 points.
    private var eraserRadius: Float {
        let points = min(max(0.033 * min(canvasSize.width, canvasSize.height), 10), 20)
        return pictureLong > 0 ? Float(points / pictureLong) : 0.02
    }

    @ViewBuilder
    private var status: some View {
        if model.phase == .generating {
            HStack(spacing: 10) {
                ProgressView(value: model.progress)
                    .frame(width: 64)
                Text("Refining…")
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
        case .pen, .smartPen, .eraser, .smartEraser: follow(touch, at: point)
        case .text: mark(touch, at: point)
        case .more, .less, .unbrush: brush(touch, at: point)
        // A fill is a tap: a drag does nothing.
        case .fill: break
        }
    }

    /// The pen's line or the eraser's pass follows the finger; when it lifts, it joins the
    /// refinements, the pen's as it showed.
    private func follow(_ touch: RefineTouch, at point: SIMD2<Float>) {
        switch touch {
        case .began:
            trace = [point]
            held = false
            snapLines = tool.erases ? nil : currentSnapLines()
            if tool == .smartPen { rest(at: point) }
        case .moved:
            if tool == .smartPen { settle(at: point) }
            // Samples closer than a point add nothing the line shows.
            guard var current = trace, let last = current.last, onScreen(point - last) >= 1 else { return }
            current.append(point)
            trace = current
        case .ended:
            guard var current = trace else { return }
            current.append(point)
            let line: TemplateRefinements.Line? = tool.erases
                ? TemplateRefinements.Line(kind: .erase, radius: eraserRadius, points: simplified(current, tolerance: 0.5))
                : drawnLine(current, smart: tool == .smartPen, holding: held)?.line
            endStroke()
            guard let line else { return }
            commit { $0.lines.append(line) }
        case .cancelled:
            endStroke()
        }
    }

    private func endStroke() {
        trace = nil
        held = false
        restPoint = nil
        snapLines = nil
    }

    /// The shortest line the pen draws, in the template's canvas units: the template keeps no
    /// stroke inside a cell shorter than 6 (`LineLayering.minimumRun`), so a shorter one would
    /// show only until the template came.
    static let shortestLine: CGFloat = 8
    /// How far (points on screen) the Smart Pen's ends reach for a line to join: about a
    /// fingertip's width, so a line ended near another, or drawn across a break, meets it.
    static let joinReach: CGFloat = 16
    /// The Smart Pen's straightness floor (points on screen): a short stroke wandering this
    /// little still counts as straight (`PenAssist.isNearlyStraight`).
    static let straightFloor: CGFloat = 2
    /// The Pen's ends move onto a line whose ink theirs touches: within one ink width (half of
    /// each), and at least this many points.
    static let touchFloor: CGFloat = 2
    /// The Smart Pen held this still (points on screen) for `holdDelay` at its end draws straight,
    /// as Notes' pen does.
    static let holdSlop: CGFloat = 3
    static let holdDelay: Duration = .milliseconds(500)
    /// A hold straightens only a line at least this long (points on screen): resting as the
    /// stroke begins isn't one.
    static let holdMinimum: CGFloat = 12

    /// The Smart Pen's line under the finger as it will be drawn, with where its ends join.
    private var assistedTrace: (points: [SIMD2<Float>], joins: [SIMD2<Float>])? {
        guard tool == .smartPen, let trace, let drawn = drawnLine(trace, smart: true, holding: held) else { return nil }
        return (drawn.line.points, drawn.joins)
    }

    /// A pen's line from its samples: smoothed and thinned on screen's terms as it showed. The
    /// Smart Pen's comes out straight when nearly straight or `holding` (held at its end), and
    /// its ends join the lines within `joinReach`; the Pen's only where its ink touches a line's
    /// (`touchFloor`). Nil for a touch too short to be a line, on screen or in the template.
    private func drawnLine(
        _ points: [SIMD2<Float>], smart: Bool, holding: Bool
    ) -> (line: TemplateRefinements.Line, joins: [SIMD2<Float>])? {
        let size = picture.size
        guard size.width > 0, size.height > 0 else { return nil }
        let onScreen = points.map { CGPoint(x: CGFloat($0.x) * size.width, y: CGFloat($0.y) * size.height) }
        // The template's canvas units per point on screen.
        let canvas = base?.drawing.size ?? .zero
        let units = canvas.width / size.width
        let shortest = units > 0 ? max(4, Self.shortestLine / units) : 4
        guard PenPath.length(onScreen) >= shortest else { return nil }
        var line = PenPath.simplified(PenPath.smoothed(onScreen, spacing: 2), tolerance: 0.3)
        let straight = smart && (holding || PenAssist.isNearlyStraight(line, floor: Self.straightFloor))
        if straight { line = [line[0], line[line.count - 1]] }
        var joins: [CGPoint] = []
        if let snapLines, units > 0 {
            let inCanvas = line.map { CGPoint(x: $0.x / size.width * canvas.width, y: $0.y / size.height * canvas.height) }
            let reach = (smart ? Self.joinReach : max(lineWidth, Self.touchFloor)) * units
            let joined = PenAssist.joined(inCanvas, to: snapLines, reach: reach, preferringEnds: smart, straight: straight)
            line = joined.line.map { CGPoint(x: $0.x / canvas.width * size.width, y: $0.y / canvas.height * size.height) }
            joins = joined.joins.map { CGPoint(x: $0.x / canvas.width * size.width, y: $0.y / canvas.height * size.height) }
        }
        func normalized(_ p: CGPoint) -> SIMD2<Float> { SIMD2(Float(p.x / size.width), Float(p.y / size.height)) }
        return (TemplateRefinements.Line(kind: .draw, radius: 0, points: line.map(normalized)), joins.map(normalized))
    }

    /// The lines on screen, in the template's canvas units: its drawing, the lines drawn since,
    /// less what was erased since (`pending`).
    private func currentSnapLines() -> SnapLines? {
        guard let drawing = base?.drawing else { return nil }
        let size = drawing.size, long = max(size.width, size.height)
        func inCanvas(_ points: [SIMD2<Float>]) -> [CGPoint] {
            points.map { CGPoint(x: CGFloat($0.x) * size.width, y: CGFloat($0.y) * size.height) }
        }
        var lines = drawing.lines.map(\.points)
        for line in pending {
            switch line.kind {
            case .draw:
                lines.append(inCanvas(line.points))
            case .erase:
                lines = SnapLines.erasing(lines, by: [(inCanvas(line.points), CGFloat(line.radius) * long)])
            case .eraseLine:
                // The line itself: what meets it keeps its junction.
                lines = SnapLines.erasing(lines, by: [(inCanvas(line.points), 1.5)])
            case .fill:
                break
            }
        }
        return SnapLines(lines)
    }

    /// The Smart Pen came down, or moved off where it rested: it rests here now, and if it stays
    /// (within `holdSlop`) for `holdDelay` at the end of a line at least `holdMinimum` long, the
    /// line is straight from then on.
    private func rest(at point: SIMD2<Float>) {
        restPoint = point
        rests += 1
        let mine = rests
        Task {
            try? await Task.sleep(for: Self.holdDelay)
            guard mine == rests, tool == .smartPen, !held, let trace, screenLength(trace) >= Self.holdMinimum else { return }
            held = true
            FeedbackEngine.shared.selectionChanged()
        }
    }

    private func settle(at point: SIMD2<Float>) {
        guard !held else { return }
        if let restPoint, onScreen(point - restPoint) <= Self.holdSlop { return }
        rest(at: point)
    }

    /// `points` thinned to within `tolerance` points on screen.
    private func simplified(_ points: [SIMD2<Float>], tolerance: CGFloat) -> [SIMD2<Float>] {
        let size = picture.size
        guard size.width > 0, size.height > 0 else { return points }
        let onScreen = points.map { CGPoint(x: CGFloat($0.x) * size.width, y: CGFloat($0.y) * size.height) }
        return PenPath.simplified(onScreen, tolerance: tolerance).map {
            SIMD2(Float($0.x / size.width), Float($0.y / size.height))
        }
    }

    /// A step between two picture points, in points on screen.
    private func onScreen(_ step: SIMD2<Float>) -> CGFloat {
        hypot(CGFloat(step.x) * picture.width, CGFloat(step.y) * picture.height)
    }

    /// The length of a trace on screen, in points.
    private func screenLength(_ points: [SIMD2<Float>]) -> CGFloat {
        zip(points, points.dropFirst()).reduce(0) { $0 + onScreen($1.1 - $1.0) }
    }

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
            commit { $0.strokes.append(current) }
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
        case .pen, .smartPen:
            break
        case .eraser:
            // A dab, of the eraser's own reach.
            commit { $0.lines.append(TemplateRefinements.Line(kind: .erase, radius: eraserRadius, points: [point])) }
        case .smartEraser:
            eraseLine(at: point)
        case .fill:
            fill(at: point)
        case .text:
            toggleText(at: point)
        case .more, .less, .unbrush:
            // A dab.
            commit { $0.strokes.append(TemplateRefinements.Stroke(kind: brushKind, radius: brushRadius, points: [point])) }
        }
    }

    /// How far either side of a tapped line's path its line is taken out, in the template's
    /// canvas units: past the template's own reach for drawing an edge along a line
    /// (`LayeredLines.annotateNear`, 3), so the line the edges were drawn for goes whole.
    static let tapReach: CGFloat = 4.5

    /// Takes out the drawn line under a tap from junction to junction (`LineChains`): the lines
    /// it meets stay whole (`LineEdit.Kind.eraseLine`). The line glows as it goes.
    private func eraseLine(at point: SIMD2<Float>) {
        guard let drawing = base?.drawing, picture.width > 0 else { return }
        let size = drawing.size
        let tap = CGPoint(x: CGFloat(point.x) * size.width, y: CGFloat(point.y) * size.height)
        // A finger's width on screen, in canvas units.
        let unitsPerPoint = size.width / picture.width
        guard let chain = LineChains(drawing).chain(near: tap, tolerance: 16 * unitsPerPoint) else { return }
        let points = PenPath.simplified(chain, tolerance: 0.25).map {
            SIMD2(Float($0.x / size.width), Float($0.y / size.height))
        }
        let long = max(size.width, size.height)
        commit { $0.lines.append(TemplateRefinements.Line(kind: .eraseLine, radius: Float(Self.tapReach / long), points: points)) }
        FeedbackEngine.shared.selectionChanged()
        guard !reduceMotion else { return }
        tapped = chain.map { SIMD2(Float($0.x / size.width), Float($0.y / size.height)) }
        flashes = true
        Task {
            try? await Task.sleep(for: .milliseconds(60))
            withAnimation(.easeOut(duration: 0.45)) { flashes = false }
        }
    }

    /// How near (points on screen) a tap comes to a fill's swatch to clear it, before the
    /// template has it: about a fingertip.
    static let swatchReach: CGFloat = 16

    /// Fills the shape under a tap, or clears a fill made there (`RefineFills`).
    private func fill(at point: SIMD2<Float>) {
        guard picture.width > 0, picture.height > 0 else { return }
        let made = (base?.refinements.lines ?? []).filter { $0.kind == .fill }
        let reach = SIMD2(Float(Self.swatchReach / picture.width), Float(Self.swatchReach / picture.height))
        commit { refinements in
            refinements.lines = RefineFills.tapped(refinements.lines, at: point, made: made, template: base?.template, reach: reach)
        }
        FeedbackEngine.shared.selectionChanged()
    }

    /// A marked line is unmarked; a found line is turned off, or on again.
    private func toggleText(at point: SIMD2<Float>) {
        if let index = model.refinements.addedText.lastIndex(where: { Self.line($0, contains: point) }) {
            commit { $0.addedText.remove(at: index) }
        } else if let line = model.foundText.first(where: { Self.line($0, contains: point) }) {
            commit { refinements in
                if let hidden = refinements.hiddenText.firstIndex(where: { TemplateRefinements.sameLine(line, $0) }) {
                    refinements.hiddenText.remove(at: hidden)
                } else {
                    refinements.hiddenText.append(line)
                }
            }
        }
    }

    /// Marks the line dragged out from `a` to `b`, unless the drag was too small to hold one.
    private func mark(from a: SIMD2<Float>, to b: SIMD2<Float>) {
        guard abs(a.x - b.x) * Float(picture.width) >= 12, abs(a.y - b.y) * Float(picture.height) >= 6 else { return }
        commit { $0.addedText.append(TemplateRefinements.textLine(from: a, to: b)) }
    }

    /// Whether a tap at `point` falls on `line`, give or take a little for the finger.
    private static func line(_ line: [SIMD2<Float>], contains point: SIMD2<Float>) -> Bool {
        guard let bounds = TemplateRefinements.bounds(line) else { return false }
        return bounds.insetBy(dx: -0.01, dy: -0.01).contains(CGPoint(x: CGFloat(point.x), y: CGFloat(point.y)))
    }

    // MARK: Changes

    private func commit(_ change: (inout TemplateRefinements) -> Void) {
        var refinements = model.refinements
        change(&refinements)
        guard refinements != model.refinements else { return }
        undoStack.append(model.refinements)
        redoStack.removeAll()
        model.refine(refinements)
    }

    private func undo() {
        guard let previous = undoStack.popLast() else { return }
        trace = nil
        redoStack.append(model.refinements)
        model.refine(previous)
    }

    private func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(model.refinements)
        model.refine(next)
    }

    private func cancel() {
        model.refine(opening)
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
                .disabled(undoStack.isEmpty)
                .keyboardShortcut("z")
                .accessibilityIdentifier("refine-undo")
            Button("Redo", systemImage: "arrow.uturn.forward", action: redo)
                .disabled(redoStack.isEmpty)
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .accessibilityIdentifier("refine-redo")
        }
        ToolbarItem(placement: .confirmationAction) {
            Button("Done", systemImage: "checkmark") { dismiss() }
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

    private var lineTools: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 8) {
                toolButton(.pen, systemImage: "pencil.tip", label: Text("Pen"), id: "pen")
                    .disabled(!model.hasLineArtInput)
                toolButton(.smartPen, systemImage: "pencil.and.ruler", label: Text("Smart Pen"), id: "smart-pen")
                    .disabled(!model.hasLineArtInput)
                toolButton(.eraser, systemImage: "eraser", label: Text("Eraser"), id: "eraser")
                    .disabled(!model.hasLineArtInput)
                toolButton(.smartEraser, systemImage: "wand.and.stars", label: Text("Smart Eraser"), id: "smart-eraser")
                    .disabled(!model.hasLineArtInput)
                toolButton(.fill, systemImage: "drop.fill", label: Text("Fill"), id: "fill")
                    .disabled(!model.hasLineArtInput)
                Capsule()
                    .fill(Color.primary.opacity(0.15))
                    .frame(width: 1, height: 24)
                    .padding(.horizontal, 4)
                    .accessibilityHidden(true)
                photoButton
            }
        }
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
                   defaultValue: "Draw lines exactly as you draw them. Two fingers zoom and move, and a two-finger tap undoes.",
                   comment: "Refine screen: how the Pen works (it draws lines into the painting's drawing just where they are drawn), shown while it is picked")
        case .smartPen:
            String(localized: "refine.hint.smartPen",
                   defaultValue: "Draw lines that come out straight when nearly straight or when you hold at the end, and join the lines near their ends. Two fingers zoom and move.",
                   comment: "Refine screen: how the Smart Pen works (it straightens lines and joins their ends to nearby lines of the painting's drawing), shown while it is picked")
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

    /// Shows the photo beneath the drawing while it is on.
    @ViewBuilder
    private var photoButton: some View {
        let button = Button { showsPhoto.toggle() } label: {
            Image(systemName: "photo")
                .font(.body.weight(.semibold))
                .foregroundStyle(showsPhoto ? Color.white : Color.primary)
                .frame(width: 30, height: 30)
        }
        .buttonBorderShape(.circle)
        .accessibilityLabel(Text("Photo"))
        .accessibilityAddTraits(showsPhoto ? .isSelected : [])
        .accessibilityIdentifier("refine-photo")
        .accessibilityShowsLargeContentViewer { Label("Photo", systemImage: "photo") }
        if showsPhoto {
            button.buttonStyle(.glassProminent).tint(Theme.signature)
        } else {
            button.buttonStyle(.glass)
        }
    }

    private func pick(_ tool: RefineTool) {
        guard tool != self.tool else { return }
        FeedbackEngine.shared.selectionChanged()
        // A stroke under way was the other tool's.
        endStroke()
        self.tool = tool
    }

    /// The Pencil's double tap: a pen's eraser, or an eraser's pen, of the same kind.
    private func pencilTap() {
        guard model.hasLineArtInput, let partner = tool.pencilPartner else { return }
        pick(partner)
    }
}
