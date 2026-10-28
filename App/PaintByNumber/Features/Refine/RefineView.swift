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

    /// A one-finger drag does something with the tool (`RefineView.draw`); the others only tap.
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
/// - the Pen draws a line as drawn (smoothed as it showed); only an end whose ink touches a
///   line's moves onto it, by no more than the ink's width, so the cell closes as it looks
///   (`PenAssist`); the sides of the areas it cuts that the photo tells apart take their own
///   paints;
/// - Shapes draws a straight line, a rectangle, an oval or a curve across a drag
///   (`RefineShape`, `ShapePath`), shown as it will be while the finger is down; a line's or a
///   curve's ends move onto a line their ink touches, as the Pen's do;
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

    @Environment(\.dismiss) private var dismiss
    /// For the draft's save toast, which the tiny-numbers badge makes way for.
    @Environment(Library.self) private var library: Library?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @Environment(\.accessibilitySwitchControlEnabled) private var switchControlEnabled
    @AppStorage(SettingsKey.lineWeight) private var lineWeight = LineWeight.default
    @State private var tool: RefineTool
    /// The tool picked before this one, for the Pencil's Switch to Previous Tool.
    @State private var previousTool: RefineTool?
    @State private var shape = RefineShape.line
    /// What shows: the numbers, the ink, the paint and the photo (`RefineLayers`).
    @State private var layers = RefineLayers.painting
    /// The Layers panel is open.
    @State private var showsLayers = false
    /// The template on screen painted, for the paint layer, with its preview's id.
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
    /// The line of text being dragged out: where the drag began and where it is.
    @State private var marking: (SIMD2<Float>, SIMD2<Float>)?
    /// The line the eraser was last tapped on, which flashes as it goes.
    @State private var tapped: [SIMD2<Float>]?
    @State private var flashes = false
    /// Where the picture is in the canvas, and its zoom (the touch surface's).
    @State private var picture: CGRect = .zero
    @State private var zoom: CGFloat = 1
    @State private var canvasSize: CGSize = .zero
    /// The tallest the tools along the bottom have been, the least room they keep: picking a tool
    /// with a shorter bar no longer grows the canvas, nor a taller one (once seen) shrinks it, so
    /// the picture neither moves under the finger nor loses its zoom (the exploratory QA of
    /// October 21 tapped where it had been).
    @State private var toolsHeight: CGFloat = 0
    /// The tools' own height now, which another width starts the room from.
    @State private var toolsMeasured: CGFloat = 0
    /// Edit Paint's family follows the current paint while it is on.
    @State private var colorFamily = true
    /// A part of the picture the touch surface is to bring up close.
    @State private var focus: RefineFocus?
    #if DEBUG
    /// The demo's paint, cell or card is picked once its edits have landed.
    @State private var didPickDemoPaint = false
    /// Where the demo's card points (canvas units): the band Select's cell brings moves the
    /// picture after the card opened, so the card points again where the picture lands.
    @State private var demoCardAt: SIMD2<Float>?
    #endif
    /// The screen has begun refining (`CreateModel.beginRefining`), once.
    @State private var opened = false
    /// The Eyedropper's hold under the finger: where it is and the color it would pick.
    @State private var hold: RefineHold?
    /// What the Pencil's hover shows for the tool in hand (`hoverMark(at:)`), and the cell a
    /// swatch's drag is over: kept only as they change, so a hover's every move doesn't lay the
    /// screen out again.
    @State private var hovering: RefineHoverMark.Mark?
    @State private var dropCell: Int?
    /// The tools, bars and palette are hidden (a four-finger tap), the picture alone on screen.
    @State private var fullScreen = false
    /// Counts the full screen's comings and goings, after which the canvas takes the keys again.
    @State private var keysRequest = 0
    /// Where the Pencil asked for the tools and the palette (its double tap or squeeze), in the
    /// canvas's coordinates.
    @State private var pencilPalette: CGRect?
    /// Cancel asks first when there are changes to lose.
    @State private var confirmsCancel = false
    @Environment(\.horizontalSizeClass) private var sizeClass
    /// Whether a line's ends join the lines their ink touches (`PenAssist`): the Toolbox's Snap.
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
    /// The current paint (OKLab, as on screen): the Bucket gives it, the palette, the Eyedropper
    /// and Edit Paint pick it. A color no paint has yet becomes one with the first Bucket tap.
    @State private var currentPaint: SIMD3<Float>?
    /// The last repaint of the current paint sent, until a template has it (`RefinePalette.landing`):
    /// its paint is then the current one. Made current as the repaint was sent, before any
    /// template had it, the paint was none for a moment and the picker's next picks went nowhere
    /// (QA, October 26).
    @State private var repainted: RefinePalette.Repainted?
    /// The cell Select picked, by a point in it (canvas units), so it follows its region through
    /// edits.
    @State private var selection: SIMD2<Float>?
    /// The undrawn edges of the template on screen, made once per template (`RefineCellEdges`).
    @State private var cellEdges: (id: UUID, path: Path)?
    /// Try Painting's painting, while it is open.
    @State private var trial: RefineTrial?
    /// The Studio's group on screen (`RefineGroup`), and the tool last picked in each.
    @State private var group = RefineGroup.ink
    @State private var lastTool: [RefineGroup: RefineTool] = [:]
    /// The area whose card Select's Change Color opened (`RefineAreaCard`): beside the area on
    /// iPad, in Select's bar on iPhone (`barCard`), where nothing covers the picture.
    @State private var card: RefineAreaPick?
    @State private var barCard: RefineAreaPick?
    /// The sparkles where a line closed off an area last: the line's number, where its ends met
    /// on screen, and the shape's smaller side on screen.
    @State private var sparkles: (id: Int, point: CGPoint, extent: CGFloat)?
    /// What a Merge drag joins, lit while the finger is down: the probe of the template on screen
    /// (with its preview's id), the areas found for the drag so far, and the drag waiting for
    /// the probe while it works on an earlier one.
    @State private var mergeProbe: (preview: UUID, probe: TemplateEditor.MergeProbe)?
    @State private var mergeAreas: [Int] = []
    @State private var mergeWanted: [SIMD2<Float>]?
    @State private var mergeProbing = false
    /// The Merge drag the lit areas are for: one found for an earlier drag never lights this one.
    @State private var mergeStroke = 0
    /// The areas whose numbers are near the smallest (`RefineTinyAreas`), and the one shown last.
    @State private var tiny: [(region: Int, label: PaintCore.Label)] = []
    @State private var tinyShown = -1
    /// A Tool Guide page's practice canvas (`RefineGuideView`): the tool it teaches over the
    /// practice picture, with Undo, Redo, Layers and Reset above it in place of the screen's
    /// bars, and none of the other tools.
    private let practice: RefinePracticeSetup?
    /// Reset on a practice canvas: the page makes the canvas again, from the picture.
    private let onReset: (() -> Void)?
    /// The Tool Guide, open at a page.
    @State private var guide: RefineGuideTopic?

    init(model: CreateModel) {
        self.init(model: model, practice: nil)
    }

    /// Refine, or with `practice` a Tool Guide page's practice canvas on `model`'s practice picture
    /// (`CreateModel.practice(_:scene:)`).
    init(model: CreateModel, practice: RefinePracticeSetup?, onReset: (() -> Void)? = nil) {
        self.model = model
        self.practice = practice
        self.onReset = onReset
        // Never a draft: its canvas is smaller than the one the edits will be laid on.
        _base = State(initialValue: model.preview.flatMap { $0.isDraft ? nil : $0 })
        _tool = State(initialValue: .pen)
        // The Studio opens on the painting in its paints (the Lamplit Table, 6 to 0).
        if let practice {
            // A practice's switches are its own, from the painter's: the Pen's page turning Color
            // from Photo on leaves Refine's Pen as it was.
            let store = RefinePracticeSetup.settings
            _snaps = AppStorage(wrappedValue: SettingsDefault.refineSnaps, SettingsKey.refineSnaps, store: store)
            _penColors = AppStorage(wrappedValue: SettingsDefault.refinePenColors, SettingsKey.refinePenColors, store: store)
            _brushSize = AppStorage(wrappedValue: SettingsDefault.refineBrushSize, SettingsKey.refineBrushSize, store: store)
            _eraserSize = AppStorage(wrappedValue: SettingsDefault.refineEraserSize, SettingsKey.refineEraserSize, store: store)
            _penSmoothing = AppStorage(
                wrappedValue: SettingsDefault.refinePenSmoothing, SettingsKey.refinePenSmoothing, store: store)
            _tool = State(initialValue: practice.tool)
            _group = State(initialValue: RefineGroup.of(practice.tool))
            _layers = State(initialValue: practice.layers)
            if let shape = practice.shape { _shape = State(initialValue: shape) }
            return
        }
        #if DEBUG
        if let demo = ShellDemo.current {
            let opens: RefineTool? =
                demo.picksColorPaint ? .editPaint : demo.opensColors ? .looks : demo.selectsCell || demo.opensCard ? .select : nil
            if let opens {
                _tool = State(initialValue: opens)
                _group = State(initialValue: RefineGroup.of(opens))
            }
            if let topic = demo.opensGuide { _guide = State(initialValue: topic) }
        }
        #endif
    }

    var body: some View {
        stage
        .onAppear {
            if !isPractice { PaintTips.desk.enter(.refine) }
            // Once: Try Painting's cover makes it disappear and appear again, and the history and
            // what Cancel puts back are the screen's, not the cover's.
            guard !opened else { return }
            opened = true
            model.beginRefining()
            // A draft refined before (Continue Refining) has found how to draw already.
            if model.refinements.isEmpty, !isPractice { PaintTips.refineShown() }
        }
        .onDisappear {
            model.dismissNote()
            if !isPractice { PaintTips.desk.leave(.refine) }
        }
        .onChange(of: model.closedShape) { _, shape in
            if let shape { closed(shape) }
        }
        #if DEBUG
        .onChange(of: picture) {
            guard let at = demoCardAt, card != nil, let template = base?.template else { return }
            card = RefineAreaPick(at: at, screen: onScreen(picturePoint(at)), template: template)
        }
        #endif
        .fullScreenCover(item: $trial) { trial in
            PaintView(session: trial.session, title: String(localized: "Try Painting"), onClose: { self.trial = nil })
        }
        .task(id: Landing(preview: model.preview?.id, settled: model.settledEdits, showsPainting: showsPainting)) {
            await land()
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
            canvas
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if !fullScreen { reservedTools }
                }
                .safeAreaInset(edge: .leading, alignment: .top, spacing: 0) {
                    if usesRail, !fullScreen { toolRail }
                }
                .background(Theme.paper)
                .navigationTitle("Refine")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbar }
                .toolbarVisibility(fullScreen ? .hidden : .visible, for: .navigationBar)
                .statusBarHidden(fullScreen)
                .persistentSystemOverlays(fullScreen ? .hidden : .automatic)
        }
        .fullScreenCover(item: $guide) { topic in RefineGuideView(opening: topic) }
    }

    /// An edit sent to the model, which draws it until the template on screen has it.
    private struct Submitted: Identifiable {
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
                // The photo shows through what lies over it; under opaque paint the lines are drawn
                // as over the paint.
                let showsPhoto = base == nil || layers.photoStrength > 0
                let painted = showsPainting && base != nil && painting?.preview == base?.id ? painting?.image : nil
                ZStack {
                    // The paper, beneath every layer: it shows where the paint and the photo are
                    // hidden or faint.
                    Rectangle()
                        .fill(LineArtDrawing.paper)
                        .frame(width: picture.width, height: picture.height)
                        .position(x: picture.midX, y: picture.midY)
                    if layers.photo || base == nil {
                        Image(decorative: photo, scale: 1)
                            .resizable()
                            .interpolation(.high)
                            .frame(width: picture.width, height: picture.height)
                            .position(x: picture.midX, y: picture.midY)
                            .opacity(base == nil ? 1 : layers.photoOpacity)
                    }
                    if let painted {
                        Image(decorative: painted, scale: 1)
                            .resizable()
                            .interpolation(.high)
                            .frame(width: picture.width, height: picture.height)
                            .position(x: picture.midX, y: picture.midY)
                            .opacity(layers.paintOpacity)
                            // New colors cross-fade in (`land`).
                            .id(painting?.preview)
                            .transition(.opacity)
                    }
                    // The brush's strokes until they land, in their paint under the drawing's ink,
                    // which a brush never covers.
                    RefineInkLayer(
                        lines: [], trace: nil, traceIsDrawn: false, erasing: false, brushes: brushes,
                        eraserRadius: eraserRadius, rect: picture, lineWidth: lineWidth, beneath: nil, halo: false)
                    if let base, layers.ink {
                        LineArtLayer(
                            drawing: base.drawing, picture: picture, scale: zoom, overPhoto: showsPhoto,
                            overPaint: painted != nil && !showsPhoto)
                            .equatable()
                    }
                    RefineFillLayer(
                        base: base, fills: filledPoints, swatches: swatches, space: model.source?.image.colorSpace, rect: picture,
                        showsAreas: painted == nil)
                        .equatable()
                    if group == .cells, let cellEdges {
                        RefineCellEdges(id: cellEdges.id, size: templateSize, path: cellEdges.path, rect: picture)
                            .equatable()
                    }
                    if !glowAreas.isEmpty {
                        RefinePaintGlow(base: base, areas: glowAreas, rect: picture, reduceMotion: reduceMotion)
                            .equatable()
                    }
                    let figure = shapeTrace
                    RefineInkLayer(
                        lines: layers.ink ? pending : [], trace: tool == .shape ? figure : tool.drags || tool == .brush ? nil : penTrace,
                        traceIsDrawn: tool == .shape, erasing: tool.erases, dashed: tool == .cellEdge, merging: tool == .merge,
                        eraserRadius: eraserRadius, rect: picture, lineWidth: lineWidth,
                        beneath: showsPhoto ? photo : painted, halo: showsPhoto)
                    if let bend {
                        RefineBendPreview(original: bend.original, moved: bend.moved, size: templateSize, rect: picture, lineWidth: lineWidth)
                    }
                    if layers.numbers || group == .numbers, let base {
                        RefineNumbers(base: base, rect: picture)
                            .equatable()
                    }
                    if let held = heldNumber, let template = base?.template {
                        RefineHeldNumber(template: template, paint: held.paint, at: held.at, rect: picture)
                    }
                    if let tapped {
                        RefineTappedLine(points: tapped, rect: picture, lineWidth: lineWidth)
                            .opacity(flashes ? 1 : 0)
                    }
                    RefineMarks(
                        refinements: model.refinements, found: model.foundText, marking: marking, rect: picture,
                        emphasizesText: tool == .text)
                    if let mark = dropCell.map(RefineHoverMark.Mark.cell) ?? (hold == nil && trace == nil ? hovering : nil) {
                        RefineHoverMark(mark: mark, base: base, rect: picture)
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
                onDraw: draw, onTap: tap, onUndo: undo, onRedo: redo, onRepeat: repeatStep, holdPicks: !tool.drags,
                strokes: tool.strokes,
                onPencil: pencil, onHold: held, onHover: hovered, onDrop: dropped, onDropHover: dropHovered,
                onFullScreen: { if !isPractice { toggleFullScreen() } }, keys: keys, onKey: pressed, keysRequest: keysRequest,
                focus: focus)
            if let hold, let space = base?.template.colorSpace {
                RefineLoupe(
                    picked: hold.color.map { RefinePalette.color($0, space: space) },
                    current: currentPaint.map { RefinePalette.color($0, space: space) })
                    .position(RefineLoupe.position(over: onScreen(hold.at), in: canvasSize))
            }
            if let sparkles {
                RefineSparkles(point: sparkles.point, extent: sparkles.extent, stars: Sky.current() == .moon)
                    .id(sparkles.id)
            }
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
        .accessibilityActions {
            if model.canRedo { Button("Redo", action: redo) }
            if !isPractice {
                Button(action: toggleFullScreen) { fullScreen ? Text("Exit Full Screen") : Text("Full Screen") }
            }
        }
        .accessibilityIdentifier("refine-canvas")
        // After the picture's own accessibility, which ignores its children: the cells, Start From
        // and the badge are elements of their own, the cells beneath the rest.
        .overlay { cellElements }
        .overlay(alignment: .top) {
            if !isPractice, !fullScreen { topControls.padding(12) }
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
            if fullScreen { exitFullScreen.padding(12) }
        }
        .popover(item: $card, attachmentAnchor: .rect(.rect(card?.anchor ?? .zero))) { pick in
            // A sheet where a popover can't be (a wide iPhone in landscape uses the rail).
            areaCard(pick)
                .presentationDetents([.medium, .large])
                .presentationCompactAdaptation(.sheet)
        }
        // Its own view, so the card's popover and this one don't share an anchor.
        .background {
            Color.clear
                .popover(
                    isPresented: Binding(get: { pencilPalette != nil }, set: { if !$0 { pencilPalette = nil } }),
                    attachmentAnchor: .rect(.rect(pencilPalette ?? .zero))
                ) { pencilPaletteView }
        }
    }

    private static let card = RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)

    /// The cells in view as VoiceOver and Switch Control elements, while a cell tool is picked
    /// (`RefineCellElements`; demo launches have them too, for the UI tests).
    @ViewBuilder
    private var cellElements: some View {
        if speaksCells, RefineCellElements.tools.contains(tool), model.hasLineArtInput, let template = base?.template {
            let anchors = RefineCells.anchors(in: template)
            RefineCellElements(
                template: template, anchors: anchors, picture: picture, canvas: canvasSize, tool: tool,
                selected: tool == .select ? selectedRegion : nil,
                activate: { region in tap(at: picturePoint(anchors[region])) },
                merge: { region, neighbour in
                    guard let probe = try? TemplateEditor.MergeProbe(template),
                          let edit = RefineCells.merge(region, with: neighbour, in: template, probe: probe)
                    else { return model.tell(.notMerged) }
                    submit(edit)
                },
                moveNumber: { region, direction in
                    guard let edit = RefineCells.moveNumber(of: region, direction, in: template) else { return model.tell(.notMoved) }
                    submit(edit)
                })
        }
    }

    private var speaksCells: Bool {
        #if DEBUG
        if DemoMode.isActive { return true }
        #endif
        return voiceOverEnabled || switchControlEnabled
    }

    /// Whether the painting shows beneath the drawing: its layer is on.
    private var showsPainting: Bool { layers.paint }

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

    private var aspectRatio: CGFloat {
        guard let image = model.source?.image, image.width > 0, image.height > 0 else { return 1 }
        return CGFloat(image.width) / CGFloat(image.height)
    }

    /// The drawing's line on screen, as the preview and the canvas draw it at this size.
    private var lineWidth: CGFloat {
        (base?.drawing ?? model.preview?.drawing)?.lineWidth(scale: zoom, weight: lineWeight) ?? 1.5
    }

    /// The eraser keeps its Size on screen, so zoomed in it erases finer (`RefineScreen.eraserRadius(size:)`).
    private var eraserRadius: Float { screen.eraserRadius(size: CGFloat(eraserSize)) }

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
        if touch == .began { revealLayer() }
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
    private func follow(_ touch: RefineTouch, at point: SIMD2<Float>) {
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
    private func submit(
        _ edit: TemplateEditor.Edit, chain: [SIMD2<Float>]? = nil, bent: (original: [SIMD2<Float>], moved: [SIMD2<Float>])? = nil
    ) {
        let edit = inked(edit)
        submitted.append(Submitted(id: model.edit(edit), edit: edit, chain: chain, bent: bent))
        if !isPractice {
            PaintTips.refineEdited()
            if case .draw = edit { PaintTips.refineLineDrawn() }
        }
    }

    private func endStroke() {
        trace = nil
        snapLines = nil
        mergeAreas = []
        mergeWanted = nil
    }

    /// Whether a line's ends join the lines their ink touches: the Toolbox's Snap.
    private var snapsOn: Bool { snaps }

    /// A drawn line as the Studio lays it: ink alone (a draw with no paints to give, which lays
    /// nudged through junctions as any line now does) unless Color from Photo is on, when the
    /// model reads the photo's colors for the pieces it cuts (`TemplateEditor.painted`).
    private func inked(_ edit: TemplateEditor.Edit) -> TemplateEditor.Edit {
        Self.inked(edit, colorsFromPhoto: penColors)
    }

    /// `edit`, a drawn line with no paints to give unless `colorsFromPhoto`.
    nonisolated static func inked(_ edit: TemplateEditor.Edit, colorsFromPhoto: Bool) -> TemplateEditor.Edit {
        guard !colorsFromPhoto, case .draw(let points, let closed, nil) = edit else { return edit }
        return .draw(points: points, closed: closed, paints: [])
    }

    /// A pen's line from its samples (`RefineGestures.pen`), steadied by its Smoothing.
    private func penEdit(_ points: [SIMD2<Float>]) -> TemplateEditor.Edit? {
        RefineGestures.pen(points, on: screen, snapping: snapLines, smoothing: tool == .pen ? CGFloat(penSmoothing) : 0)
    }

    /// The stroke under the finger as it shows: the Pen's steadied by its Smoothing, as it will be
    /// laid (`RefineGestures.steadied`); the others as drawn.
    private var penTrace: [SIMD2<Float>]? {
        guard let trace, tool == .pen, penSmoothing > 0 else { return trace }
        return RefineGestures.steadied(trace, smoothing: CGFloat(penSmoothing), on: screen)
    }

    /// The eraser's pass as an edit, at its Size (`RefineGestures.eraser`).
    private func eraserEdit(_ points: [SIMD2<Float>]) -> TemplateEditor.Edit? {
        RefineGestures.eraser(points, on: screen, size: CGFloat(eraserSize))
    }

    /// Bend Line, Move Edge and Move Number follow the drag from where it began to the finger
    /// (`trace`, the two points), the line or number shown moving, and lay it when it lifts.
    private func drag(_ touch: RefineTouch, at point: SIMD2<Float>) {
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

    /// How near a drag must begin to a line or a number to take it: a finger's reach on screen, in
    /// canvas units (`RefineGestures.fingerReach`, as the edits it sends).
    private var fingerReach: Float {
        picture.width > 0 ? Float(RefineGestures.fingerReach * templateSize.width / picture.width) : TemplateEditor.tapReach
    }

    /// Canvas points normalized to the picture.
    private func normalized(_ points: [SIMD2<Float>]) -> [SIMD2<Float>] {
        let size = SIMD2(Float(max(templateSize.width, 1)), Float(max(templateSize.height, 1)))
        return points.map { $0 / size }
    }

    /// The line Bend Line (ink) or Move Edge (a cell's edge) holds, as it was and moved to the
    /// finger (canvas units), the same moved points the edit will lay (`TemplateEditor.reshapedChain`).
    private var bend: (original: [SIMD2<Float>], moved: [SIMD2<Float>])? {
        guard tool == .bendLine || tool == .moveEdge, let trace, trace.count == 2, let template = base?.template,
              picture.width > 0, screen.onScreenLength(trace[1] - trace[0]) >= 1
        else { return nil }
        return TemplateEditor.reshapedChain(
            on: template, from: canvasPoint(trace[0]), to: canvasPoint(trace[1]), reach: fingerReach,
            target: tool == .bendLine ? .ink : .edge)
    }

    /// The number Move Number holds (its paint's index), the one the edit will move
    /// (`TemplateEditor.labelNear`), and where the finger has it, normalized.
    private var heldNumber: (paint: Int, at: SIMD2<Float>)? {
        guard tool == .moveNumber, let trace, trace.count == 2, let template = base?.template,
              let held = TemplateEditor.labelNear(on: template, at: canvasPoint(trace[0]), reach: fingerReach)
        else { return nil }
        return (Int(template.regions[held.region].colorIndex), trace[1])
    }

    /// The Paint Brush's stroke as an edit, in the current paint at the brush's Size
    /// (`RefineGestures.brush`).
    private func brushEdit(_ points: [SIMD2<Float>]) -> TemplateEditor.Edit? {
        guard let color = currentPaint else { return nil }
        return RefineGestures.brush(points, on: screen, color: color, size: CGFloat(brushSize))
    }

    /// The brush's strokes sent that the template on screen doesn't show yet, and the one under
    /// the finger, as `RefineInkLayer` lays them.
    private var brushes: [RefineInkLayer.Brush] {
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

    // MARK: Shapes

    /// Shapes follows the drag: the shape spans from where it began to the finger, and is laid on
    /// the template when it lifts. A curve takes two drags: its ends, then its bend.
    private func drawShape(_ touch: RefineTouch, at point: SIMD2<Float>) {
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
    /// The lines a stroke's ends may join: the drawing's, but its writing, which the editor never
    /// joins a line to (an end snapped onto a letter would hang there and close nothing).
    private func currentSnapLines() -> SnapLines? {
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
    private func land() async {
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
            withAnimation(fades ? .easeInOut(duration: 0.35) : nil) {
                base = preview
                // Only a painting of this template: an older one would show lines that are gone.
                painting = image?.preview == preview.id ? image : nil
            }
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
        revealLayer()
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
        if !isPractice {
            PaintTips.refineEdited()
            PaintTips.refineFilled()
        }
    }

    /// A marked line is unmarked; a found line is turned off, or on again.
    private func toggleText(at point: SIMD2<Float>) {
        if let marked = model.refinements.addedText.last(where: { Self.line($0, contains: point) }) {
            model.change(.unmarkText(marked))
            if !isPractice { PaintTips.refineEdited() }
        } else if let line = model.foundText.first(where: { Self.line($0, contains: point) }) {
            model.change(.toggleFound(line))
            if !isPractice { PaintTips.refineEdited() }
        }
    }

    /// Marks the line dragged out from `a` to `b`, unless the drag was too small to hold one.
    private func mark(from a: SIMD2<Float>, to b: SIMD2<Float>) {
        guard abs(a.x - b.x) * Float(picture.width) >= 12, abs(a.y - b.y) * Float(picture.height) >= 6 else { return }
        model.change(.markText(TemplateRefinements.textLine(from: a, to: b)))
        if !isPractice { PaintTips.refineEdited() }
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

    private func redo() {
        model.redo()
    }

    /// Cancel: at once with nothing to lose, else once the painter says to discard the changes
    /// (an edit still on its way counts: it isn't in the history yet).
    private func askToCancel() {
        if model.canUndo || !submitted.isEmpty { confirmsCancel = true } else { cancel() }
    }

    /// A step of held fingers' undo or redo, once the last has landed and shows (a step that makes
    /// the template again, a text correction's, shows only once it's made); false when there's
    /// none left to take.
    private func repeatStep(redo: Bool) -> Bool {
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
            Button("Cancel", systemImage: "xmark", action: askToCancel)
                .keyboardShortcut(isCovered || fullScreen ? nil : .cancelAction)
                .accessibilityIdentifier("refine-cancel")
                .confirmationDialog(Text("Discard Your Changes?"), isPresented: $confirmsCancel, titleVisibility: .visible) {
                    Button("Discard Changes", role: .destructive, action: cancel)
                    Button("Keep Refining", role: .cancel) {}
                }
        }
        ToolbarItem(placement: .topBarLeading) {
            Button("Tool Guide", systemImage: "questionmark.circle") {
                FeedbackEngine.shared.selectionChanged()
                guide = RefineGuideTopic.opening(at: tool)
            }
            .accessibilityHint(Text(String(
                localized: "refine.guide.open.hint", defaultValue: "What each tool does, with a picture to try it on.",
                comment: "Refine screen: VoiceOver hint of the Tool Guide button, which opens a page per tool with a description and a practice canvas")))
            .accessibilityIdentifier("refine-guide")
        }
        ToolbarItemGroup(placement: .primaryAction) {
            // ⌘Z and ⇧⌘Z are the canvas's (`keys`), the full screen's too, where this bar hides.
            Button("Undo", systemImage: "arrow.uturn.backward", action: undo)
                .disabled(!model.canUndo)
                .accessibilityIdentifier("refine-undo")
            Button("Redo", systemImage: "arrow.uturn.forward", action: redo)
                .disabled(!model.canRedo)
                .accessibilityIdentifier("refine-redo")
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
        ToolbarItem(placement: .confirmationAction) {
            Button("Done", systemImage: "checkmark", action: done)
                .tint(Theme.signature)
                .keyboardShortcut(isCovered ? nil : .defaultAction)
                .accessibilityIdentifier("refine-done")
        }
    }

    /// The tools, keeping the room of the tallest they have been (`toolsHeight`).
    private var reservedTools: some View {
        tools
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                toolsMeasured = height
                if height > toolsHeight { toolsHeight = height }
            }
            .frame(minHeight: toolsHeight, alignment: .bottom)
            // Another width (a rotation, a resized window) lays the tools out anew: measured again.
            // The tools as they are now count, though their height doesn't change with the width
            // (the picture jumped at the first change of group, QA, October 28).
            .onChange(of: canvasSize.width) { toolsHeight = toolsMeasured }
    }

    /// What the finger does, along the bottom (`studioBar`): the picked tool's options and, on
    /// iPhone, the groups and the group's tools. How each tool works is its button's VoiceOver
    /// hint, and how to draw at all a tip said once (`RefineDrawTip`); only a curve waiting to be
    /// bent says what comes next.
    private var tools: some View {
        VStack(spacing: 12) {
            if tool == .shape, shape == .curve, curve != nil {
                Text(hint(for: .shape))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 480)
                    .accessibilityIdentifier("refine-hint")
            }
            studioBar
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

    /// How `tool` works: its button's VoiceOver hint (a curve waiting to be bent also shows it).
    private func hint(for tool: RefineTool) -> String {
        switch tool {
        case .pen:
            String(localized: "refine.hint.pen",
                   defaultValue: "Draw lines just where you draw them. Two fingers zoom and move, and a two‑finger tap undoes.",
                   comment: "Refine screen: how the Pen works (it draws lines into the painting's drawing just where they are drawn), read by VoiceOver as the hint of its button")
        case .shape:
            switch shape {
            case .line:
                String(localized: "refine.hint.line",
                       defaultValue: "Drag to draw a straight line. Two fingers zoom and move.",
                       comment: "Refine screen: how the Shapes tool's Line works (a drag draws a straight line from where it starts to where it ends), read by VoiceOver as the hint of its button")
            case .rectangle:
                String(localized: "refine.hint.rectangle",
                       defaultValue: "Drag from corner to corner to draw a rectangle. Two fingers zoom and move.",
                       comment: "Refine screen: how the Shapes tool's Rectangle works (a drag spans the rectangle from one corner to the opposite one), read by VoiceOver as the hint of its button")
            case .oval:
                String(localized: "refine.hint.oval",
                       defaultValue: "Drag across to draw an oval. Two fingers zoom and move.",
                       comment: "Refine screen: how the Shapes tool's Oval works (a drag spans the box the oval fills), read by VoiceOver as the hint of its button")
            case .curve:
                curve == nil
                    ? String(localized: "refine.hint.curve",
                             defaultValue: "Drag from one end of the curve to the other, then drag to bend it. Two fingers zoom and move.",
                             comment: "Refine screen: how the Shapes tool's Curve works (a first drag places the curve's ends, a second bends it through the finger), read by VoiceOver as the hint of its button")
                    : String(localized: "refine.hint.curve.bend",
                             defaultValue: "Drag to bend the curve, or tap to keep it straight.",
                             comment: "Refine screen: the Shapes tool's Curve once its ends are placed: a drag bends it through the finger, a tap keeps it a straight line")
            case .polygon:
                String(localized: "refine.hint.polygon",
                       defaultValue: "Drag across to draw a hexagon. Two fingers zoom and move.",
                       comment: "Refine screen: how the Shapes tool's Hexagon works (a drag spans the box the hexagon fills), read by VoiceOver as the hint of its button")
            case .star:
                String(localized: "refine.hint.star",
                       defaultValue: "Drag across to draw a star. Two fingers zoom and move.",
                       comment: "Refine screen: how the Shapes tool's Star works (a drag spans the box the five-pointed star fills), read by VoiceOver as the hint of its button")
            }
        case .eraser:
            String(localized: "refine.hint.eraser",
                   defaultValue: "Rub out just what you touch, or tap to erase a spot. Two fingers zoom and move.",
                   comment: "Refine screen: how the Eraser works (it takes out exactly the parts of lines it touches), read by VoiceOver as the hint of its button")
        case .smartEraser:
            String(localized: "refine.hint.smartEraser",
                   defaultValue: "Rub lines out, or tap a line to erase all of it. Two fingers zoom and move.",
                   comment: "Refine screen: how the Smart Eraser works (it takes lines out of the painting's drawing; a tap takes a whole line), read by VoiceOver as the hint of its button")
        case .fill:
            String(localized: "refine.hint.fill",
                   defaultValue: "Tap inside a closed shape to make it an area of its own, in the photo’s color there. Tap it again to clear it. Two fingers zoom and move.",
                   comment: "Refine screen: how the Fill tool works (a tap makes the closed shape of the drawing under it an area of its own, painted the photo's color where it was tapped; a tap in a filled area clears it), read by VoiceOver as the hint of its button")
        case .select:
            String(localized: "refine.hint.select",
                   defaultValue: "Tap an area to select it and see its paint. Tap it again to let it go.",
                   comment: "Refine screen: how Select works (a tap selects the area under it, outlined, with its paint shown in a bar), read by VoiceOver as the hint of its button")
        case .cellEdge:
            String(localized: "refine.hint.cellEdge",
                   defaultValue: "Draw across an area to divide it in two with no line. Both parts keep the paint.",
                   comment: "Refine screen: how Cell Edge works (a stroke divides an area where it goes, drawing no line; both parts keep their paint until painted), read by VoiceOver as the hint of its button")
        case .bendLine:
            String(localized: "refine.hint.bendLine",
                   defaultValue: "Drag a line to move it. It bends near where you hold it.",
                   comment: "Refine screen: how Bend Line works (a drag on a drawn line moves the part of it near the finger, the rest bending smoothly into place), read by VoiceOver as the hint of its button")
        case .moveEdge:
            String(localized: "refine.hint.moveEdge",
                   defaultValue: "Drag the edge between two areas to change their shapes.",
                   comment: "Refine screen: how Move Edge works (a drag on the boundary between two areas moves it, one area growing as the other shrinks), read by VoiceOver as the hint of its button")
        case .moveNumber:
            String(localized: "refine.hint.moveNumber",
                   defaultValue: "Drag a number to where you want it in its area.",
                   comment: "Refine screen: how Move Number works (a drag moves an area's number to another spot inside the same area, where it fits), read by VoiceOver as the hint of its button")
        case .tryPainting:
            String(localized: "refine.hint.tryPainting",
                   defaultValue: "Paints the template as it is now, to try it. Nothing is saved.",
                   comment: "Refine screen: what Try Painting does (opens the painting screen on the template as refined so far; fills made there are not kept), read by VoiceOver as the hint of its button")
        case .merge:
            String(localized: "refine.hint.merge",
                   defaultValue: "Drag across areas to join them into one, in the first one’s paint.",
                   comment: "Refine screen: how Merge works (a drag across areas joins them into one, taking the paint of the area the drag began in; the lines between them go), read by VoiceOver as the hint of its button")
        case .brush:
            String(localized: "refine.hint.brush",
                   defaultValue: "Paint the current paint where you brush, or tap to paint a spot. It joins the areas of that paint it touches.",
                   comment: "Refine screen: how the Paint Brush works (where it is dragged becomes the paint picked in the palette, joining areas of that paint it meets; a tap paints a spot), read by VoiceOver as the hint of its button")
        case .bucket:
            String(localized: "refine.hint.bucket",
                   defaultValue: "Tap an area to give it the current paint.",
                   comment: "Refine screen: how the Bucket works (a tap gives the area under it the paint picked in the palette), read by VoiceOver as the hint of its button")
        case .eyedropper:
            String(localized: "refine.hint.eyedropper",
                   defaultValue: "Tap an area to make its paint the current paint, or touch and hold with any tool. Where the photo shows, it picks the photo’s color.",
                   comment: "Refine screen: how the Eyedropper works (a tap, or a touch and hold with any tool, picks the paint of the area under it, or the photo's color where the photo shows most), read by VoiceOver as the hint of its button")
        case .editPaint:
            String(localized: "refine.hint.editPaint",
                   defaultValue: "Give the current paint a new color everywhere it’s used. Tap an area to pick its paint.",
                   comment: "Refine screen: how Edit Paint works (the current paint takes a new color from the color picker in every area that uses it; a tap on an area picks its paint), read by VoiceOver as the hint of its button")
        case .looks:
            String(localized: "refine.hint.looks",
                   defaultValue: "Pick a look for every paint.",
                   comment: "Refine screen: how Looks works (a look changes every paint of the painting at once), read by VoiceOver as the hint of its button")
        case .text:
            String(localized: "refine.hint.text",
                   defaultValue: "Tap a line of text to keep or ignore it, or drag across a line the app missed.",
                   comment: "Refine screen: how the Text tool works (lines of text in the photo are drawn as writing), read by VoiceOver as the hint of its button")
        }
    }

    /// A tool, prominent while it's the finger's.
    @ViewBuilder
    private func toolButton(_ tool: RefineTool, systemImage: String, label: Text, id: String) -> some View {
        let selected = self.tool == tool
        let button = Button { toolTapped(tool) } label: {
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

    private func shapeName(_ kind: RefineShape) -> Text {
        switch kind {
        case .line: Text("Line")
        case .rectangle: Text("Rectangle")
        case .oval: Text("Oval")
        case .curve: Text("Curve")
        case .polygon: Text("Hexagon")
        case .star: Text("Star")
        }
    }

    private func pickShape(_ kind: RefineShape) {
        if kind != shape { finishCurve() }
        shape = kind
        pick(.shape)
    }

    private func pick(_ tool: RefineTool) {
        pencilPalette = nil
        hovering = nil
        guard tool != self.tool else { return }
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
    private func revealLayer() {
        guard tool != .select, tool != .eyedropper, let layer = tool.layer, layer != .numbers else { return }
        show(layer)
    }

    private func show(_ layer: RefineLayers.Layer) {
        guard !layers.shows(layer) else { return }
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { layers.set(layer, shown: true) }
    }

    /// A tool's button: picks it; Try Painting opens the painting screen instead.
    private func toolTapped(_ tool: RefineTool) {
        if tool == .tryPainting {
            tryPainting()
            return
        }
        pick(tool)
    }

    /// The Pencil's double tap or squeeze, as iPadOS's Apple Pencil settings ask: a pen's eraser
    /// or an eraser's pen, the tool before, or the tools and the palette beside the Pencil
    /// (`location`, where it hovers; else the picture's middle).
    private func pencil(_ action: RefinePencilAction, at location: CGPoint?) {
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
}

// MARK: The Studio

extension RefineView {
    /// Whether every tool stands in a rail along the leading edge (iPad), rather than in group tabs
    /// over a row of the group's tools (iPhone).
    private var usesRail: Bool { sizeClass == .regular }

    /// Whether the palette shows: in Cells and Paint, but for Make Cell, whose cell takes the
    /// photo's color (QA, October 28: the palette there looked like the color it would use).
    private var showsPalette: Bool { (group == .cells || group == .paint) && tool != .fill }

    /// The Studio's bottom: the picked tool's options, the cell Select picked, the palette (in
    /// Cells and Paint), and on iPhone the groups and the group's tools.
    @ViewBuilder
    private var studioBar: some View {
        toolOptions
        if showsPalette, let template = base?.template {
            if tool == .select, let region = selectedRegion {
                selectionBand(template: template, region: region)
            } else {
                RefinePaletteBar(template: template, current: $currentPaint, merge: paletteMerge)
                    .disabled(!model.hasLineArtInput)
            }
        }
        if practice?.teaches == .tryPainting {
            Button("Try Painting", systemImage: "paintbrush", action: tryPainting)
                .buttonStyle(.glassProminent)
                .tint(Theme.signature)
                .disabled(base == nil)
                .accessibilityIdentifier("refine-practice-try")
        }
        if !usesRail, practice == nil {
            Picker("Tools", selection: Binding(get: { group }, set: { choose($0) })) {
                ForEach(RefineGroup.allCases, id: \.self) { kind in
                    Self.groupName(kind).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 420)
            .disabled(!model.hasLineArtInput)
            .accessibilityIdentifier("refine-groups")
            // Centred where the row fits (a group holds at most five), scrolling where it doesn't
            // (larger text).
            ViewThatFits(in: .horizontal) {
                groupRow
                ScrollView(.horizontal) { groupRow }
                    .scrollIndicators(.hidden)
            }
        }
    }

    /// The group's tools, each a round button.
    private var groupRow: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 8) {
                ForEach(group.tools, id: \.self) { kind in
                    studioButton(kind)
                        .disabled(!model.hasLineArtInput)
                }
            }
            .padding(.horizontal, 2)
        }
    }

    /// Every tool, in its group's labelled section, a name beside each (iPad); it scrolls where
    /// the screen is too short for all of them.
    private var toolRail: some View {
        ViewThatFits(in: .vertical) {
            railTools
            ScrollView { railTools }
                .scrollIndicators(.hidden)
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
                    .foregroundStyle(.secondary)
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
        let selected = tool == kind
        let row = Button { toolTapped(kind) } label: {
            HStack(spacing: 10) {
                Image(systemName: symbol(kind))
                    .font(.body.weight(.semibold))
                    .frame(width: 24)
                Self.toolName(kind)
                    .font(.subheadline.weight(selected ? .semibold : .regular))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
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
        .accessibilityLabel(Self.toolName(kind))
        .accessibilityHint(Text(hint(for: kind)))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("refine-tool-\(Self.toolID(kind))")
        .accessibilityShowsLargeContentViewer { Label { Self.toolName(kind) } icon: { Image(systemName: symbol(kind)) } }
        switch kind {
        case .pen: row.gentleTip(.refineDraw, arrowEdge: .leading)
        case .fill: row.gentleTip(.refineFill, arrowEdge: .leading)
        case .shape: row.accessibilityValue(shapeName(shape))
        default: row
        }
    }

    /// A tool's round button (iPhone's row).
    @ViewBuilder
    private func studioButton(_ kind: RefineTool) -> some View {
        let button = toolButton(kind, systemImage: symbol(kind), label: Self.toolName(kind), id: Self.toolID(kind))
        switch kind {
        case .pen: button.gentleTip(.refineDraw, arrowEdge: .bottom)
        case .fill: button.gentleTip(.refineFill, arrowEdge: .bottom)
        case .shape: button.accessibilityValue(shapeName(shape))
        default: button
        }
    }

    static func groupName(_ kind: RefineGroup) -> Text {
        switch kind {
        case .ink: Text("Ink")
        case .cells: Text("Cells")
        case .paint: Text("Paint")
        case .numbers: Text("Numbers")
        case .see: Text("See")
        }
    }

    static func toolName(_ kind: RefineTool) -> Text {
        Text(toolTitle(kind))
    }

    /// A tool's name, as the rail, VoiceOver, the Tool Guide and a key's name in the ⌘ list say it.
    static func toolTitle(_ kind: RefineTool) -> String {
        switch kind {
        case .pen: String(localized: "Pen")
        case .shape: String(localized: "Shapes")
        case .eraser: String(localized: "Eraser")
        case .smartEraser: String(localized: "Line Eraser")
        case .text: String(localized: "Writing")
        case .select: String(localized: "Select")
        case .cellEdge: String(localized: "Cell Edge")
        case .merge: String(localized: "Merge")
        case .fill: String(localized: "Make Cell")
        case .brush: String(localized: "Paint Brush")
        case .bucket: String(localized: "Bucket")
        case .eyedropper: String(localized: "Eyedropper")
        case .editPaint: String(localized: "Edit Paint")
        case .looks: String(localized: "Looks")
        case .bendLine: String(localized: "Bend Line")
        case .moveEdge: String(localized: "Move Edge")
        case .moveNumber: String(localized: "Move Number")
        case .tryPainting: String(localized: "Try Painting")
        }
    }

    private func symbol(_ kind: RefineTool) -> String { Self.symbol(kind, shape: shape) }

    /// A tool's symbol; Shapes' is its figure's.
    static func symbol(_ kind: RefineTool, shape: RefineShape) -> String {
        switch kind {
        case .pen: "pencil.tip"
        case .shape: shape.systemImage
        case .eraser: "eraser"
        case .smartEraser: "eraser.line.dashed"
        case .text: "text.viewfinder"
        case .select: "cursorarrow"
        case .cellEdge: "square.split.diagonal"
        case .merge: "arrow.triangle.merge"
        case .fill: "circle.inset.filled"
        case .brush: "paintbrush.pointed"
        case .bucket: "drop.fill"
        case .eyedropper: "eyedropper"
        case .editPaint: "swatchpalette"
        case .looks: "camera.filters"
        case .bendLine: "scribble"
        case .moveEdge: "arrow.left.and.right.square"
        case .moveNumber: "number.circle"
        case .tryPainting: "paintbrush"
        }
    }

    /// The tool's accessibility identifier, after `refine-tool-` (the UI tests' names).
    nonisolated static func toolID(_ kind: RefineTool) -> String {
        switch kind {
        case .shape: "shapes"
        default: "\(kind)"
        }
    }

    // MARK: Options

    /// What the picked tool offers above the tools: Shapes' figures, Snap where lines join, the
    /// Pen's Color from Photo, the looks, and the current paint's color.
    @ViewBuilder
    private var toolOptions: some View {
        switch tool {
        case .pen:
            optionBar {
                snapToggle
                Toggle(isOn: $penColors) { Text("Color from Photo") }
                    .accessibilityHint(Text(String(
                        localized: "refine.penColors.hint", defaultValue: "Gives the areas a line divides the photo’s colors there.",
                        comment: "Refine screen, the Pen's options: VoiceOver hint of Color from Photo, which makes each part of an area a drawn line divides take the photo's color there")))
                    .accessibilityIdentifier("refine-pen-colors")
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
                snapToggle
            }
        case .cellEdge:
            optionBar { snapToggle }
        case .brush:
            optionBar { sizeSlider($brushSize, id: "refine-brush-size") }
        case .eraser, .smartEraser:
            optionBar { sizeSlider($eraserSize, id: "refine-eraser-size") }
        case .looks, .editPaint:
            if let base {
                RefineColorsPanel(
                    template: base.template, paintsBefore: model.paintsBeforeEdits, edits: base.refinements.edits,
                    mode: tool == .looks ? .looks : .paint, paint: currentIndexBinding, family: $colorFamily,
                    change: recolor)
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

    /// The tool's options in a capsule; `more` beside them where the width holds both, else under them.
    private func optionBar<Content: View, More: View>(
        @ViewBuilder _ content: () -> Content, @ViewBuilder more: () -> More
    ) -> some View {
        let content = content(), more = more()
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) {
                content
                more
            }
            .fixedSize()
            VStack(spacing: 8) {
                HStack(spacing: 16) { content }
                HStack(spacing: 10) { more }
            }
            .fixedSize()
        }
        .font(.footnote)
        .toggleStyle(.switch)
        .tint(Theme.signature)
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
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

    private var snapToggle: some View {
        Toggle(isOn: $snaps) { Text("Snap") }
            .accessibilityHint(Text(String(
                localized: "refine.snap.hint", defaultValue: "Joins the end of a line to a line it touches.",
                comment: "Refine screen, a drawing tool's options: VoiceOver hint of Snap, which moves a drawn line's end onto a line its ink touches")))
            .accessibilityIdentifier("refine-snap")
    }

    /// One of Shapes' figures: picks it.
    private func shapeOption(_ kind: RefineShape) -> some View {
        let selected = shape == kind
        let button = Button {
            FeedbackEngine.shared.selectionChanged()
            pickShape(kind)
        } label: {
            Label { shapeName(kind) } icon: { Image(systemName: kind.systemImage) }
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

    /// Another group on screen, with the tool last picked there.
    private func choose(_ next: RefineGroup) {
        guard next != group else { return }
        lastTool[group] = tool
        pick(lastTool[next] ?? next.tools[0])
        group = next
    }

    /// The Layers button and its panel (`RefineLayersPanel`), the picked tool's layer marked.
    private var layersButton: some View {
        Button("Layers", systemImage: "square.3.layers.3d") {
            FeedbackEngine.shared.selectionChanged()
            showsLayers = true
        }
        .accessibilityHint(Text(String(
            localized: "refine.layers.hint", defaultValue: "Shows or hides the numbers, the ink, the paint and the photo.",
            comment: "Refine screen: VoiceOver hint of the Layers button, which opens a panel of what shows (numbers, ink, paint, photo)")))
        .accessibilityIdentifier("refine-layers")
        .popover(isPresented: $showsLayers) {
            RefineLayersPanel(layers: $layers, working: tool.layer)
                .presentationCompactAdaptation(.popover)
        }
    }

    // MARK: Full screen

    /// The picture alone on screen (a four-finger tap, ⌃⌘F), or the tools and bars back.
    private func toggleFullScreen() {
        FeedbackEngine.shared.selectionChanged()
        withAnimation(reduceMotion ? nil : .snappy) { fullScreen.toggle() }
        keysRequest += 1
    }

    /// The way back from full screen, in the corner.
    private var exitFullScreen: some View {
        Button(action: toggleFullScreen) {
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
        guard !isPractice, !isCovered, model.hasLineArtInput else { return [] }
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
        case .tool(let tool): toolTapped(tool)
        case .smaller: resize(by: -2)
        case .larger: resize(by: 2)
        case .fit: fit()
        case .fullScreen: toggleFullScreen()
        case .undo: undo()
        case .redo: redo()
        }
    }

    /// The Tool Guide or Try Painting covers the screen.
    private var isCovered: Bool { guide != nil || trial != nil }

    /// The tools a key picks.
    static let toolKeys: [(tool: RefineTool, key: String, modifiers: UIKeyModifierFlags)] = [
        (.pen, "p", []), (.shape, "u", []), (.eraser, "e", []), (.smartEraser, "e", .shift), (.select, "v", []),
        (.merge, "m", []), (.bucket, "g", []), (.brush, "b", []), (.eyedropper, "i", []), (.moveNumber, "n", []),
    ]

    /// [ and ]: the Paint Brush's or the Eraser's Size, a step smaller or larger.
    private func resize(by step: Double) {
        switch tool {
        case .brush: brushSize = min(max(brushSize + step, Self.sizes.lowerBound), Self.sizes.upperBound)
        case .eraser, .smartEraser: eraserSize = min(max(eraserSize + step, Self.sizes.lowerBound), Self.sizes.upperBound)
        default: return
        }
        FeedbackEngine.shared.selectionChanged()
    }

    /// The sizes a brush or an eraser can be, in points on screen.
    static let sizes: ClosedRange<Double> = 4...48

    /// The whole picture on screen (⌘0), as a quick pinch in fits it.
    private func fit() {
        focus = RefineFocus(id: (focus?.id ?? 0) + 1, rect: CGRect(x: 0, y: 0, width: 1, height: 1), animated: !reduceMotion)
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
            if group == .cells || group == .paint, let template = base?.template {
                RefinePaletteBar(template: template, current: $currentPaint, merge: paletteMerge)
            }
        }
        .padding(16)
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .presentationCompactAdaptation(.popover)
        .accessibilityIdentifier("refine-pencil-palette")
    }

    // MARK: Holding, hovering and dropping

    /// The Eyedropper's hold, with any tool: a loupe shows the color under the finger over the
    /// current paint while it holds and moves, and lifting makes that color the current paint.
    private func held(_ touch: RefineTouch, at point: SIMD2<Float>) {
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
    private func sampled(at point: SIMD2<Float>) -> SIMD3<Float>? {
        guard let template = base?.template else { return nil }
        if layers.photoReads, let photo = model.source?.image {
            return RefinePalette.snapped(LineEdit.photoColor(at: point, in: photo), to: template.palette)
        }
        guard let region = template.region(at: canvasPoint(point)) else { return nil }
        return template.palette[Int(template.regions[region].colorIndex)].oklab
    }

    /// The Pencil's hover over the picture (nil once it leaves), kept as what it shows.
    private func hovered(_ point: SIMD2<Float>?) {
        let mark = point.flatMap(hoverMark(at:))
        if mark != hovering { hovering = mark }
    }

    /// What the Pencil's hover at `point` shows for the tool in hand: the Eraser's and the Brush's
    /// reach, or the cell a tap would take.
    private func hoverMark(at point: SIMD2<Float>) -> RefineHoverMark.Mark? {
        switch tool {
        case .eraser, .smartEraser: RefineHoverMark.Mark.ring(at: point, radius: eraserRadius)
        case .brush: RefineHoverMark.Mark.ring(at: point, radius: screen.brushRadius(size: CGFloat(brushSize)))
        case .bucket, .fill, .select, .eyedropper, .editPaint: base?.template.region(at: canvasPoint(point)).map(RefineHoverMark.Mark.cell)
        default: nil
        }
    }

    /// A swatch dragged over the picture: the cell it would paint is outlined, and only a cell
    /// takes it.
    private func dropHovered(_ point: SIMD2<Float>?) -> Bool {
        let cell = point.flatMap { model.hasLineArtInput ? base?.template.region(at: canvasPoint($0)) : nil }
        if cell != dropCell { dropCell = cell }
        return cell != nil
    }

    /// A swatch dropped on a cell pours its paint there, as the Bucket does, and becomes the
    /// current paint (Procreate's ColorDrop); the paint shows if it was hidden.
    private func dropped(_ payload: String, at point: SIMD2<Float>) {
        dropCell = nil
        guard let template = base?.template, model.hasLineArtInput, let color = RefinePaletteBar.color(of: payload, in: template),
              template.region(at: canvasPoint(point)) != nil
        else { return }
        FeedbackEngine.shared.selectionChanged()
        currentPaint = color
        show(.paint)
        let at = canvasPoint(point)
        submitted.append(Submitted(id: model.paintArea(at: at, color: color), edit: .paintArea(at: at, color: color)))
        if !isPractice { PaintTips.refineEdited() }
    }

    // MARK: Cells and paint

    /// The region Select picked, on the template on screen.
    private var selectedRegion: Int? {
        guard let selection else { return nil }
        return base?.template.region(at: selection)
    }

    /// The current paint's number less one, when the painting has it.
    private var currentIndex: Int? {
        RefinePalette.index(of: currentPaint, in: base?.template.palette ?? [])
    }

    /// What a swatch dropped on another does: in Edit Paint, `mergePaints`; elsewhere nothing.
    private var paletteMerge: ((Int, Int) -> Void)? {
        guard tool == .editPaint else { return nil }
        return { from, into in mergePaints(from, into: into) }
    }

    /// Edit Paint's swatch dropped on another: paint `from` takes the color of `into`, so the two
    /// become one (`TemplateEditor.Edit.repaint`, whose paints made alike merge), which a note
    /// says; the current paint follows.
    private func mergePaints(_ from: Int, into: Int) {
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
    private func recolor(_ change: RefineColors) {
        if case .repaint(let from, let to, let family) = change, from == currentPaint {
            let edit = TemplateEditor.Edit.repaint(from: from, to: to, family: family)
            repainted = RefinePalette.Repainted(edit: edit, color: TemplateEditor.recolor(from, by: edit), current: currentPaint)
        }
        model.recolor(change)
    }

    private var currentIndexBinding: Binding<Int?> {
        Binding(
            get: { currentIndex },
            set: { index in
                guard let index, let palette = base?.template.palette, index < palette.count else { return }
                currentPaint = palette[index].oklab
            })
    }

    /// The areas that glow: those a Merge drag joins, a card's paint's, the cell Select picked,
    /// or Edit Paint's paint's.
    private var glowAreas: [Int] {
        guard let template = base?.template else { return [] }
        if tool == .merge, trace != nil, let probe = mergeProbe, probe.preview == base?.id { return mergeAreas }
        if let card = card ?? barCard, let region = template.region(at: card.at) {
            return RefinePaintGlow.areas(of: Int(template.regions[region].colorIndex), in: template)
        }
        if tool == .select, let region = selectedRegion { return [region] }
        if tool == .editPaint, let index = currentIndex { return RefinePaintGlow.areas(of: index, in: template) }
        return []
    }

    /// A Merge drag begins: the template on screen gets its probe, unless it has one.
    private func probeMerge() {
        mergeStroke += 1
        mergeAreas = []
        guard let base, mergeProbe?.preview != base.id else { return }
        mergeProbe = (try? TemplateEditor.MergeProbe(base.template)).map { (base.id, $0) }
    }

    /// The areas the Merge drag so far joins, found off the main actor; a drag that moves on while
    /// they are being found waits for that, and only its newest points are looked at.
    private func light(_ points: [SIMD2<Float>]) {
        mergeWanted = points
        guard !mergeProbing else { return }
        lightNext()
    }

    private func lightNext() {
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
    private static func areas(of probe: TemplateEditor.MergeProbe, along path: [SIMD2<Float>]) async -> [Int] {
        probe.areas(along: path)
    }

    /// A tap of Select, the Bucket, the Eyedropper or Edit Paint on the cell under it.
    private func cellTapped(at point: SIMD2<Float>) {
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
    private func announceCurrentPaint(in template: Template) {
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

    /// A point of the picture (0…1) on screen.
    private func onScreen(_ p: SIMD2<Float>) -> CGPoint {
        CGPoint(x: picture.minX + CGFloat(p.x) * picture.width, y: picture.minY + CGFloat(p.y) * picture.height)
    }

    /// A point in canvas units as a point of the picture (0…1).
    private func picturePoint(_ p: SIMD2<Float>) -> SIMD2<Float> {
        let size = templateSize
        guard size.width > 0, size.height > 0 else { return .zero }
        return SIMD2(p.x / Float(size.width), p.y / Float(size.height))
    }

    @ViewBuilder
    private func areaCard(_ pick: RefineAreaPick, inBar: Bool = false) -> some View {
        if let template = base?.template {
            RefineAreaCard(
                template: template, at: pick.at, isolates: pick.isolates, from: pick.from,
                paintArea: { model.paintArea(at: pick.at, color: $0, picking: true) },
                repaint: { from, to in recolor(.repaint(from: from, to: to, family: false)) },
                showPaint: { paint in
                    card = nil
                    barCard = nil
                    currentPaint = template.palette[paint].oklab
                    self.pick(.editPaint)
                },
                inBar: inBar)
        }
    }

    /// The cell Select picked and the palette, one band (Rikyū, `factory/pieces/refine-phase3`):
    /// Change Color opens the cell's card beside it on iPad, and on iPhone in the band itself, in
    /// the palette's place (`barCard`), where nothing covers the picture.
    private func selectionBand(template: Template, region: Int) -> some View {
        VStack(spacing: 0) {
            RefineSelectionBar(template: template, region: region, cardOpen: barCard != nil) {
                guard let selection else { return }
                FeedbackEngine.shared.selectionChanged()
                // Close closes, whatever the width has become since the card opened.
                if barCard != nil {
                    barCard = nil
                } else if usesRail {
                    card = RefineAreaPick(at: selection, screen: onScreen(picturePoint(selection)), template: template)
                } else {
                    barCard = RefineAreaPick(at: selection, screen: .zero, template: template)
                }
            }
            if let barCard {
                areaCard(barCard, inBar: true)
            } else {
                RefinePaletteBar(template: template, current: $currentPaint, merge: paletteMerge, glass: false)
                    .disabled(!model.hasLineArtInput)
            }
        }
        .padding(.vertical, 2)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
        .frame(maxWidth: 720)
        .transition(.opacity)
    }

    /// Start From at the top's leading end and the tiny-numbers badge at its trailing one, clear of
    /// each other; where they don't fit side by side (larger text) the badge goes under the chooser.
    private var topControls: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 8) {
                startChooser
                Spacer(minLength: 0)
                tinyBadge
            }
            VStack(alignment: .leading, spacing: 8) {
                startChooser
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    tinyBadge
                }
            }
        }
    }

    /// Where the template starts from, asked until the first edit: what the generator made (the
    /// default), or the photo as one area (Blank), which the painter's lines and paint then make
    /// into the picture. Out of the way while a note shows at the top.
    @ViewBuilder
    private var startChooser: some View {
        if model.refinements.edits.isEmpty, submitted.isEmpty, model.hasLineArtInput, model.note == nil {
            Picker("Start From", selection: Binding(get: { model.refinements.start }, set: { model.start(from: $0) })) {
                Text("Generated").tag(TemplateRefinements.Start.generated)
                Text("Blank").tag(TemplateRefinements.Start.blank)
            }
            .pickerStyle(.segmented)
            .fixedSize()
            .padding(6)
            .glassEffect(.regular, in: .capsule)
            .disabled(model.phase == .generating)
            .accessibilityIdentifier("refine-start")
            .transition(.opacity)
        }
    }

    /// How many numbers are near the smallest: a tap brings the next of them up close. Out of the
    /// way while a note or the draft's save toast holds the top, which it covered.
    @ViewBuilder
    private var tinyBadge: some View {
        if !tiny.isEmpty, model.note == nil, library?.drafts.saveFailed != model.photoID, let template = base?.template {
            Button {
                tinyShown = (tinyShown + 1) % tiny.count
                let label = tiny[tinyShown].label
                focus = RefineFocus(
                    id: (focus?.id ?? 0) + 1, rect: RefineTinyAreas.focus(on: label, in: template), animated: !reduceMotion)
                FeedbackEngine.shared.selectionChanged()
            } label: {
                Label { Text(Self.tinyText(tiny.count)) } icon: { Image(systemName: "magnifyingglass") }
                    .font(.footnote.weight(.semibold))
            }
            .buttonStyle(.glass)
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

    /// A line or a cell edge closed off an area of its own: a soft tap, VoiceOver hears of it, and
    /// the sparkles pop where its ends met (none under Reduce Motion).
    private func closed(_ shape: CreateModel.ClosedShape) {
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
                    Button("Undo", systemImage: "arrow.uturn.backward", action: undo)
                        .disabled(!model.canUndo)
                        .keyboardShortcut("z")
                        .accessibilityIdentifier("refine-undo")
                    Button("Redo", systemImage: "arrow.uturn.forward", action: redo)
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

extension RefineView {
    /// Try Painting: the painting screen on the template on screen, once the canvas's renderer is
    /// made (`ArtworkPaintingView` waits for it too). Its fills go when it closes.
    fileprivate func tryPainting() {
        guard let template = base?.template else { return }
        FeedbackEngine.shared.selectionChanged()
        Task {
            _ = await RenderContext.ready()
            trial = RefineTrial(session: PaintingSession(template: template, nicknameVersion: ColorNickname.currentVersion))
        }
    }
}
