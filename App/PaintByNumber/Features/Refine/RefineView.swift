import Accessibility
import Foundation
import PaintCore
import SwiftUI
import UIKit

/// The create flow's optional Refine step (`TemplateRefinements`): the drawing large, on its
/// paper, over the photo or over the painting finished (every area in its paint), where one
/// finger draws lines and takes them out, and two fingers zoom and move; a tap of two fingers
/// undoes. What the painter does is made by hand to the template (PaintCore's `TemplateEditor`,
/// `CreateModel.edit(_:)`): no image processing, no new template. A line is the line drawn, as the
/// outline of the areas it closes too, and nothing the painter didn't touch changes:
/// - the Pen draws a line as drawn (smoothed as it showed); with Snap, an end within a fingertip
///   of a line moves onto it and an overshoot past or along one is cut back, so the cell closes
///   as the painter meant (`PenAssist`); the sides of the areas it cuts that the photo tells apart take their own
///   paints;
/// - Shapes draws a straight line, a rectangle, an oval or a curve across a drag
///   (`RefineShape`, `ShapePath`), shown as it will be while the finger is down; a line's or a
///   curve's ends move onto a line they land near, as the Pen's do;
/// - the Eraser rubs out what it touches (ink within its reach is cut at the edge of it), and a
///   tap takes out a dab;
/// - the Line Eraser rubs too, and a tap takes the line out from junction to junction;
/// - Fill: a tap inside a closed shape makes it an area of its own, painted the photo's color
///   where it was tapped (`LineEdit.photoColor`), kept however small, its number allowed down to
///   about half the usual size and read zoomed in (a detail area, `Template.detailRegions`); a
///   tap in a filled area clears it (`EditFills`). A shape left open fills the area around it,
///   which shows at once, and Undo takes it back. Refine zooms in far
///   (`RefineSurfaceView.maximumZoom`), so a Pencil outlines a star of a few pixels comfortably.
/// An edit the template can't take (a line that doubles back on itself) changes nothing and says
/// so, in a toast VoiceOver announces; so does a shape a line closed that has no room for a
/// number (the line stays).
/// The gestures are iPad drawing apps' (`RefineTouchSurface`): two fingers tap to undo and three
/// to redo, held to keep going; a quick pinch fits the picture; four fingers tap for the full
/// screen; a touch held still is the Eyedropper, its loupe under the finger, with any tool; a
/// palette swatch dropped on a cell pours its paint. With Only Draw with Apple Pencil on, the Pencil
/// draws and taps and one finger moves the picture; otherwise fingers draw too. The Pencil's
/// double tap and squeeze do what iPadOS's settings ask (`RefinePencilAction`), and its hover shows
/// the tool's reach. The Layers panel (`RefineLayers`) shows or hides the numbers, the ink, the
/// paint (the template painted, every area in its paint, `TemplateRasterizer.Style.paintedAreas`:
/// the painting the changes make, once the template has them) and the photo, the paint and the
/// photo at an opacity of their own. Text corrects the text the app found (a tap turns a found
/// line off or on again, a drag across a line marks it).
///
/// An edit lands in a few hundredths of a second, off the main actor, and the screen then shows
/// the new template with no crossfade; until it does, the edit shows over the last template in the
/// drawing's own ink (`RefineInkLayer`), so a line is there the moment it is drawn and gone the
/// moment it is erased, and a fill shows as a swatch of its color where it was tapped
/// (`RefineFillLayer`, which then tints the areas fills made in their paint, under the drawing).
/// The text corrections still make the template again, as the sliders do, and the edits are laid
/// on the new one. Undo and Redo (⌘Z, ⇧⌘Z) step through the changes
/// (`CreateModel.history`; an edit taken back or put back comes at once from the templates kept),
/// Cancel puts back what the screen opened with (asking first when there are changes), Done keeps
/// them.
///
/// The tools are laid out as the Toolbox, a drawing app's:
/// Ink, Cells, Paint, Numbers and See, every tool in a rail on iPad and in group tabs on iPhone; a
/// Pen of ink alone with Snap and Color from Photo, Bend Line, Select, Cell Edge, Merge, Move Edge,
/// a palette with a current paint, the Bucket, the Paint Brush, the Eyedropper, Edit Paint,
/// Move Number, Try Painting; Start From until the first edit
/// (the generator's template, or the photo as one area to draw and paint everything on); an area's
/// card from Select's Change Color, sparkles where a line closes off an area and a badge for numbers
/// near their floor (`RefineStudio.swift`, `RefineToolbox.swift`, App/CLAUDE.md › Create flow › The
/// Toolbox), and keys for the tools ([ and ] for a size, ⌘0 to fit, ⌃⌘F for the full screen).
struct RefineView: View {
    let model: CreateModel
    /// The screen's state and what its gestures do with it (`RefineModel`), kept from the first
    /// `init`: the ones made after it, as the views above lay out again, are let go unused.
    @State private var refine: RefineModel

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @Environment(\.accessibilitySwitchControlEnabled) private var switchControlEnabled
    @AppStorage(SettingsKey.lineWeight) private var lineWeight = LineWeight.default
    /// Where the bar's Layers button is on the screen, which the panel hangs from (`layersHook`).
    @State private var layersAnchor = RefineLayersAnchor()
    /// The panel opens from the Layers button itself: on a practice canvas, and when a tap found
    /// no bar button to hang it under (the bar built otherwise, its items in an overflow menu), so
    /// the button never opens nothing.
    @State private var layersFromButton = false
    /// The tallest the tools along the bottom have been, the least room they keep: picking a tool
    /// with a shorter bar no longer grows the canvas, nor a taller one (once seen) shrinks it, so
    /// the picture neither moves under the finger nor loses its zoom (the exploratory QA of
    /// October 21 tapped where it had been).
    @State private var toolsHeight: CGFloat = 0
    /// The tools' own height now, which another width starts the room from.
    @State private var toolsMeasured: CGFloat = 0
    /// Cancel asks first when there are changes to lose.
    @State private var confirmsCancel = false
    @Environment(\.horizontalSizeClass) private var sizeClass
    /// Compact on a phone on its side, where the tools stand beside the picture (`usesSide`).
    @Environment(\.verticalSizeClass) private var heightClass
    /// The painter's text size: the Studio clamps its own at `.xxLarge`, and its options lay out
    /// as a column from the accessibility sizes on.
    @Environment(\.dynamicTypeSize) private var typeSize
    /// Whether a line's ends join the lines they land near (`PenAssist`): the Toolbox's Snap.
    @AppStorage(SettingsKey.refineSnaps) private var snaps = SettingsDefault.refineSnaps
    /// Whether a drawn line gives the pieces it cuts the photo's colors (`TemplateEditor.painted`):
    /// the Toolbox's Color from Photo, off, so the Pen draws ink alone.
    @AppStorage(SettingsKey.refinePenColors) private var penColors = SettingsDefault.refinePenColors
    /// The Paint Brush's Size: its radius on screen, in points.
    @AppStorage(SettingsKey.refineBrushSize) private var brushSize = SettingsDefault.refineBrushSize
    /// The Eraser's and the Line Eraser's Size: their radius on screen, in points.
    @AppStorage(SettingsKey.refineEraserSize) private var eraserSize = SettingsDefault.refineEraserSize
    /// The Pen's Smoothing, 0 to 1 (`RefineGestures.steadied`, Procreate's StreamLine).
    @AppStorage(SettingsKey.refinePenSmoothing) private var penSmoothing = SettingsDefault.refinePenSmoothing
    /// The top controls' height (Start From, the badge), for where they lie over the picture.
    @State private var topControlsHeight: CGFloat = 0
    /// Whether the rail scrolls and has tools below what shows.
    @State private var railHasMore = false
    /// Whether the column beside the picture scrolls and has more above what shows.
    @State private var sideHasMore = false
    /// Whether the column's tools leave room for the tiny-numbers badge, and the room it takes.
    @State private var sideBadge = true
    @State private var sideBadgeRoom: CGFloat = 0
    /// A Tool Guide page's practice canvas (`RefineGuideView`): the tool it teaches over the
    /// practice picture, with Undo, Redo, Layers and Reset above it in place of the screen's
    /// bars, and none of the other tools.
    private let practice: RefinePracticeSetup?
    /// Reset on a practice canvas: the page makes the canvas again, from the picture.
    private let onReset: (() -> Void)?
    /// A practice canvas's layers as the painter sets them, for the page to keep through Reset.
    private let layersChanged: ((RefineLayers) -> Void)?

