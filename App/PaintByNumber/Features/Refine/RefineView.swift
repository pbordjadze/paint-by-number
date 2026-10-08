import PaintCore
import SwiftUI

/// What one finger does on the Refine screen.
enum RefineTool: Hashable {
    /// Draws lines.
    case pen
    /// Rubs lines out, or takes out the one tapped.
    case eraser
    /// Settings › Detail Brushes: areas brushed for more or less detail, that brushing cleared,
    /// and the text the app found corrected.
    case more, less, unbrush, text
}

/// The create flow's optional Refine step (`TemplateRefinements`): the drawing large, on its
/// paper or over the photo, where one finger draws lines with the pen and takes them out with
/// the eraser (rubbing them out, or tapping a line to take it out from junction to junction,
/// `LineChains`), and two fingers zoom and move; a tap of two fingers undoes. With Settings ›
/// Detail Brushes one finger also brushes areas for more or less detail, clears that brushing,
/// and corrects the text the app found (a tap turns a found line off or on again, a drag across
/// a line marks it).
///
/// Each change regenerates the template at full resolution (`CreateModel.refine`); until the new
/// template comes, what the painter did shows over the last one in the drawing's own ink
/// (`RefineInkLayer`), so a line is there the moment it is drawn and gone the moment it is
/// erased. Undo and Redo (⌘Z, ⇧⌘Z) step through the changes (a template already made comes back
/// at once), Cancel puts back what the screen opened with, Done keeps them.
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
                    RefineInkLayer(
                        lines: pending, trace: trace, erasing: tool == .eraser, eraserRadius: eraserRadius,
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
                onDraw: draw, onTap: tap, onUndo: undo)
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
    /// the ones it was made with.
    private var pending: [TemplateRefinements.Line] {
        let lines = model.refinements.lines, made = base?.refinements.lines ?? []
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
        case .pen, .eraser: follow(touch, at: point)
        case .text: mark(touch, at: point)
        case .more, .less, .unbrush: brush(touch, at: point)
        }
    }

    /// The pen's line or the eraser's pass follows the finger; when it lifts, it joins the
    /// refinements, the pen's smoothed as it showed.
    private func follow(_ touch: RefineTouch, at point: SIMD2<Float>) {
        switch touch {
        case .began:
            trace = [point]
        case .moved:
            // Samples closer than a point add nothing the line shows.
            guard var current = trace, let last = current.last, onScreen(point - last) >= 1 else { return }
            current.append(point)
            trace = current
        case .ended:
            guard var current = trace else { return }
            current.append(point)
            trace = nil
            if tool == .pen {
                guard let line = penLine(current) else { return }
                commit { $0.lines.append(line) }
            } else {
                let path = simplified(current, tolerance: 0.5)
                commit { $0.lines.append(TemplateRefinements.Line(kind: .erase, radius: eraserRadius, points: path)) }
            }
        case .cancelled:
            trace = nil
        }
    }

    /// The pen's line as it was drawn, smoothed and thinned on screen's terms; nil for a touch
    /// too short to be a line.
    private func penLine(_ points: [SIMD2<Float>]) -> TemplateRefinements.Line? {
        let size = picture.size
        guard size.width > 0, size.height > 0 else { return nil }
        let onScreen = points.map { CGPoint(x: CGFloat($0.x) * size.width, y: CGFloat($0.y) * size.height) }
        guard PenPath.length(onScreen) >= 4 else { return nil }
        let line = PenPath.simplified(PenPath.smoothed(onScreen, spacing: 2), tolerance: 0.3)
        return TemplateRefinements.Line(
            kind: .draw, radius: 0,
            points: line.map { SIMD2(Float($0.x / size.width), Float($0.y / size.height)) })
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
        case .pen:
            break
        case .eraser:
            eraseLine(at: point)
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

    /// What the finger does, with a line on how to use it, along the bottom: the pen, the eraser
    /// and the photo beneath, and the detail brushes in a row of their own where there isn't
    /// room for one.
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
                toolButton(.eraser, systemImage: "eraser", label: Text("Eraser"), id: "eraser")
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
                   defaultValue: "Draw lines with one finger: their ends join the lines they touch. Two fingers zoom and move, and a two-finger tap undoes.",
                   comment: "Refine screen: how the Pen works (it draws lines into the painting's drawing), shown while it is picked")
        case .eraser:
            String(localized: "refine.hint.eraser",
                   defaultValue: "Rub lines out with one finger, or tap a line to erase all of it. Two fingers zoom and move.",
                   comment: "Refine screen: how the Eraser works (it takes lines out of the painting's drawing), shown while it is picked")
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
        self.tool = tool
    }
}
