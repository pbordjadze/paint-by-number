import Accessibility
import Foundation
import PaintCore
import SwiftUI
import UIKit

/// What one finger (or the Pencil) does on the Refine screen.
nonisolated enum RefineTool: Hashable, CaseIterable {
    /// Draws lines as they are drawn.
    case pen
    /// Draws the shape picked (`RefineShape`) across a drag.
    case shape
    /// The Toolbox's Bend Line: a drag moves the line under it, bending it near where it was
    /// grabbed (`TemplateEditor.Edit.reshape`).
    case bendLine
    /// Rubs out what it touches; a tap takes out a dab.
    case eraser
    /// Rubs lines out, or takes out the one tapped, junction to junction (`LineChains`).
    case smartEraser
    /// The Toolbox's Select: a tap picks the cell under it, which shows its outline and a bar
    /// with its paint (`RefineSelectionBar`); a tap on it again lets it go.
    case select
    /// The Toolbox's Cell Edge: a stroke divides a cell where it goes and draws no line, both
    /// sides keeping the paint (`TemplateEditor.Edit.cellEdge`).
    case cellEdge
    /// The Toolbox's Merge: a drag across cells joins them into the first, boundaries and all
    /// (`TemplateEditor.Edit.merge`).
    case merge
    /// The Toolbox's Move Edge: a drag moves a cell's boundary, inked or not, so the cell and its
    /// neighbour change shape (`TemplateEditor.Edit.reshape`, as Bend Line's).
    case moveEdge
    /// A tap makes the closed shape under it an area of its own in the photo's color there, or
    /// clears that again (`EditFills`).
    case fill
    /// The Toolbox's Bucket: a tap gives the cell under it the current paint
    /// (`TemplateEditor.Edit.paintArea`).
    case bucket
    /// The Toolbox's Paint Brush: the stroke's footprint takes the current paint, joining the
    /// cells of that paint it meets (`TemplateEditor.Edit.brush`); a tap is a dab.
    case brush
    /// The Toolbox's Eyedropper: a tap makes the cell's paint the current paint, or over the
    /// photo the photo's color there.
    case eyedropper
    /// The Toolbox's Edit Paint: the current paint takes a new color everywhere it's used
    /// (`RefineColorsPanel`'s picker); a tap on a cell makes its paint the current one.
    case editPaint
    /// The Toolbox's Looks over every paint (`RefineColorsPanel`'s row).
    case looks
    /// The Toolbox's Move Number: a drag moves a number within its cell
    /// (`TemplateEditor.Edit.moveLabel`).
    case moveNumber
    /// The text the app found corrected: a tap turns a found line off or on again, a drag marks
    /// one it missed.
    case text
    /// The Toolbox's Try Painting: the painting screen on the template as it stands, saving
    /// nothing. An action, never the finger's tool.
    case tryPainting

    /// The Toolbox's group the tool stands in (`RefineGroup`), which lists its tools in the order
    /// they are declared here: a new tool doesn't compile without its place.
    var group: RefineGroup {
        switch self {
        case .pen, .shape, .bendLine, .eraser, .smartEraser: .ink
        case .select, .cellEdge, .merge, .moveEdge, .fill: .cells
        case .bucket, .brush, .eyedropper, .editPaint, .looks: .paint
        case .moveNumber: .numbers
        case .text, .tryPainting: .see
        }
    }

    /// The tool the Pencil's Switch Between Current Tool and Eraser picks: a drawing tool's
    /// eraser, an eraser's pen.
    var pencilPartner: RefineTool? {
        switch self {
        case .pen, .shape: .eraser
        case .eraser, .smartEraser: .pen
        case .fill, .text, .select, .cellEdge, .merge, .brush, .bucket, .eyedropper, .editPaint, .looks, .bendLine,
             .moveEdge, .moveNumber, .tryPainting:
            nil
        }
    }

    /// What the tool does shows in the painting (paints, and a cell edge, which draws no line), so
    /// the painting shows beneath it.
    /// The tool drags something already there (a line, an edge, a number), drawing no ink.
    var drags: Bool { self == .bendLine || self == .moveEdge || self == .moveNumber }

    /// A one-finger drag does something with the tool (`RefineModel.draw`); the others only tap.
    var strokes: Bool {
        switch self {
        case .pen, .shape, .bendLine, .eraser, .smartEraser, .cellEdge, .merge, .moveEdge, .brush, .moveNumber, .text: true
        case .select, .fill, .bucket, .eyedropper, .editPaint, .looks, .tryPainting: false
        }
    }

    var paints: Bool {
        self == .cellEdge || self == .brush || self == .bucket || self == .editPaint || self == .looks
    }

    var erases: Bool { self == .eraser || self == .smartEraser }
}

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
/// a palette with a current paint, the Bucket, the Paint Brush, the Eyedropper, Edit Paint and
/// Looks, Move Number, Try Painting; Start From until the first edit
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
    /// For the draft's save toast, which the tiny-numbers badge makes way for.
    @Environment(Library.self) private var library: Library?
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
                    if usesRail, !refine.fullScreen { toolRail }
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
                ) { pencilPaletteView }
        }
    }

    /// The picture, the touch surface over it and what shows above them, with the canvas's own
    /// accessibility.
    private var canvasStack: some View {
        ZStack {
            if let photo = model.source?.preview {
                // A card, as the preview's comparison is; zoomed in, its corners leave the screen.
                Self.card
                    .fill(Theme.surface)
                    .shadow(color: .black.opacity(0.12), radius: 20, x: 0, y: 10)
                    .frame(width: refine.picture.width, height: refine.picture.height)
                    .position(x: refine.picture.midX, y: refine.picture.midY)
                AnyView(pictureLayers(photo: photo))
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

    /// The picture's layers, from the paper up to the hover mark, masked to the card.
    @ViewBuilder
    private func pictureLayers(photo: CGImage) -> some View {
        // The photo shows through what lies over it; under opaque paint the lines are drawn
        // as over the paint.
        let showsPhoto = refine.base == nil || refine.layers.photoStrength > 0
        let painted = refine.showsPainting && refine.base != nil && refine.painting?.preview == refine.base?.id ? refine.painting?.image : nil
        ZStack {
            // The paper, beneath every layer: it shows where the paint and the photo are
            // hidden or faint.
            Rectangle()
                .fill(LineArtDrawing.paper)
                .frame(width: refine.picture.width, height: refine.picture.height)
                .position(x: refine.picture.midX, y: refine.picture.midY)
            if refine.layers.photo || refine.base == nil {
                Image(decorative: photo, scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: refine.picture.width, height: refine.picture.height)
                    .position(x: refine.picture.midX, y: refine.picture.midY)
                    .opacity(refine.base == nil ? 1 : refine.layers.photoOpacity)
            }
            if let painted {
                Image(decorative: painted, scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: refine.picture.width, height: refine.picture.height)
                    .position(x: refine.picture.midX, y: refine.picture.midY)
                    .opacity(refine.layers.paintOpacity)
                    // New colors cross-fade in (`land`).
                    .id(refine.painting?.preview)
                    .transition(.opacity)
            }
            // The brush's strokes until they land, in their paint under the drawing's ink,
            // which a brush never covers.
            RefineInkLayer(
                lines: [], trace: nil, traceIsDrawn: false, erasing: false, brushes: refine.brushes,
                eraserRadius: refine.eraserRadius, rect: refine.picture, lineWidth: refine.lineWidth, beneath: nil, halo: false)
            if let base = refine.base, refine.layers.ink {
                LineArtLayer(
                    drawing: base.drawing, picture: refine.picture, scale: refine.zoom, overPhoto: showsPhoto,
                    overPaint: painted != nil && !showsPhoto)
                    .equatable()
            }
            RefineFillLayer(
                base: refine.base, fills: refine.filledPoints, swatches: refine.swatches, space: model.source?.image.colorSpace, rect: refine.picture,
                showsAreas: painted == nil)
                .equatable()
            // Not Bend Line's: a bend passes over them, re-cutting the cells it crosses.
            if refine.group == .cells, let cellEdges = refine.cellEdges {
                RefineCellEdges(id: cellEdges.id, size: refine.templateSize, path: cellEdges.path, rect: refine.picture)
                    .equatable()
            }
            if !refine.glowAreas.isEmpty {
                RefinePaintGlow(base: refine.base, areas: refine.glowAreas, rect: refine.picture, reduceMotion: reduceMotion)
                    .equatable()
            }
            let figure = refine.shapeTrace
            RefineInkLayer(
                lines: refine.layers.ink ? refine.pending : [], trace: refine.tool == .shape ? figure : refine.tool.drags || refine.tool == .brush ? nil : refine.penTrace,
                traceIsDrawn: refine.tool == .shape, erasing: refine.tool.erases, dashed: refine.tool == .cellEdge, merging: refine.tool == .merge,
                eraserRadius: refine.eraserRadius, rect: refine.picture, lineWidth: refine.lineWidth,
                beneath: showsPhoto ? photo : painted, halo: showsPhoto)
            if let bend = refine.bend {
                RefineBendPreview(original: bend.original, moved: bend.moved, size: refine.templateSize, rect: refine.picture, lineWidth: refine.lineWidth)
            }
            if refine.layers.numbers || refine.group == .numbers || refine.tinyMarked != nil, let base = refine.base {
                RefineNumbers(base: base, rect: refine.picture, overPaint: painted != nil && !showsPhoto && refine.layers.paintOpacity >= 0.5)
                    .equatable()
            }
            if let held = refine.heldNumber, let template = refine.base?.template {
                RefineHeldNumber(template: template, paint: held.paint, at: held.at, rect: refine.picture)
            }
            if let tapped = refine.tapped {
                RefineTappedLine(points: tapped, rect: refine.picture, lineWidth: refine.lineWidth)
                    .opacity(refine.flashes ? 1 : 0)
            }
            RefineMarks(
                refinements: model.refinements, found: model.foundText, marking: refine.marking, rect: refine.picture,
                emphasizesText: refine.tool == .text)
            if let mark = refine.dropCell.map(RefineHoverMark.Mark.cell) ?? (refine.hold == nil && refine.trace == nil ? refine.hovering : nil) {
                RefineHoverMark(mark: mark, base: refine.base, rect: refine.picture)
            }
        }
        // Drawing past the picture's edge stays on the picture.
        .mask {
            Self.card
                .frame(width: refine.picture.width, height: refine.picture.height)
                .position(x: refine.picture.midX, y: refine.picture.midY)
        }
    }

    private static let card = RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)

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
                Button("Keep Refining", role: .cancel) {}
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
            Text(hint(for: .shape))
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

    /// How `tool` works, with the figure and the curve in hand (`RefineView.hint(for:shape:bending:)`).
    private func hint(for tool: RefineTool) -> String {
        Self.hint(for: tool, shape: refine.shape, bending: refine.curve != nil)
    }

    /// A tool, prominent while it's the finger's.
    @ViewBuilder
    private func toolButton(_ tool: RefineTool, systemImage: String, label: Text, id: String) -> some View {
        let selected = refine.tool == tool
        let button = Button { refine.toolTapped(tool) } label: {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(selected ? Color.white : Color.primary)
                .frame(width: 30, height: 30)
        }
        .buttonBorderShape(.circle)
        .accessibilityLabel(label)
        .accessibilityHint(Text(hint(for: tool)))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("refine-tool-\(id)")
        .accessibilityShowsLargeContentViewer { Label { label } icon: { Image(systemName: systemImage) } }
        if selected {
            button.buttonStyle(.glassProminent).tint(Theme.signature)
        } else {
            button.buttonStyle(.glass)
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
                        startChooser
                        if badge { tinyBadge }
                    }
                    VStack(spacing: 8) {
                        startChooser
                        if badge { tinyBadge }
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
        toolOptions
        if showsPalette, let template = refine.base?.template {
            if refine.tool == .select, let region = refine.selectedRegion {
                selectionBand(template: template, region: region)
            } else {
                RefinePaletteBar(template: template, current: $refine.currentPaint, picked: $refine.newColors, merge: paletteMerge)
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
                    studioButton(kind)
                        .disabled(!model.hasLineArtInput)
                }
            }
            .padding(.horizontal, 2)
        }
    }

    /// Every tool, in its group's labelled section, a name beside each (iPad); it scrolls where
    /// the screen is too short for all of them (an iPad on its side), its indicator flashing as it
    /// comes and its foot fading while there is more below: it ended at Looks, cut in half, with
    /// nothing to say Move Number, Writing and Try Painting were there (QA, November 7).
    private var toolRail: some View {
        ViewThatFits(in: .vertical) {
            railTools
            ScrollView { railTools }
                .scrollIndicatorsFlash(onAppear: true)
                .onScrollGeometryChange(for: Bool.self) { geometry in
                    geometry.contentOffset.y + geometry.containerSize.height < geometry.contentSize.height - 1
                } action: { _, more in
                    railHasMore = more
                }
                .mask {
                    VStack(spacing: 0) {
                        Color.black
                        LinearGradient(colors: [.black, .black.opacity(railHasMore ? 0 : 1)], startPoint: .top, endPoint: .bottom)
                            .frame(height: 56)
                    }
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: railHasMore)
                }
        }
        .frame(width: 184)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
        .padding(.leading, 12)
        .padding(.vertical, 12)
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .disabled(!model.hasLineArtInput)
    }

    private var railTools: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(RefineGroup.allCases, id: \.self) { kind in
                Self.groupName(kind)
                    .font(.caption.weight(.semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.quietInk)
                    .padding(.horizontal, 12)
                    .padding(.top, kind == RefineGroup.allCases.first ? 4 : 14)
                    .padding(.bottom, 2)
                    .accessibilityAddTraits(.isHeader)
                ForEach(kind.tools, id: \.self) { railRow($0) }
            }
        }
        .padding(8)
    }

    /// A tool in the rail: its symbol and name, filled in the signature color while it's the
    /// finger's.
    @ViewBuilder
    private func railRow(_ kind: RefineTool) -> some View {
        let selected = refine.tool == kind
        let row = Button { refine.toolTapped(kind) } label: {
            HStack(spacing: 10) {
                Image(systemName: symbol(kind))
                    .font(.body.weight(.semibold))
                    .frame(width: 24)
                Self.toolName(kind)
                    .font(.subheadline.weight(selected ? .semibold : .regular))
                    // A long name wraps at larger text rather than shrinking below the others.
                    .lineLimit(2)
                Spacer(minLength: 0)
            }
            .foregroundStyle(selected ? Color.white : Color.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background {
                if selected { Capsule().fill(Theme.signature) }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .contentShape(.hoverEffect, Capsule())
        .hoverEffect(.highlight)
        .accessibilityLabel(Self.toolName(kind))
        .accessibilityHint(Text(hint(for: kind)))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("refine-tool-\(Self.toolID(kind))")
        .accessibilityShowsLargeContentViewer { Label { Self.toolName(kind) } icon: { Image(systemName: symbol(kind)) } }
        switch kind {
        case .pen: row.gentleTip(.refineDraw, arrowEdge: .leading)
        case .fill: row.gentleTip(.refineFill, arrowEdge: .leading)
        case .shape: row.accessibilityValue(Self.shapeName(refine.shape))
        default: row
        }
    }

    /// A tool's round button (iPhone's row).
    @ViewBuilder
    private func studioButton(_ kind: RefineTool) -> some View {
        let button = toolButton(kind, systemImage: symbol(kind), label: Self.toolName(kind), id: Self.toolID(kind))
        switch kind {
        case .fill: button.gentleTip(.refineFill, arrowEdge: .bottom)
        case .shape: button.accessibilityValue(Self.shapeName(refine.shape))
        default: button
        }
    }

    private func symbol(_ kind: RefineTool) -> String { Self.symbol(kind, shape: refine.shape) }

    // MARK: Options

    /// What the picked tool offers above the tools: Shapes' figures, Snap where lines join, the
    /// Pen's Color from Photo, the looks, and the current paint's color.
    @ViewBuilder
    private var toolOptions: some View {
        switch refine.tool {
        case .pen:
            optionBar {
                snapToggle
                penColorsToggle
            } more: {
                Text("Smoothing")
                Slider(value: $penSmoothing, in: 0...1)
                    .frame(width: 140)
                    .accessibilityLabel(Text("Smoothing"))
                    .accessibilityValue(Text(penSmoothing.formatted(.percent.precision(.fractionLength(0)))))
                    .accessibilityHint(Text(String(
                        localized: "refine.smoothing.hint", defaultValue: "Evens out a wobbly line: the line trails your finger a little. Off draws exactly as you draw.",
                        comment: "Refine screen, the Pen's options: VoiceOver hint of Smoothing, a slider from off to full (Procreate calls it StreamLine)")))
                    .accessibilityIdentifier("refine-pen-smoothing")
            }
        case .shape:
            optionBar {
                HStack(spacing: 6) {
                    ForEach(RefineShape.allCases, id: \.self) { shapeOption($0) }
                }
            } more: {
                snapToggle
                penColorsToggle
            }
        case .cellEdge:
            optionBar { snapToggle }
        case .brush:
            optionBar { sizeSlider($brushSize, id: "refine-brush-size") }
        case .eraser, .smartEraser:
            optionBar { sizeSlider($eraserSize, id: "refine-eraser-size") }
        case .looks, .editPaint:
            if let base = refine.base {
                RefineColorsPanel(
                    template: base.template, paintsBefore: model.paintsBeforeEdits, edits: base.refinements.edits,
                    mode: refine.tool == .looks ? .looks : .paint, paint: currentIndexBinding, family: $refine.colorFamily,
                    change: refine.recolor)
                    .disabled(model.phase == .generating || !model.hasLineArtInput)
                    .transition(.opacity)
            }
        default:
            EmptyView()
        }
    }

    /// The tool's options in a capsule.
    private func optionBar<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        optionBar(content, more: { EmptyView() })
    }

    /// The tool's options in a capsule; `more` beside them where the width holds both, else under
    /// them, else a column. From the accessibility sizes on, each option has a line of its own
    /// and a slider's name stands over it: the rows ran into each other and out of their capsule.
    private func optionBar<Content: View, More: View>(
        @ViewBuilder _ content: () -> Content, @ViewBuilder more: () -> More
    ) -> some View {
        let content = content(), more = more()
        let column = VStack(alignment: .leading, spacing: 10) {
            content
            more
        }
        .frame(maxWidth: 320)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.vertical, 6)
        return Group {
            if typeSize.isAccessibilitySize {
                column
            } else {
                // The column also where long words (a translation) leave even two rows wider
                // than a phone: fixed, they laid the whole screen out wider than the window.
                // Each option at its own width in a row: two switches shared the row in halves,
                // Snap's word far from its switch and "Color from Photo" broken in two though the
                // row had room (QA, November 7).
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 16) {
                        Group { content }.fixedSize()
                        Group { more }.fixedSize()
                    }
                    .fixedSize()
                    VStack(spacing: 8) {
                        HStack(spacing: 16) { Group { content }.fixedSize() }
                        HStack(spacing: 10) { Group { more }.fixedSize() }
                    }
                    .fixedSize()
                    column
                }
            }
        }
        .font(.footnote)
        .toggleStyle(.switch)
        .tint(Theme.signature)
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        // Beside the picture, on the paper: boxed, the column was all boxes.
        .glassEffect(usesSide ? .identity : .regular, in: .rect(cornerRadius: 22))
        .disabled(!model.hasLineArtInput)
    }

    /// A brush's or an eraser's Size: its radius on screen, in points ([ and ] step it too).
    @ViewBuilder
    private func sizeSlider(_ size: Binding<Double>, id: String) -> some View {
        Text("Size")
        Slider(value: size, in: Self.sizes)
            .frame(width: 160)
            .accessibilityLabel(Text("Size"))
            .accessibilityValue(Text(String(
                localized: "refine.brush.size", defaultValue: "\(Int(size.wrappedValue.rounded())) points",
                comment: "Refine screen, the Paint Brush's and the Eraser's options: VoiceOver value of their Size slider, the radius on screen in points; the argument is the number")))
            .accessibilityIdentifier(id)
    }

    /// The Pen's and Shapes' Color from Photo: a figure's pieces take the photo's colors as a
    /// drawn line's do (`inked`), so the switch shows with both. A blank page has no photo to
    /// color from, so none there (the Mac's QA, November 9).
    @ViewBuilder
    private var penColorsToggle: some View {
        if !model.isScratch {
            penColorsSwitch
        }
    }

    private var penColorsSwitch: some View {
        Toggle(isOn: $penColors) { Text("Color from Photo") }
            .accessibilityHint(Text(String(
                localized: "refine.penColors.hint", defaultValue: "Gives the areas a line divides the photo’s colors there.",
                comment: "Refine screen, the Pen's options: VoiceOver hint of Color from Photo, which makes each part of an area a drawn line divides take the photo's color there")))
            .accessibilityIdentifier("refine-pen-colors")
    }

    private var snapToggle: some View {
        Toggle(isOn: $snaps) { Text("Snap") }
            .accessibilityHint(Text(String(
                localized: "refine.snap.hint", defaultValue: "Moves the end of a line onto a line it lands near.",
                comment: "Refine screen, a drawing tool's options: VoiceOver hint of Snap, which moves a drawn line's end onto a line it lands within a fingertip of")))
            .accessibilityIdentifier("refine-snap")
    }

    /// One of Shapes' figures: picks it.
    private func shapeOption(_ kind: RefineShape) -> some View {
        let selected = refine.shape == kind
        let button = Button {
            FeedbackEngine.shared.selectionChanged()
            refine.pickShape(kind)
        } label: {
            Label { Self.shapeName(kind) } icon: { Image(systemName: kind.systemImage) }
                .labelStyle(.iconOnly)
                .font(.body.weight(.semibold))
                .foregroundStyle(selected ? Color.white : Color.primary)
                .frame(width: 26, height: 26)
        }
        .buttonBorderShape(.circle)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("refine-shape-\(kind)")
        return Group {
            if selected {
                button.buttonStyle(.glassProminent).tint(Theme.signature)
            } else {
                button.buttonStyle(.glass)
            }
        }
    }

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

    // MARK: The Pencil's palette

    /// The tools, a row per group, and the palette in Cells and Paint: beside the Pencil when its
    /// double tap or squeeze asks for them.
    private var pencilPaletteView: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(RefineGroup.allCases, id: \.self) { kind in
                HStack(spacing: 8) {
                    Self.groupName(kind)
                        .font(.caption.weight(.semibold))
                        .textCase(.uppercase)
                        .foregroundStyle(.secondary)
                        .frame(width: 72, alignment: .leading)
                        .accessibilityAddTraits(.isHeader)
                    GlassEffectContainer(spacing: 8) {
                        HStack(spacing: 6) {
                            ForEach(kind.tools, id: \.self) { studioButton($0) }
                        }
                    }
                }
            }
            if refine.group == .cells || refine.group == .paint, let template = refine.base?.template {
                RefinePaletteBar(template: template, current: $refine.currentPaint, picked: $refine.newColors, merge: paletteMerge)
            }
        }
        .padding(16)
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .presentationCompactAdaptation(.popover)
        .accessibilityIdentifier("refine-pencil-palette")
    }

    // MARK: Cells and paint

    /// What a swatch dropped on another does: in Edit Paint, `mergePaints`; elsewhere nothing.
    private var paletteMerge: ((Int, Int) -> Void)? {
        guard refine.tool == .editPaint else { return nil }
        return { from, into in refine.mergePaints(from, into: into) }
    }

    private var currentIndexBinding: Binding<Int?> {
        Binding(
            get: { refine.currentIndex },
            set: { index in
                guard let index, let palette = refine.base?.template.palette, index < palette.count else { return }
                refine.currentPaint = palette[index].oklab
            })
    }

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
                RefinePaletteBar(template: template, current: $refine.currentPaint, picked: $refine.newColors, merge: paletteMerge, glass: false)
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
                startChooser
                tinyBadge
            }
            VStack(alignment: .trailing, spacing: 8) {
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    startChooser
                }
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    tinyBadge
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

    /// Where the template starts from, asked until the first edit: what the generator made (the
    /// default), or the photo as one area (Blank), which the painter's lines and paint then make
    /// into the picture. Out of the way while a note shows at the top.
    @ViewBuilder
    private var startChooser: some View {
        // A page from scratch has nothing to generate: Blank is all it is.
        if refine.showsStartFrom {
            Picker("Start From", selection: Binding(get: { model.refinements.start }, set: { model.start(from: $0) })) {
                Text("Generated").tag(TemplateRefinements.Start.generated)
                Text("Blank").tag(TemplateRefinements.Start.blank)
            }
            .pickerStyle(.segmented)
            .fixedSize()
            .padding(6)
            .glassEffect(.regular, in: .capsule)
            .background(Theme.surface, in: .capsule)
            .disabled(model.phase == .generating)
            .accessibilityIdentifier("refine-start")
            .transition(.opacity)
        }
    }

    /// How many numbers are near the smallest: a tap brings the next of them up close. Out of the
    /// way while a note or the draft's save toast holds the top, which it covered.
    @ViewBuilder
    private var tinyBadge: some View {
        if !refine.tiny.isEmpty, model.note == nil, library?.drafts.saveFailed != model.photoID, let template = refine.base?.template {
            Button {
                refine.tinyShown = (refine.tinyShown + 1) % refine.tiny.count
                let label = refine.tiny[refine.tinyShown].label
                refine.tinyMarked = refine.tiny[refine.tinyShown].region
                refine.focus = RefineFocus(
                    id: (refine.focus?.id ?? 0) + 1, rect: RefineTinyAreas.focus(on: label, in: template), animated: !reduceMotion)
                FeedbackEngine.shared.selectionChanged()
            } label: {
                Label { Text(Self.tinyText(refine.tiny.count)) } icon: { Image(systemName: "magnifyingglass") }
                    .font(.footnote.weight(.semibold))
            }
            .buttonStyle(.glass)
            // The glass alone took the paint's light behind it, which washed out the gold label
            // at night (QA, November 7): on the card's surface it reads over any paint.
            .background(Theme.surface, in: .capsule)
            .accessibilityShowsLargeContentViewer()
            .accessibilityHint(Text(String(
                localized: "refine.tiny.hint", defaultValue: "Shows the next one up close.",
                comment: "Refine screen: VoiceOver hint of the badge that counts the areas whose numbers are near the smallest size; a tap zooms in on the next one")))
            .accessibilityIdentifier("refine-tiny")
            .transition(.opacity)
        }
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