    init(model: CreateModel) {
        self.init(model: model, practice: nil)
    }

    /// Refine, or with `practice` a Tool Guide page's practice canvas on `model`'s practice picture
    /// (`CreateModel.practice(_:scene:)`).
    init(
        model: CreateModel, practice: RefinePracticeSetup?, onReset: (() -> Void)? = nil,
        layersChanged: ((RefineLayers) -> Void)? = nil
    ) {
        self.model = model
        self.practice = practice
        self.onReset = onReset
        self.layersChanged = layersChanged
        _refine = State(initialValue: RefineModel(model: model, practice: practice))
        if practice != nil {
            // A practice's switches are its own, from the painter's: the Pen's page turning Color
            // from Photo on leaves Refine's Pen as it was.
            let store = RefinePracticeSetup.settings
            _snaps = AppStorage(wrappedValue: SettingsDefault.refineSnaps, SettingsKey.refineSnaps, store: store)
            _penColors = AppStorage(wrappedValue: SettingsDefault.refinePenColors, SettingsKey.refinePenColors, store: store)
            _brushSize = AppStorage(wrappedValue: SettingsDefault.refineBrushSize, SettingsKey.refineBrushSize, store: store)
            _eraserSize = AppStorage(wrappedValue: SettingsDefault.refineEraserSize, SettingsKey.refineEraserSize, store: store)
            _penSmoothing = AppStorage(
                wrappedValue: SettingsDefault.refinePenSmoothing, SettingsKey.refinePenSmoothing, store: store)
        }
    }

    /// Where the screen shows and how the painter's tools are set, as the model's gestures read
    /// them (`RefineModel.Surroundings`).
    private var surroundings: RefineModel.Surroundings {
        RefineModel.Surroundings(
            reduceMotion: reduceMotion, usesRail: usesRail, lineWeight: lineWeight, snaps: snaps, penColors: penColors,
            brushSize: brushSize, eraserSize: eraserSize, penSmoothing: penSmoothing)
    }

    var body: some View {
        stage
        .onAppear {
            // Before the first landing, which may start ahead of the canvas's own appearing.
            refine.surroundings = surroundings
            if !isPractice { PaintTips.desk.enter(.refine) }
            // Once: Try Painting's cover makes it disappear and appear again, and the history and
            // what Cancel puts back are the screen's, not the cover's.
            guard !refine.opened else { return }
            refine.opened = true
            model.beginRefining()
            // A draft refined before (Continue Refining) has found how to draw already.
            if model.refinements.isEmpty, !isPractice { PaintTips.refineShown() }
        }
        .onDisappear {
            model.dismissNote()
            if !isPractice { PaintTips.desk.leave(.refine) }
        }
        .onChange(of: model.closedShape) { _, shape in
            if let shape { refine.closed(shape) }
        }
        // Make Cell is for a shape a line closed with no room for a number of its own: its tip
        // comes then. After any line, it sent newcomers to tap shapes already areas of their own,
        // and nothing showed (round 5's QA, November 5).
        .onChange(of: model.note?.kind == .tooSmall) { _, small in
            if small, !isPractice { PaintTips.refineLineDrawn() }
        }
        // On a phone its button was in a tab not showing then, and the tip waited: Cells shows it.
        .onChange(of: refine.group) { _, group in
            if group == .cells, !isPractice { PaintTips.refineCellsShown() }
        }
        .onChange(of: refine.layers) { layersChanged?(refine.layers) }
        #if DEBUG
        .onChange(of: refine.picture) {
            guard let at = refine.demoCardAt, refine.card != nil, let template = refine.base?.template else { return }
            refine.card = RefineAreaPick(at: at, screen: refine.onScreen(refine.picturePoint(at)), template: template)
        }
        // Once the demo's card closes, a card opened after it stays where it was opened.
        .onChange(of: refine.card == nil) { _, closed in
            if closed { refine.demoCardAt = nil }
        }
        #endif
        .fullScreenCover(item: $refine.trial) { trial in
            PaintView(session: trial.session, title: String(localized: "Try Painting"), onClose: { refine.trial = nil })
        }
        .task(id: Landing(preview: model.preview?.id, settled: model.settledEdits, showsPainting: refine.showsPainting)) {
            await refine.land()
        }
    }

