import PaintCore
import SwiftUI

/// What one finger does on the Refine screen.
enum RefineTool: Hashable {
    case more, less, text, eraser
}

/// The create flow's optional Refine step (`TemplateRefinements`): the template large, where one
/// finger brushes areas for more or less detail, or erases that brushing, and corrects the text
/// the app found (a tap turns a found line off or on again, a drag across a line marks it); two
/// fingers zoom and move. Each change regenerates the template as a slider does
/// (`CreateModel.refine`). Undo and Redo step through the changes, Cancel puts back what the
/// screen opened with, Done keeps them.
struct RefineView: View {
    let model: CreateModel

    @Environment(\.dismiss) private var dismiss
    @State private var tool: RefineTool = .more
    @State private var showsPhoto = false
    /// What the screen opened with: Cancel puts it back.
    @State private var opening: TemplateRefinements
    @State private var undoStack: [TemplateRefinements] = []
    @State private var redoStack: [TemplateRefinements] = []
    /// The stroke under the finger, until it lifts.
    @State private var stroke: TemplateRefinements.Stroke?
    /// The line of text being dragged out: where the drag began and where it is.
    @State private var marking: (SIMD2<Float>, SIMD2<Float>)?
    /// Where the picture is in the canvas, and its zoom (the touch surface's).
    @State private var picture: CGRect = .zero
    @State private var zoom: CGFloat = 1
    @State private var canvasSize: CGSize = .zero

    init(model: CreateModel) {
        self.model = model
        _opening = State(initialValue: model.refinements)
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
    }

    // MARK: Canvas

    private var canvas: some View {
        ZStack {
            if let photo = model.source?.preview {
                RefinePicture(picture: showsPhoto ? nil : model.preview?.picture, photo: photo, rect: picture, zoom: zoom)
                RefineMarks(
                    refinements: shown, found: model.foundText, marking: marking, rect: picture,
                    emphasizesText: tool == .text)
            }
            RefineTouchSurface(
                aspectRatio: aspectRatio,
                onLayout: { rect, zoom in
                    picture = rect
                    self.zoom = zoom
                },
                onDraw: draw, onTap: tap)
        }
        .clipped()
        .overlay(alignment: .bottom) { status.padding(12) }
        .animation(.easeInOut(duration: 0.2), value: model.phase)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { canvasSize = $0 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(String(
            localized: "refine.canvas", defaultValue: "Painting to refine",
            comment: "VoiceOver label of the Refine screen's picture, where areas are brushed and text is marked; its value counts the changes")))
        .accessibilityValue(Self.changes(model.refinements.changeCount))
        .accessibilityIdentifier("refine-canvas")
    }

    /// The refinements with the stroke still under the finger.
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

    /// The brush keeps its size on screen, so zoomed in it brushes finer: a twenty-fifth of the
    /// canvas's short side, between 14 and 30 points.
    private var brushRadius: Float {
        let points = min(max(0.04 * min(canvasSize.width, canvasSize.height), 14), 30)
        let long = max(picture.width, picture.height)
        return long > 0 ? Float(points / long) : 0.03
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

    private var strokeKind: TemplateRefinements.Stroke.Kind {
        switch tool {
        case .less: .less
        case .eraser: .erase
        case .more, .text: .more
        }
    }

    private func draw(_ touch: RefineTouch, at point: SIMD2<Float>) {
        if tool == .text {
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
            return
        }
        switch touch {
        case .began:
            stroke = TemplateRefinements.Stroke(kind: strokeKind, radius: brushRadius, points: [point])
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

    private func tap(at point: SIMD2<Float>) {
        guard tool == .text else {
            // A dab.
            commit { $0.strokes.append(TemplateRefinements.Stroke(kind: strokeKind, radius: brushRadius, points: [point])) }
            return
        }
        // A marked line is unmarked; a found line is turned off, or on again.
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
            comment: "VoiceOver value of the Refine button and the Refine screen's picture: how many strokes and text lines were changed")
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
                .accessibilityIdentifier("refine-undo")
            Button("Redo", systemImage: "arrow.uturn.forward", action: redo)
                .disabled(redoStack.isEmpty)
                .accessibilityIdentifier("refine-redo")
        }
        ToolbarItem(placement: .confirmationAction) {
            Button("Done", systemImage: "checkmark") { dismiss() }
                .accessibilityIdentifier("refine-done")
        }
    }

    /// What the finger does, with a line on how to use it, along the bottom.
    private var tools: some View {
        VStack(spacing: 12) {
            Text(hint)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 480)
                .accessibilityIdentifier("refine-hint")
            GlassEffectContainer(spacing: 10) {
                HStack(spacing: 8) {
                    toolButton(.more, systemImage: "plus", label: Text("More Detail"), id: "more")
                    toolButton(.less, systemImage: "minus", label: Text("Less Detail"), id: "less")
                    if model.hasLineArtInput {
                        toolButton(.text, systemImage: "text.viewfinder", label: Text("Text"), id: "text")
                    }
                    toolButton(.eraser, systemImage: "eraser", label: Text("Eraser"), id: "eraser")
                    Capsule()
                        .fill(Color.primary.opacity(0.15))
                        .frame(width: 1, height: 24)
                        .padding(.horizontal, 4)
                        .accessibilityHidden(true)
                    photoButton
                }
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

    private var hint: String {
        switch tool {
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
        case .eraser:
            String(localized: "refine.hint.eraser", defaultValue: "Brush over marked areas to clear them.",
                   comment: "Refine screen: how the Eraser works (it clears brushed areas), shown while it is picked")
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

    /// Shows the photo in place of the template while it is on.
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