    /// Whether this is a Tool Guide page's practice canvas.
    private var isPractice: Bool {
        practice != nil
    }

    /// Refine's screen, or a practice canvas.
    @ViewBuilder
    private var stage: some View {
        if practice != nil {
            practiceScreen
        } else {
            refineScreen
        }
    }

    private var refineScreen: some View {
        NavigationStack {
            // Erased too, for margin under the rest of the screen's nesting (`canvas`).
            AnyView(canvas
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if !refine.fullScreen, !usesSide { reservedTools }
                }
                .safeAreaInset(edge: .leading, alignment: .top, spacing: 0) {
                    if usesRail, !refine.fullScreen { RefineToolRail(refine: refine, railHasMore: $railHasMore) }
                }
                .safeAreaInset(edge: .trailing, spacing: 0) {
                    if usesSide, !refine.fullScreen { sideTools }
                }
                .background(Theme.paper)
                .overlay { layersHook }
                .navigationTitle(screenTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbar }
                .toolbarVisibility(refine.fullScreen || usesSide ? .hidden : .visible, for: .navigationBar)
                .statusBarHidden(refine.fullScreen)
                .persistentSystemOverlays(refine.fullScreen ? .hidden : .automatic))
        }
        .fullScreenCover(item: $refine.guide) { topic in RefineGuideView(opening: topic) }
        .onChange(of: refine.base?.id) { refine.landedColors() }
        // The tools along the bottom are measured afresh when they come back from the side, and
        // a Layers panel opened beside the picture hangs from the bar's button once upright.
        .onChange(of: usesSide) {
            toolsHeight = 0
            layersFromButton = false
        }
    }

    /// What the screen draws over: when any of it changes, `land` brings `base` up to date.
    private struct Landing: Hashable {
        var preview: UUID?
        var settled: Int
        var showsPainting: Bool
    }

    // MARK: Canvas

    /// Refine's picture and what lies over it. Its parts are type-erased (`AnyView`) because the
    /// whole as one nested SwiftUI type overflowed the iPad's 1 MB main-thread stack in the
    /// unoptimized Debug build: the runtime resolves a type's generic arguments recursively, and
    /// the simulator's 8 MB stack never showed it (painting-company row 319). Each erased part
    /// is resolved on its own, so keep new layers and modifiers inside one of them rather than
    /// nesting them all again.
    private var canvas: some View {
        AnyView(canvasStack)
        // After the picture's own accessibility, which ignores its children: the cells, Start From
        // and the badge are elements of their own, the cells beneath the rest.
        .overlay { cellElements }
        .overlay(alignment: .top) {
            // Beside the picture, they head the tools' column (`sideTools`).
            if !isPractice, !refine.fullScreen, !usesSide {
                topControls
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { topControlsHeight = $0 }
                    .padding(topControlsInsets)
                    // They give way to a note at once and come back once it has slid away: back
                    // at once, the badge lay under the leaving note (the Mac's Refine round 2).
                    .animation(
                        model.note == nil && !reduceMotion ? .easeIn(duration: 0.2).delay(Self.afterNote) : nil,
                        value: model.note)
            }
        }
        // A draft that couldn't be saved, with its Retry, under the note (a practice canvas keeps
        // no draft).
        .overlay(alignment: .top) {
            if !isPractice {
                VStack(spacing: 8) {
                    RefineNoteToast(note: model.note).hidden()
                    DraftSaveToast(photoID: model.photoID)
                }
                .padding(.top, 12)
                .animation(reduceMotion ? nil : .snappy, value: model.note)
            }
        }
        .overlay(alignment: .topTrailing) {
            if refine.fullScreen { exitFullScreen.padding(12) }
        }
        .popover(item: $refine.card, attachmentAnchor: .rect(.rect(refine.card?.anchor ?? .zero))) { pick in
            // A sheet where a popover can't be (only the rail's iPad opens it).
            areaCard(pick)
                .presentationDetents([.medium, .large])
                .presentationCompactAdaptation(.sheet)
        }
        // Its own view, so the card's popover and this one don't share an anchor.
        .background {
            Color.clear
                .popover(
                    isPresented: Binding(get: { refine.pencilPalette != nil }, set: { if !$0 { refine.pencilPalette = nil } }),
                    attachmentAnchor: .rect(.rect(refine.pencilPalette ?? .zero))
                ) { RefinePencilPalette(refine: refine) }
        }
    }

    /// The picture, the touch surface over it and what shows above them, with the canvas's own
    /// accessibility.
    private var canvasStack: some View {
        ZStack {
            if let photo = model.source?.preview {
                // A card, as the preview's comparison is; zoomed in, its corners leave the screen.
                RefinePictureLayers.card
                    .fill(Theme.surface)
                    .shadow(color: .black.opacity(0.12), radius: 20, x: 0, y: 10)
                    .frame(width: refine.picture.width, height: refine.picture.height)
                    .position(x: refine.picture.midX, y: refine.picture.midY)
                AnyView(RefinePictureLayers(refine: refine, photo: photo))
            }
            RefineTouchSurface(
                aspectRatio: refine.aspectRatio,
                onLayout: { rect, zoom in
                    refine.picture = rect
                    refine.zoom = zoom
                },
                onDraw: refine.draw, onTap: refine.tap, onUndo: refine.undo, onRedo: refine.redo, onRepeat: refine.repeatStep, holdPicks: !refine.tool.drags,
                strokes: refine.tool.strokes,
                onPencil: refine.pencil, onHold: refine.held, onHover: refine.hovered, onDrop: refine.dropped, onDropHover: refine.dropHovered,
                onFullScreen: { if !isPractice { refine.toggleFullScreen() } }, keys: keys, onKey: pressed, keysRequest: refine.keysRequest,
                focus: refine.focus)
                // The model's gestures read the environment and the settings from here. In the
                // erased stack, on a view that is always there, it adds nothing to the screen's
                // own nesting (`canvas`).
                .onChange(of: surroundings, initial: true) { _, now in refine.surroundings = now }
            if let hold = refine.hold, let space = refine.base?.template.colorSpace {
                RefineLoupe(
                    picked: hold.color.map { RefinePalette.color($0, space: space) },
                    current: refine.currentPaint.map { RefinePalette.color($0, space: space) })
                    .position(RefineLoupe.position(over: refine.onScreen(hold.at), in: refine.canvasSize))
            }
            if let sparkles = refine.sparkles {
                RefineSparkles(point: sparkles.point, extent: sparkles.extent, stars: Sky.current() == .moon)
                    .id(sparkles.id)
            }
        }
        .clipped()
        .overlay(alignment: .bottom) {
            // Above a taller tool that rises over the canvas (`reservedTools`).
            status.padding(12).padding(.bottom, refine.fullScreen || usesSide ? 0 : max(0, toolsMeasured - toolsHeight))
        }
        .overlay(alignment: .top) { RefineNoteToast(note: model.note).padding(.top, 12) }
        .animation(.easeInOut(duration: 0.2), value: model.phase)
        .animation(reduceMotion ? nil : .snappy, value: model.note)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { refine.canvasSize = $0 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(String(
            localized: "refine.canvas", defaultValue: "Painting to refine",
            comment: "VoiceOver label of the Refine screen's picture, where lines are drawn and erased; its value counts the changes")))
        .accessibilityValue(Self.changes(model.shownChangeCount))
        .accessibilityActions {
            if model.canRedo { Button("Redo", action: refine.redo) }
            if !isPractice {
                Button(action: refine.toggleFullScreen) { refine.fullScreen ? Text("Exit Full Screen") : Text("Full Screen") }
            }
        }
        .accessibilityIdentifier("refine-canvas")
    }

    /// The cells in view as VoiceOver and Switch Control elements, while a cell tool is picked
    /// (`RefineCellElements`; demo launches have them too, for the UI tests).
    @ViewBuilder
    private var cellElements: some View {
        if speaksCells, RefineCellElements.tools.contains(refine.tool), model.hasLineArtInput, let template = refine.base?.template {
            let anchors = RefineCells.anchors(in: template)
            RefineCellElements(
                template: template, anchors: anchors, picture: refine.picture, canvas: refine.canvasSize, tool: refine.tool,
                selected: refine.tool == .select ? refine.selectedRegion : nil,
                activate: { region in refine.tap(at: refine.picturePoint(anchors[region])) },
                merge: { region, neighbour in
                    guard let probe = try? TemplateEditor.MergeProbe(template),
                          let edit = RefineCells.merge(region, with: neighbour, in: template, probe: probe)
                    else { return model.tell(.notMerged) }
                    refine.submit(edit)
                },
                moveNumber: { region, direction in
                    guard let edit = RefineCells.moveNumber(of: region, direction, in: template) else { return model.tell(.notMoved) }
                    refine.submit(edit)
                })
        }
    }

    private var speaksCells: Bool {
        #if DEBUG
        if DemoMode.isActive { return true }
        #endif
        return voiceOverEnabled || switchControlEnabled
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

    /// `edit`, a drawn line with no paints to give unless `colorsFromPhoto`.
    nonisolated static func inked(_ edit: TemplateEditor.Edit, colorsFromPhoto: Bool) -> TemplateEditor.Edit {
        guard !colorsFromPhoto, case .draw(let points, let closed, nil) = edit else { return edit }
        return .draw(points: points, closed: closed, paints: [])
    }

    // MARK: Changes

    /// Cancel: at once with nothing to lose, else once the painter says to discard the changes
    /// (an edit still on its way counts: it isn't in the history yet).
    private func askToCancel() {
        if model.canUndo || !refine.submitted.isEmpty { confirmsCancel = true } else { cancel() }
    }

    private func cancel() {
        model.cancelRefining()
        dismiss()
    }

    /// Keeps the changes, a curve waiting to be bent among them (as switching tools keeps it).
    private func done() {
        refine.finishCurve()
        dismiss()
    }

    /// Named for the way in (painting-company row 239): a blank page's drawing, or ✎ Change
    /// on a painting or a picture.
    private var screenTitle: Text {
        #if UNRELEASED
        // 1.3's names (painting-company row 331): Edit, for Refine and ✎ Change alike.
        model.isScratch ? Text("Blank Page") : Text("Edit")
        #else
        model.isScratch ? Text("Blank Page") : Text("Change")
        #endif
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

    /// The top bar's controls; a phone on its side has none, its controls heading the tools'
    /// column (`sideBar`), so the picture has the screen's whole height.
    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if !usesSide {
            ToolbarItem(placement: .cancellationAction) { cancelButton }
            ToolbarItem(placement: .topBarLeading) { guideButton }
            ToolbarItemGroup(placement: .primaryAction) {
                // ⌘Z and ⇧⌘Z are the canvas's (`keys`), the full screen's too, where this bar hides.
                undoButton
                redoButton
                layersButton
            }
            // A phone's bar has room for its six controls but not the title, which showed as "R…"
            // (QA, October 28): its middle is left empty there, as the views' menu once filled it.
            if !usesRail {
                ToolbarItem(placement: .principal) {
                    Color.clear.frame(width: 1, height: 1).accessibilityHidden(true)
                }
                .sharedBackgroundVisibility(.hidden)
            }
            ToolbarItem(placement: .confirmationAction) { doneButton }
        }
    }

    private var cancelButton: some View {
        Button("Cancel", systemImage: "xmark", action: askToCancel)
            .keyboardShortcut(refine.isCovered || refine.fullScreen ? nil : .cancelAction)
            .accessibilityIdentifier("refine-cancel")
            .confirmationDialog(Text("Discard Your Changes?"), isPresented: $confirmsCancel, titleVisibility: .visible) {
                Button("Discard Changes", role: .destructive, action: cancel)
                #if UNRELEASED
                Button("Keep Editing", role: .cancel) {}
                #else
                Button("Keep Refining", role: .cancel) {}
                #endif
            }
    }

    private var guideButton: some View {
        Button("Tool Guide", systemImage: "questionmark.circle") {
            FeedbackEngine.shared.selectionChanged()
            refine.guide = RefineGuideTopic.opening(at: refine.tool)
        }
        .accessibilityHint(Text(String(
            localized: "refine.guide.open.hint", defaultValue: "What each tool does, with a picture to try it on.",
            comment: "Refine screen: VoiceOver hint of the Tool Guide button, which opens a page per tool with a description and a practice canvas")))
        .accessibilityIdentifier("refine-guide")
    }

    private var undoButton: some View {
        Button("Undo", systemImage: "arrow.uturn.backward", action: refine.undo)
            .disabled(!model.canUndo)
            .accessibilityIdentifier("refine-undo")
    }

    private var redoButton: some View {
        Button("Redo", systemImage: "arrow.uturn.forward", action: refine.redo)
            .disabled(!model.canRedo)
            .accessibilityIdentifier("refine-redo")
    }

    private var doneButton: some View {
        Button("Done", systemImage: "checkmark", action: done)
            .tint(Theme.signature)
            .keyboardShortcut(refine.isCovered ? nil : .defaultAction)
            .accessibilityIdentifier("refine-done")
    }

    /// The top bar's controls at the head of the tools' column on a phone on its side: Cancel and
    /// the Tool Guide, then Undo, Redo, Layers and Done, as the bar has them; two rows where one
    /// doesn't fit (larger text).
    private var sideBar: some View {
        let leading = GlassEffectContainer(spacing: 6) {
            HStack(spacing: 6) {
                cancelButton
                guideButton
            }
            .buttonStyle(.glass)
        }
        let trailing = HStack(spacing: 6) {
            GlassEffectContainer(spacing: 6) {
                HStack(spacing: 6) {
                    undoButton
                    redoButton
                    layersButton
                }
                .buttonStyle(.glass)
            }
            doneButton.buttonStyle(.glassProminent)
        }
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 0) {
                leading
                Spacer(minLength: 6)
                trailing
            }
            VStack(alignment: .trailing, spacing: 8) {
                HStack(spacing: 0) {
                    leading
                    Spacer(minLength: 0)
                }
                trailing
            }
        }
        .labelStyle(.iconOnly)
        .buttonBorderShape(.circle)
    }

    /// The tools, keeping the room of the tallest they have been (`toolsHeight`). A taller tool
    /// (Select's band with a cell picked, an area's card, the looks) rises over the canvas's empty
    /// paper under the picture where that holds it, and takes more room only where it would cover
    /// the picture: each new one moved and shrank the picture once (QA, November 7).
    private var reservedTools: some View {
        tools
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                toolsMeasured = height
                if height > toolsHeight, !risesUnderPicture(height) { toolsHeight = height }
            }
            .frame(height: toolsHeight > 0 ? toolsHeight : nil, alignment: .bottom)
            // Another width (a rotation, a resized window) lays the tools out anew: measured again.
            // The tools as they are now count, though their height doesn't change with the width
            // (the picture jumped at the first change of group, QA, October 28).
            .onChange(of: refine.canvasSize.width) { toolsHeight = toolsMeasured }
    }

    /// Whether tools `height` tall fit in the room kept for them and the paper under the picture
    /// as it fits the canvas, leaving the picture's margin.
    private func risesUnderPicture(_ height: CGFloat) -> Bool {
        guard toolsHeight > 0, refine.canvasSize.height > 0 else { return false }
        let margin = RefineSurfaceView.margin
        let fitted = CompareView.fitted(
            refine.aspectRatio, in: CGSize(width: refine.canvasSize.width - 2 * margin, height: refine.canvasSize.height - 2 * margin))
        return height - toolsHeight <= (refine.canvasSize.height - fitted.height) / 2 - margin
    }

    /// What the finger does, along the bottom (`studioBar`): the picked tool's options and, on
    /// iPhone, the groups and the group's tools. How each tool works is its button's VoiceOver
    /// hint, and how to draw at all a tip said once (`RefineDrawTip`); only a curve waiting to be
    /// bent says what comes next.
    private var tools: some View {
        VStack(spacing: 12) {
            curveHint
            studioBar
        }
        // On iPhone the tip on drawing hangs from the top of the Pen's options, over the picture
        // above them: from the Pen, under them, it covered Snap, Color from Photo and the groups
        // (QA, November 7). The iPad's hangs beside the Pen in the rail.
        .gentleTip(.refineDraw, active: !usesRail && !isPractice, arrowEdge: .bottom)
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .background(Theme.paper)
        // Like the painting's bars: larger text sizes reach the buttons through the Large
        // Content Viewer.
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
    }

    /// What comes next for a curve waiting to be bent. It keeps its room from the moment the Curve
    /// is picked, unseen until then: appearing, it moved the picture up under the finger about to
    /// bend it (QA, October 29).
    @ViewBuilder
    private var curveHint: some View {
        if refine.tool == .shape, refine.shape == .curve {
            Text(refine.hint(for: .shape))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 480)
                .opacity(refine.curve != nil ? 1 : 0)
                .accessibilityHidden(refine.curve == nil)
                .accessibilityIdentifier("refine-hint")
        }
    }
}

// MARK: The Studio

extension RefineView {
    /// Whether every tool stands in a rail along the leading edge (iPad), rather than in group tabs
    /// over a row of the group's tools (iPhone, and a phone on its side however wide).
    private var usesRail: Bool { sizeClass == .regular && !usesSide }

    /// Whether the tools stand in a column beside the picture rather than under it: a phone on its
    /// side, where under them the picture was about 190 × 130 points, gone with the looks, and the
    /// widest phones' rail and card left it little more (QA, November 7 and 9).
    private var usesSide: Bool { heightClass == .compact && !isPractice }

    /// What the column's scroll view reports: whether there is more above, and how tall its
    /// tools are against its room.
    private struct SideScroll: Equatable {
        var above: Bool
        var content: CGFloat
        var room: CGFloat
    }

    /// The column's width: the groups' five tabs and a group's five tools fit across it.
    private static let sideWidth: CGFloat = 300

    /// The column's foot: Start From and, with `badge`, the tiny-numbers badge, then the tool's
    /// options, the palette, the groups and the tools.
    private func sideToolsFoot(badge: Bool) -> some View {
        VStack(spacing: 12) {
            // An area's card takes the room of everything but Select's band: under the badge,
            // over the groups and the tools, it was cut at the top of the smallest phone.
            if refine.barCard == nil {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        RefineStartChooser(refine: refine)
                        if badge { RefineTinyBadge(refine: refine) }
                    }
                    VStack(spacing: 8) {
                        RefineStartChooser(refine: refine)
                        if badge { RefineTinyBadge(refine: refine) }
                    }
                }
                .animation(
                    model.note == nil && !reduceMotion ? .easeIn(duration: 0.2).delay(Self.afterNote) : nil,
                    value: model.note)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                    if badge { sideBadgeRoom = height + 12 }
                }
            }
            curveHint
            studioBar
        }
    }

    /// A phone on its side: the tools in a column along the trailing edge, on the paper, the
    /// picture beside it the screen's whole height. The top bar's controls head it; at its foot,
    /// under the thumb, Start From and the badge, off the picture, then the tool's options (bare
    /// on the paper), the palette, the groups and the tools, as along the bottom, scrolling where
    /// a tool's options are taller than the screen.
    private var sideTools: some View {
        VStack(spacing: 12) {
            sideBar
            // The bar's controls stay put while the tools scroll: scrolled with them, Done and
            // Undo left the screen with the looks. One scroll view, the tools at its foot where
            // they fit: a choice of copies would make the area's card anew as it grew, closing
            // its color picker.
            ScrollView { sideToolsFoot(badge: sideBadge) }
                .scrollBounceBehavior(.basedOnSize)
                .scrollIndicatorsFlash(onAppear: true)
                .defaultScrollAnchor(.bottom)
                // Its head fades while there is more above: cut off hard, an area's card looked
                // broken. The badge gives way before the tools scroll: scrolled, it lay half
                // faded under the head with the looks.
                .onScrollGeometryChange(for: SideScroll.self) { geometry in
                    SideScroll(
                        above: geometry.contentOffset.y + geometry.contentInsets.top > 1,
                        content: geometry.contentSize.height, room: geometry.containerSize.height)
                } action: { _, scroll in
                    sideHasMore = scroll.above
                    sideBadge = scroll.content + (sideBadge ? 0 : sideBadgeRoom) <= scroll.room + 0.5
                }
                .mask {
                    VStack(spacing: 0) {
                        LinearGradient(colors: [.black.opacity(sideHasMore ? 0 : 1), .black], startPoint: .top, endPoint: .bottom)
                            .frame(height: 40)
                        Color.black
                    }
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: sideHasMore)
                }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(width: Self.sideWidth)
        .gentleTip(.refineDraw, active: !isPractice, arrowEdge: .trailing)
        // The room the badge was measured to need included Start From beside it: when Start From
        // comes or goes, the badge is tried again, and gives way again, measured afresh, if it
        // still doesn't fit (once the first edit took Start From away, it never came back).
        .onChange(of: refine.showsStartFrom) { sideBadge = true }
        .background(Theme.paper)
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
    }

    /// Whether the palette shows: in Cells and Paint, but for Make Cell, whose cell takes the
    /// photo's color (QA, October 28: the palette there looked like the color it would use).
    private var showsPalette: Bool { (refine.group == .cells || refine.group == .paint) && refine.tool != .fill }

    /// The Studio's bottom: the picked tool's options, the cell Select picked, the palette (in
    /// Cells and Paint), and on iPhone the groups and the group's tools.
    @ViewBuilder
    private var studioBar: some View {
        RefineToolOptions(
            refine: refine, usesSide: usesSide, typeSize: typeSize, snaps: $snaps, penColors: $penColors,
            brushSize: $brushSize, eraserSize: $eraserSize, penSmoothing: $penSmoothing)
        if showsPalette, let template = refine.base?.template {
            if refine.tool == .select, let region = refine.selectedRegion {
                selectionBand(template: template, region: region)
            } else {
                RefinePaletteBar(template: template, current: $refine.currentPaint, picked: $refine.newColors, merge: refine.paletteMerge)
                    .disabled(!model.hasLineArtInput)
            }
        }
        if practice?.teaches == .tryPainting {
            Button("Try Painting", systemImage: "paintbrush", action: refine.tryPainting)
                .buttonStyle(.glassProminent)
                .tint(Theme.signature)
                .disabled(refine.base == nil)
                .accessibilityIdentifier("refine-practice-try")
        }
        // Beside the picture, an area's card takes their room (`sideTools`).
        if !usesRail, practice == nil, !(usesSide && refine.barCard != nil) {
            let groups = Picker("Tools", selection: Binding(get: { refine.group }, set: { refine.choose($0) })) {
                ForEach(RefineGroup.allCases, id: \.self) { kind in
                    Self.groupName(kind).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            .disabled(!model.hasLineArtInput)
            .accessibilityIdentifier("refine-groups")
            if usesSide {
                // A segmented control's segments are as wide as its widest: in the column it cut
                // "Numbers" short. Each name at its own width there, smaller where it must be.
                ViewThatFits(in: .horizontal) {
                    sideGroups.font(.subheadline)
                    sideGroups.font(.footnote)
                    groups
                }
            } else {
                groups.frame(maxWidth: 420)
            }
            // Centred where the row fits (a group holds at most five), scrolling where it doesn't
            // (larger text).
            ViewThatFits(in: .horizontal) {
                groupRow
                ScrollView(.horizontal) { groupRow }
                    .scrollIndicators(.hidden)
            }
        }
    }

    /// The groups in the column beside the picture: each name a button at its own width, the
    /// group on screen marked.
    private var sideGroups: some View {
        HStack(spacing: 2) {
            ForEach(RefineGroup.allCases, id: \.self) { kind in
                let selected = kind == refine.group
                Button { refine.choose(kind) } label: {
                    Self.groupName(kind)
                        .fontWeight(selected ? .semibold : .regular)
                        .foregroundStyle(Color.primary)
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background {
                            if selected {
                                Capsule()
                                    .fill(Theme.surface)
                                    .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(2)
        .background(.fill.tertiary, in: .capsule)
        .fixedSize()
        .disabled(!model.hasLineArtInput)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Tools"))
        .accessibilityIdentifier("refine-groups")
    }

    /// The group's tools, each a round button.
    private var groupRow: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 8) {
                ForEach(refine.group.tools, id: \.self) { kind in
                    RefineToolButton(refine: refine, kind: kind)
                        .disabled(!model.hasLineArtInput)
                }
            }
            .padding(.horizontal, 2)
        }
    }

    // MARK: Options

    /// The Layers button and its panel (`RefineLayersPanel`), the picked tool's layer marked: from
    /// the button on a practice canvas and in the column beside the picture (`sideBar`), from
    /// `layersHook` under the bar's (`RefineLayersAnchor`).
    private var layersButton: some View {
        layersButtonAlone.popover(
            isPresented: Binding(get: { refine.showsLayers && (isPractice || usesSide || layersFromButton) }, set: { refine.showsLayers = $0 })
        ) { layersPanel }
    }

    private var layersPanel: some View {
        RefineLayersPanel(layers: $refine.layers, working: refine.tool.layer)
            .presentationCompactAdaptation(.popover)
    }

    /// The screen's side of `RefineLayersAnchor`: the panel points up at the Layers button's place
    /// and opens below the bar, once the button has one (a demo opens the panel before).
    private var layersHook: some View {
        Color.clear
            .refineLayersAnchor(layersAnchor)
            .popover(
                isPresented: Binding(
                    get: { refine.showsLayers && !isPractice && !usesSide && !layersFromButton && layersAnchor.buttonFrame != nil },
                    set: { refine.showsLayers = $0 }),
                // Its arrow a little under the button, not flush with the bar's glass.
                attachmentAnchor: .rect(.rect((layersAnchor.buttonFrame ?? .zero).offsetBy(dx: 0, dy: 4))), arrowEdge: .top
            ) { layersPanel }
            .ignoresSafeArea()
            .onAppear { layersAnchor.refresh() }
            // The bar may have moved its buttons since the screen was last laid out.
            .onChange(of: refine.showsLayers) { if refine.showsLayers { layersAnchor.refresh() } }
    }

    private var layersButtonAlone: some View {
        Button("Layers", systemImage: "square.3.layers.3d") {
            FeedbackEngine.shared.selectionChanged()
            layersFromButton = !isPractice && !usesSide && layersAnchor.buttonOnScreen == nil
            refine.showsLayers = true
        }
        .accessibilityHint(Text(String(
            localized: "refine.layers.hint", defaultValue: "Shows or hides the numbers, the ink, the paint and the photo.",
            comment: "Refine screen: VoiceOver hint of the Layers button, which opens a panel of what shows (numbers, ink, paint, photo)")))
        .accessibilityIdentifier("refine-layers")
    }

    // MARK: Full screen

    /// The way back from full screen, in the corner.
    private var exitFullScreen: some View {
        Button(action: refine.toggleFullScreen) {
            Label { Text("Exit Full Screen") } icon: { Image(systemName: "arrow.down.right.and.arrow.up.left") }
                .labelStyle(.iconOnly)
                .font(.body.weight(.semibold))
                .frame(width: 30, height: 30)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .accessibilityIdentifier("refine-exit-full-screen")
        .transition(.opacity)
    }

    // MARK: Keys

    /// A hardware keyboard's keys (their names show while ⌘ is held), the canvas's
    /// (`RefineSurfaceView.keyCommands`): a tool each, as drawing apps letter them (P Pen, E Eraser,
    /// B Brush, I Eyedropper, G Bucket, V Select), [ and ] for the size, ⌘0 to fit the picture, ⌃⌘F
    /// for the full screen, ⌘Z and ⇧⌘Z, the same keys whatever shows: keys a first responder adds
    /// later went unheard (Escape and ⌘Z in the full screen, CI, October 28). Done (Return) and
    /// Cancel (Escape) are their buttons'. None on a practice canvas, nor under the Tool Guide or
    /// Try Painting, which have keys of their own.
    private var keys: [RefineKey] {
        guard !isPractice, !refine.isCovered, model.hasLineArtInput else { return [] }
        var keys = Self.toolKeys.map { RefineKey(input: $0.key, modifiers: $0.modifiers, title: Self.toolTitle($0.tool), action: .tool($0.tool)) }
        keys += [
            RefineKey(input: "[", modifiers: [], title: String(localized: "Smaller"), action: .smaller),
            RefineKey(input: "]", modifiers: [], title: String(localized: "Larger"), action: .larger),
            RefineKey(input: "0", modifiers: .command, title: String(localized: "Fit to Screen"), action: .fit),
            RefineKey(input: "f", modifiers: [.command, .control], title: String(localized: "Full Screen"), action: .fullScreen),
            RefineKey(input: "z", modifiers: .command, title: String(localized: "Undo"), action: .undo),
            RefineKey(input: "z", modifiers: [.command, .shift], title: String(localized: "Redo"), action: .redo),
        ]
        return keys
    }

    /// What a key asks for.
    private func pressed(_ action: RefineKey.Action) {
        switch action {
        case .tool(let tool): refine.toolTapped(tool)
        case .smaller: resize(by: -2)
        case .larger: resize(by: 2)
        case .fit: refine.fit()
        case .fullScreen: refine.toggleFullScreen()
        case .undo: refine.undo()
        case .redo: refine.redo()
        }
    }

    /// [ and ]: the Paint Brush's or the Eraser's Size, a step smaller or larger.
    private func resize(by step: Double) {
        switch refine.tool {
        case .brush: brushSize = min(max(brushSize + step, Self.sizes.lowerBound), Self.sizes.upperBound)
        case .eraser, .smartEraser: eraserSize = min(max(eraserSize + step, Self.sizes.lowerBound), Self.sizes.upperBound)
        default: return
        }
        FeedbackEngine.shared.selectionChanged()
    }

    // MARK: Cells and paint

    @ViewBuilder
    private func areaCard(_ pick: RefineAreaPick, inBar: Bool = false) -> some View {
        if let template = refine.base?.template {
            RefineAreaCard(
                template: template, at: pick.at, isolates: pick.isolates, from: pick.from,
                paintArea: { model.paintArea(at: pick.at, color: $0, picking: true) },
                repaint: { from, to in refine.recolor(.repaint(from: from, to: to, family: false)) },
                showPaint: { paint in
                    refine.card = nil
                    refine.barCard = nil
                    refine.currentPaint = template.palette[paint].oklab
                    refine.pick(.editPaint)
                },
                inBar: inBar)
        }
    }

    /// The cell Select picked and the palette, one band (Rikyū, `factory/pieces/refine-phase3`):
    /// Change Color opens the cell's card beside it on iPad, and on iPhone in the band itself, in
    /// the palette's place (`barCard`), where nothing covers the picture.
    private func selectionBand(template: Template, region: Int) -> some View {
        VStack(spacing: 0) {
            RefineSelectionBar(template: template, region: region, cardOpen: refine.barCard != nil) {
                guard let selection = refine.selection else { return }
                FeedbackEngine.shared.selectionChanged()
                // Close closes, whatever the width has become since the card opened.
                if refine.barCard != nil {
                    refine.barCard = nil
                } else if usesRail {
                    refine.card = RefineAreaPick(at: selection, screen: refine.onScreen(refine.picturePoint(selection)), template: template)
                } else {
                    refine.barCard = RefineAreaPick(at: selection, screen: .zero, template: template)
                }
            }
            if let barCard = refine.barCard {
                areaCard(barCard, inBar: true)
            } else {
                RefinePaletteBar(template: template, current: $refine.currentPaint, picked: $refine.newColors, merge: refine.paletteMerge, glass: false)
                    .disabled(!model.hasLineArtInput)
            }
        }
        .padding(.vertical, 2)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
        .frame(maxWidth: 720)
        .transition(.opacity)
    }

    /// Start From and the tiny-numbers badge at the top's trailing end, side by side or, where they
    /// don't fit (larger text), the badge under the chooser: the leading end is where the first
    /// tip opens beside the Pen on iPad, and it hid Blank there (QA, November 3).
    private var topControls: some View {
        // Clamped as the rest of Refine is: the badge grew to cover the picture. The Large
        // Content Viewer shows it enlarged.
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 8) {
                Spacer(minLength: 0)
                RefineStartChooser(refine: refine)
                RefineTinyBadge(refine: refine)
            }
            VStack(alignment: .trailing, spacing: 8) {
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    RefineStartChooser(refine: refine)
                }
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    RefineTinyBadge(refine: refine)
                }
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
    }

    /// How long Start From and the badge wait to come back after a note: as long as the note's
    /// own slide out (`.snappy`'s half second).
    static let afterNote: Double = 0.5

    /// Where Start From and the badge lie: at the canvas's top trailing corner, or, where that
    /// would put them over the picture (it grows to the canvas's top when Select, the paint tools or
    /// a card shrink it), just inside the picture's own corner, never hanging past its edge (QA,
    /// November 7: the badge hung over the picture's corner and past its side).
    private var topControlsInsets: EdgeInsets {
        let standard = EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12)
        let shown = refine.picture.intersection(CGRect(origin: .zero, size: refine.canvasSize))
        guard !shown.isNull, shown.width > 0, topControlsHeight > 0, shown.minY < 12 + topControlsHeight + 4 else {
            return standard
        }
        // Only the trailing edge follows the picture's: they lie at the trailing end, and a
        // picture narrower than they are mustn't squeeze them.
        return EdgeInsets(
            top: max(12, shown.minY + 8), leading: 12, bottom: 12,
            trailing: max(12, refine.canvasSize.width - shown.maxX + 8))
    }

    /// "12 tiny numbers".
    nonisolated static func tinyText(_ count: Int) -> String {
        String(
            localized: "refine.tiny", defaultValue: "\(count) tiny numbers",
            comment: "Refine screen: a badge counting the areas whose numbers are near the smallest a painter can read; a tap zooms in on the next one. The argument is the count")
    }
}

// MARK: Practice

extension RefineView {
    /// A Tool Guide page's practice canvas: the canvas, the tool's options (and the palette, in
    /// Cells and Paint) below it, and above it Undo, Redo, Layers and Reset.
    fileprivate var practiceScreen: some View {
        canvas
            .safeAreaInset(edge: .top, spacing: 0) { practiceBar }
            .safeAreaInset(edge: .bottom, spacing: 0) { reservedTools }
            .background(Theme.paper)
    }

    /// Undo, Redo, Layers and Reset.
    private var practiceBar: some View {
        HStack(spacing: 10) {
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    Button("Undo", systemImage: "arrow.uturn.backward", action: refine.undo)
                        .disabled(!model.canUndo)
                        .keyboardShortcut("z")
                        .accessibilityIdentifier("refine-undo")
                    Button("Redo", systemImage: "arrow.uturn.forward", action: refine.redo)
                        .disabled(!model.canRedo)
                        .keyboardShortcut("z", modifiers: [.command, .shift])
                        .accessibilityIdentifier("refine-redo")
                    layersButton
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
            }
            Spacer(minLength: 0)
            Button("Reset", systemImage: "arrow.counterclockwise", action: resetPractice)
                .buttonStyle(.glass)
                .disabled(!model.canUndo && model.refinements.edits.isEmpty)
                .accessibilityHint(Text(String(
                    localized: "refine.practice.reset.hint", defaultValue: "Puts the practice picture back as it was.",
                    comment: "Tool Guide: VoiceOver hint of Reset above a tool's practice canvas, which undoes everything tried on it")))
                .accessibilityIdentifier("refine-practice-reset")
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 4)
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
    }

    /// Reset: the practice picture as the page opened it, with the canvas made again (its tool's
    /// options and current paint too).
    private func resetPractice() {
        FeedbackEngine.shared.selectionChanged()
        model.cancelRefining()
        onReset?()
    }
}

/// Try Painting's painting: a session on the template as it stood, which nothing saves.
struct RefineTrial: Identifiable {
    let id = UUID()
    let session: PaintingSession
}
