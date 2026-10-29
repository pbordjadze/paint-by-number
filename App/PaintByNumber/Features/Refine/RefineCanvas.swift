import PaintCore
import QuartzCore
import SwiftUI
import UIKit

/// The edits sent on the Refine screen that the template doesn't show yet, in the order they were
/// sent, over the drawing in `rect` (view coordinates): lines drawn in the drawing's own
/// ink and weight, and the eraser's passes and the lines tapped away showing the paper, photo or
/// painting beneath, so whatever they took out is gone at once. `trace` is the pen's line, the
/// shape or the eraser's pass still under the finger; while the eraser is down a ring shows its
/// reach.
struct RefineInkLayer: View {
    /// A Paint Brush stroke: its path (normalized to the picture), its reach either side (a
    /// fraction of the picture's long side) and its paint.
    nonisolated struct Brush: Equatable {
        var points: [SIMD2<Float>]
        var radius: Float
        var color: Color
    }

    let lines: [TemplateRefinements.Line]
    let trace: [SIMD2<Float>]?
    /// The trace is the line as it will be drawn (a shape), not the finger's samples.
    let traceIsDrawn: Bool
    /// The trace is the eraser's, not the pen's.
    let erasing: Bool
    /// The trace is a Cell Edge's, a line that won't be drawn: dashed.
    var dashed = false
    /// The trace is Merge's, a path that draws nothing: in the signature color.
    var merging = false
    /// The Paint Brush's strokes the template doesn't show yet, and the one under the finger, laid
    /// in their paint (Refine gives them a layer of their own, under the drawing).
    var brushes: [Brush] = []
    /// The eraser's reach either side of its pass, a fraction of the picture's long side.
    let eraserRadius: Float
    let rect: CGRect
    /// The drawing's line width, in points.
    let lineWidth: CGFloat
    /// The photo or the painting, when it shows beneath the drawing; nil: the paper does.
    let beneath: CGImage?
    /// The ink is edged in white, as the drawing is over the photo.
    let halo: Bool

    var body: some View {
        let lines = lines, trace = trace, erasing = erasing, eraserRadius = eraserRadius, rect = rect
        let lineWidth = lineWidth, beneath = beneath, halo = halo, traceIsDrawn = traceIsDrawn, dashed = dashed
        let merging = merging, brushes = brushes, signature = Theme.signature
        Canvas { context, _ in
            guard rect.width > 0, rect.height > 0 else { return }
            let long = max(rect.width, rect.height)
            func point(_ p: SIMD2<Float>) -> CGPoint {
                CGPoint(x: rect.minX + CGFloat(p.x) * rect.width, y: rect.minY + CGFloat(p.y) * rect.height)
            }
            var canvas = context
            canvas.clip(to: Path(rect))
            // A single point (a dab) is a segment to nowhere, which a round cap still draws.
            func polyline(_ points: [CGPoint]) -> Path {
                var path = Path()
                path.addLines(points.count == 1 ? [points[0], points[0]] : points)
                return path
            }
            func ink(_ path: Path) {
                if halo {
                    canvas.stroke(path, with: .color(.white.opacity(0.75)), style: Self.style(lineWidth + 2.5))
                }
                canvas.stroke(path, with: .color(LineArtDrawing.ink), style: Self.style(lineWidth))
            }
            // What lies beneath the drawing, over `covered`.
            func uncover(_ covered: Path) {
                var under = canvas
                under.clip(to: covered)
                if let beneath {
                    under.draw(Image(decorative: beneath, scale: 1), in: rect)
                } else {
                    under.fill(Path(rect), with: .color(LineArtDrawing.paper))
                }
            }
            func erase(_ path: Path, radius: Float) {
                uncover(path.strokedPath(Self.style(2 * CGFloat(radius) * long)))
            }
            for brush in brushes where !brush.points.isEmpty {
                let path = polyline(brush.points.map(point))
                canvas.stroke(path, with: .color(brush.color.opacity(0.85)), style: Self.style(2 * CGFloat(brush.radius) * long))
            }
            for line in lines where !line.points.isEmpty {
                let path = polyline(line.points.map(point))
                switch line.kind {
                case .draw:
                    ink(path)
                case .erase:
                    erase(path, radius: line.radius)
                case .eraseLine:
                    // The line itself, its own path, and not what meets it at its ends.
                    let width = lineWidth + (halo ? 4 : 1.5)
                    uncover(path.strokedPath(StrokeStyle(lineWidth: width, lineCap: .butt, lineJoin: .round)))
                case .fill:
                    // `RefineFillLayer` shows fills.
                    break
                }
            }
            if let trace, let last = trace.last {
                let points = trace.map(point)
                if erasing {
                    erase(polyline(points), radius: eraserRadius)
                    let r = CGFloat(eraserRadius) * long
                    let ring = Path(ellipseIn: CGRect(x: point(last).x - r, y: point(last).y - r, width: 2 * r, height: 2 * r))
                    canvas.fill(ring, with: .color(.white.opacity(0.25)))
                    canvas.stroke(ring, with: .color(LineArtDrawing.ink.opacity(0.45)), lineWidth: 1)
                } else if merging {
                    canvas.stroke(polyline(points), with: .color(signature), style: Self.style(max(lineWidth, 2.5)))
                } else if dashed {
                    var style = Self.style(lineWidth)
                    style.dash = [lineWidth * 2.5, lineWidth * 2.5]
                    canvas.stroke(Path(PenPath.path(points)), with: .color(LineArtDrawing.ink.opacity(0.7)), style: style)
                } else {
                    ink(traceIsDrawn ? polyline(points) : Path(PenPath.path(points)))
                }
            }
        }
        .allowsHitTesting(false)
    }

    nonisolated static func style(_ width: CGFloat) -> StrokeStyle {
        StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round)
    }
}

/// The painter's fills over the drawing in `rect` (view coordinates): each area a fill made in
/// the template on screen (`base`'s detail areas holding a fill's point) tinted its paint,
/// multiplied in so the drawing's ink stays on top and the paper or photo shows through, and a
/// swatch of the photo's color (`LineEdit.photoColor`, what the fill paints it with) where each
/// fill the template doesn't have yet was tapped, until the template that has it comes. Over the
/// painting (`showsAreas` off) the areas are painted already: only the swatches show.
struct RefineFillLayer: View, Equatable {
    /// A fill sent and not shown yet: where it was tapped (normalized to the picture) and the
    /// photo's color there (OKLab).
    nonisolated struct Swatch: Equatable {
        let point: SIMD2<Float>
        let color: SIMD3<Float>
    }

    let base: CreateModel.Preview?
    /// Where the fills the template has were tapped, normalized to the picture.
    let fills: [SIMD2<Float>]
    let swatches: [Swatch]
    /// The photo's color space, for the swatches' color; the same while Refine is open.
    let space: RGBColorSpace?
    let rect: CGRect
    var showsAreas = true

    /// How opaque an area's paint is laid over the drawing.
    static let areaOpacity: Double = 0.75
    /// A swatch's radius, in points on screen.
    static let swatchRadius: CGFloat = 6

    nonisolated static func == (a: RefineFillLayer, b: RefineFillLayer) -> Bool {
        a.base?.id == b.base?.id && a.fills == b.fills && a.swatches == b.swatches && a.rect == b.rect && a.space == b.space
            && a.showsAreas == b.showsAreas
    }

    var body: some View {
        let areas = showsAreas ? Self.areas(base?.template, fills: fills) : [], rect = rect
        let dots = swatches.compactMap { swatch -> (SIMD2<Float>, Color)? in
            guard let space else { return nil }
            let rgb = ColorScience.okLabToEncoded(swatch.color, space: space)
            let color = Color(space == .displayP3 ? .displayP3 : .sRGB, red: Double(rgb.x), green: Double(rgb.y), blue: Double(rgb.z))
            return (swatch.point, color)
        }
        let size = base.map { CGSize(width: $0.template.width, height: $0.template.height) } ?? .zero
        let opacity = Self.areaOpacity, r = Self.swatchRadius
        ZStack {
            Canvas { context, _ in
                guard size.width > 0, size.height > 0, rect.width > 0 else { return }
                // Filled into the picture as the drawing is (`LineArtLayer`).
                let s = max(rect.width / size.width, rect.height / size.height)
                let origin = CGPoint(x: rect.midX - size.width * s / 2, y: rect.midY - size.height * s / 2)
                var tinted = context
                tinted.clip(to: Path(rect))
                tinted.translateBy(x: origin.x, y: origin.y)
                tinted.scaleBy(x: s, y: s)
                for area in areas {
                    var path = Path()
                    for ring in area.rings where ring.count >= 3 {
                        path.addLines(ring.map { CGPoint(x: CGFloat($0.x), y: CGFloat($0.y)) })
                        path.closeSubpath()
                    }
                    tinted.fill(path, with: .color(area.paint.opacity(opacity)), style: FillStyle(eoFill: true))
                }
            }
            .blendMode(.multiply)
            Canvas { context, _ in
                for (point, color) in dots {
                    let centre = CGPoint(x: rect.minX + CGFloat(point.x) * rect.width, y: rect.minY + CGFloat(point.y) * rect.height)
                    let dot = Path(ellipseIn: CGRect(x: centre.x - r, y: centre.y - r, width: 2 * r, height: 2 * r))
                    context.fill(dot, with: .color(color))
                    // A white ring edged in ink reads on paper, photo and paint alike.
                    context.stroke(dot, with: .color(.white), lineWidth: 2)
                    let edge = Path(ellipseIn: CGRect(x: centre.x - r - 1, y: centre.y - r - 1, width: 2 * r + 2, height: 2 * r + 2))
                    context.stroke(edge, with: .color(LineArtDrawing.ink.opacity(0.4)), lineWidth: 0.75)
                }
            }
        }
        .allowsHitTesting(false)
    }

    /// The areas of `template` a fill made (its detail areas holding one of the `fills`): their
    /// rings in canvas units and their paint.
    static func areas(_ template: Template?, fills: [SIMD2<Float>]) -> [(rings: [[SIMD2<Float>]], paint: Color)] {
        guard let template, !template.detailRegions.isEmpty else { return [] }
        let size = SIMD2(Float(template.width), Float(template.height))
        var filled = Set<Int>()
        for point in fills {
            if let r = template.region(at: point * size), template.isDetailRegion(r) { filled.insert(r) }
        }
        return filled.sorted().map { (template.polygons(ofRegion: $0), PaletteBar.paint(template, Int(template.regions[$0].colorIndex))) }
    }
}

/// Areas outlined in the signature color, in screen points even while zooming: every area of the
/// paint Edit Paint or a card picked, or the cell Select picked. Each area's closed rings include
/// its holes, just as `RefineFillLayer`'s even-odd paths do.
struct RefinePaintGlow: View, Equatable {
    let base: CreateModel.Preview?
    /// The regions of `base`'s template that glow.
    let areas: [Int]
    let rect: CGRect
    let reduceMotion: Bool

    @State private var haloOpacity = 0.22

    nonisolated static func == (a: RefinePaintGlow, b: RefinePaintGlow) -> Bool {
        a.base?.id == b.base?.id && a.areas == b.areas && a.rect == b.rect && a.reduceMotion == b.reduceMotion
    }

    nonisolated static func areas(of paint: Int, in template: Template) -> [Int] {
        template.regions.indices.filter { Int(template.regions[$0].colorIndex) == paint }
    }

    var body: some View {
        ZStack {
            outlines(width: 8)
                .blur(radius: 2)
                .opacity(reduceMotion ? 0.22 : haloOpacity)
            outlines(width: 2)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task(id: areas) {
            haloOpacity = 0.22
            guard !areas.isEmpty, !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.3)) { haloOpacity = 0.42 }
            do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
            guard !Task.isCancelled, !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.3)) { haloOpacity = 0.22 }
        }
        .onChange(of: reduceMotion) { _, _ in haloOpacity = 0.22 }
    }

    private func outlines(width: CGFloat) -> some View {
        let rings = base.map { base in
            areas.filter { $0 < base.template.regions.count }.map { base.template.polygons(ofRegion: $0) }
        } ?? []
        let size = base.map { CGSize(width: $0.template.width, height: $0.template.height) } ?? .zero
        let rect = rect, color = Theme.signature
        return Canvas { context, _ in
            guard size.width > 0, size.height > 0, rect.width > 0, rect.height > 0 else { return }
            let s = max(rect.width / size.width, rect.height / size.height)
            let origin = CGPoint(x: rect.midX - size.width * s / 2, y: rect.midY - size.height * s / 2)
            var glowing = context
            glowing.clip(to: Path(rect))
            glowing.translateBy(x: origin.x, y: origin.y)
            glowing.scaleBy(x: s, y: s)
            for area in rings {
                var path = Path()
                for ring in area where ring.count >= 3 {
                    path.addLines(ring.map { CGPoint(x: CGFloat($0.x), y: CGFloat($0.y)) })
                    path.closeSubpath()
                }
                glowing.stroke(path, with: .color(color), style: RefineInkLayer.style(width / s))
            }
        }
    }
}

/// A line the eraser was tapped on, glowing in the signature color as it goes (its view fades it).
struct RefineTappedLine: View {
    let points: [SIMD2<Float>]
    let rect: CGRect
    let lineWidth: CGFloat

    var body: some View {
        Path { path in
            path.addLines(points.map {
                CGPoint(x: rect.minX + CGFloat($0.x) * rect.width, y: rect.minY + CGFloat($0.y) * rect.height)
            })
        }
        .stroke(Theme.signature, style: RefineInkLayer.style(max(2.5 * lineWidth, 4)))
        .shadow(color: Theme.signature.opacity(0.6), radius: 6)
        .allowsHitTesting(false)
    }
}

/// What Refine tells the painter (`RefineNote`): a glass capsule at the top that takes no touches,
/// like the app's other toasts (`Toast`), which VoiceOver is told of when it comes
/// (`CreateModel.say`). Nothing without a note.
struct RefineNoteToast: View {
    let note: RefineNote?

    var body: some View {
        if let note {
            Toast(text: note.text, systemImage: note.systemImage, edge: .top)
                .padding(.horizontal, 20)
                .allowsHitTesting(false)
                .accessibilityIdentifier("refine-note")
        }
    }
}

/// The refinements over the picture in `rect`: brushed areas tinted (more detail in the
/// signature color, less in slate; the eraser clears both), and the lines of text boxed in
/// orange, found or marked, a line turned off dashed. `refinements` include the stroke still
/// under the finger, `marking` the line being dragged out.
struct RefineMarks: View {
    let refinements: TemplateRefinements
    let found: [[SIMD2<Float>]]
    let marking: (SIMD2<Float>, SIMD2<Float>)?
    let rect: CGRect
    /// The Text tool is up: lines stand out.
    let emphasizesText: Bool

    static let more = Theme.signature
    static let less = Color(red: 0.36, green: 0.45, blue: 0.56)
    static let text = Color.orange

    var body: some View {
        let refinements = refinements, found = found, marking = marking, rect = rect, emphasizesText = emphasizesText
        let more = Self.more, less = Self.less, text = Self.text
        Canvas { context, _ in
            let long = max(rect.width, rect.height)
            func point(_ p: SIMD2<Float>) -> CGPoint {
                CGPoint(x: rect.minX + CGFloat(p.x) * rect.width, y: rect.minY + CGFloat(p.y) * rect.height)
            }
            // Each stroke opaque in one layer, the layer translucent: overlaps don't darken, and a
            // later stroke covers the earlier ones as it does in the template.
            var areas = context
            areas.opacity = 0.42
            areas.drawLayer { layer in
                for stroke in refinements.strokes {
                    var path = Path()
                    path.addLines(stroke.points.map(point) + (stroke.points.count == 1 ? stroke.points.map(point) : []))
                    let style = StrokeStyle(lineWidth: 2 * CGFloat(stroke.radius) * long, lineCap: .round, lineJoin: .round)
                    switch stroke.kind {
                    case .more:
                        layer.blendMode = .normal
                        layer.stroke(path, with: .color(more), style: style)
                    case .less:
                        layer.blendMode = .normal
                        layer.stroke(path, with: .color(less), style: style)
                    case .erase:
                        layer.blendMode = .clear
                        layer.stroke(path, with: .color(.black), style: style)
                    }
                }
            }
            var lines = context
            lines.opacity = emphasizesText ? 1 : 0.55
            for line in found {
                let hidden = refinements.hiddenText.contains { TemplateRefinements.sameLine(line, $0) }
                Self.box(line.map(point), hidden: hidden, color: text, in: &lines)
            }
            for line in refinements.addedText {
                Self.box(line.map(point), hidden: false, color: text, in: &lines)
            }
            if let marking {
                Self.box(TemplateRefinements.textLine(from: marking.0, to: marking.1).map(point), hidden: true, color: text, in: &lines)
            }
        }
        .allowsHitTesting(false)
    }

    /// A line of text's box: filled and solid when it counts as text, dashed when it doesn't.
    nonisolated private static func box(_ corners: [CGPoint], hidden: Bool, color: Color, in context: inout GraphicsContext) {
        guard let first = corners.first else { return }
        var path = Path()
        path.move(to: first)
        for corner in corners.dropFirst() { path.addLine(to: corner) }
        path.closeSubpath()
        if hidden {
            context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 1.5, lineJoin: .round, dash: [5, 4]))
        } else {
            context.fill(path, with: .color(color.opacity(0.16)))
            context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 2, lineJoin: .round))
        }
    }
}

/// A part of the picture to bring up close (normalized, 0…1), each request with its own `id`.
struct RefineFocus: Equatable {
    let id: Int
    let rect: CGRect
    let animated: Bool
}

/// Where a finger is in a stroke on the refine canvas.
enum RefineTouch {
    case began, moved, ended, cancelled
}


/// What the Apple Pencil's double tap or squeeze asks for, as the painter set it in iPadOS's
/// Apple Pencil settings (`UIPencilInteraction.preferredTapAction`, `preferredSqueezeAction`).
enum RefinePencilAction {
    /// The tool's eraser, or the eraser's pen.
    case switchEraser
    /// The tool picked before this one.
    case switchPrevious
    /// The tools and the palette, beside the Pencil.
    case showPalette

    /// What `preferred` asks of Refine; nil for nothing (Ignore, or a system shortcut iPadOS runs
    /// itself).
    init?(_ preferred: UIPencilPreferredAction) {
        switch preferred {
        case .switchEraser: self = .switchEraser
        case .switchPrevious: self = .switchPrevious
        case .showColorPalette, .showInkAttributes, .showContextualPalette: self = .showPalette
        case .ignore, .runSystemShortcut: return nil
        @unknown default: return nil
        }
    }
}

/// A key of a hardware keyboard on the Refine screen (`RefineView.keys`): what it is, its name in
/// the list holding ⌘ shows, and what it does.
struct RefineKey: Equatable {
    enum Action: Equatable {
        case tool(RefineTool)
        case smaller, larger, fit, fullScreen, undo, redo
    }

    let input: String
    let modifiers: UIKeyModifierFlags
    let title: String
    let action: Action
}

/// The refine canvas's touches, the gestures of iPad drawing apps: an invisible scroll view zooms
/// and moves the picture with two fingers, with the system's feel (the painting canvas's way),
/// while one finger draws or taps; a tap of two fingers undoes and of three redoes, two or three
/// held down keep undoing or redoing, a quick pinch in fits the picture (and a quick pinch out goes
/// back), and a tap of four fingers asks for the full screen. A finger (or the Pencil) held still
/// for a moment is a hold, which no tool draws with: it is the Eyedropper's, reported as it moves.
/// With Only Draw with Apple Pencil on (iPadOS's setting, read again whenever the app comes back),
/// the Pencil draws and taps, one finger moves the picture and a finger's hold still picks;
/// otherwise fingers draw too, and a Pencil's stroke holds the picture still. The Pencil's double
/// tap and squeeze are reported as its settings ask, its hover as it moves, and a palette swatch
/// dragged over the picture as it goes and where it is dropped. Reports where the picture is in
/// its frame and its zoom, and touches in picture coordinates (0…1, origin top-left).
struct RefineTouchSurface: UIViewRepresentable {
    var aspectRatio: CGFloat
    var onLayout: (CGRect, CGFloat) -> Void
    var onDraw: (RefineTouch, SIMD2<Float>) -> Void
    var onTap: (SIMD2<Float>) -> Void
    var onUndo: () -> Void
    var onRedo: () -> Void = {}
    /// A step of held fingers' undo (false) or redo (true); false back once there's nothing more
    /// to step, which ends the hold's steps.
    var onRepeat: (Bool) -> Bool = { _ in false }
    /// A hold picks a color (the Eyedropper's); off, a touch held still before a drag is the
    /// drag's (Bend Line, Move Edge, Move Number).
    var holdPicks = true
    /// A one-finger drag is the tool's stroke: a touch that becomes one is no tap as well. Off (a
    /// tool that only taps), a tap that wanders a little is still a tap.
    var strokes = true
    /// The Pencil's double tap or squeeze, and where it hovers then (the view's coordinates).
    var onPencil: (RefinePencilAction, CGPoint?) -> Void = { _, _ in }
    var onHold: (RefineTouch, SIMD2<Float>) -> Void = { _, _ in }
    /// Where the Pencil (or a pointer) hovers; nil once it leaves.
    var onHover: (SIMD2<Float>?) -> Void = { _ in }
    /// A swatch's drag (its text) dropped on the picture, and where.
    var onDrop: (String, SIMD2<Float>) -> Void = { _, _ in }
    /// Where a swatch's drag is over the picture, and whether a cell there would take it; nil once
    /// it leaves or lands.
    var onDropHover: (SIMD2<Float>?) -> Bool = { _ in false }
    var onFullScreen: () -> Void = {}
    /// A hardware keyboard's keys, and what one pressed asks for.
    var keys: [RefineKey] = []
    var onKey: (RefineKey.Action) -> Void = { _ in }
    /// Changed, the canvas takes the keys again (after the full screen lays it out anew).
    var keysRequest = 0
    var focus: RefineFocus?

    func makeUIView(context: Context) -> RefineSurfaceView { RefineSurfaceView() }

    func updateUIView(_ view: RefineSurfaceView, context: Context) {
        view.onLayout = onLayout
        view.onDraw = onDraw
        view.onTap = onTap
        view.onUndo = onUndo
        view.onRedo = onRedo
        view.onRepeat = onRepeat
        view.holdPicks = holdPicks
        view.strokes = strokes
        view.onPencil = onPencil
        view.onHold = onHold
        view.onHover = onHover
        view.onDrop = onDrop
        view.onDropHover = onDropHover
        view.onFullScreen = onFullScreen
        view.keys = keys
        view.onKey = onKey
        if view.keysRequest != keysRequest {
            view.keysRequest = keysRequest
            Task { @MainActor in if !view.isFirstResponder { _ = view.becomeFirstResponder() } }
        }
        view.aspectRatio = aspectRatio
        // Zooming reports the layout, which sets state: never within SwiftUI's update.
        if let focus, focus.id != view.focusedRequest {
            view.focusedRequest = focus.id
            Task { @MainActor in view.focus(on: focus) }
        }
    }
}

final class RefineSurfaceView: UIView, UIScrollViewDelegate, UIGestureRecognizerDelegate {
    var aspectRatio: CGFloat = 1 {
        didSet { if aspectRatio != oldValue { setNeedsLayout() } }
    }
    var onLayout: ((CGRect, CGFloat) -> Void)?
    var onDraw: ((RefineTouch, SIMD2<Float>) -> Void)?
    var onTap: ((SIMD2<Float>) -> Void)?
    var onUndo: (() -> Void)?
    var onRedo: (() -> Void)?
    var onRepeat: ((Bool) -> Bool)?
    var holdPicks = true
    var strokes = true
    var onPencil: ((RefinePencilAction, CGPoint?) -> Void)?
    var onHold: ((RefineTouch, SIMD2<Float>) -> Void)?
    var onHover: ((SIMD2<Float>?) -> Void)?
    var onDrop: ((String, SIMD2<Float>) -> Void)?
    var onDropHover: ((SIMD2<Float>?) -> Bool)?
    var onFullScreen: (() -> Void)?
    var keys: [RefineKey] = []
    var onKey: ((RefineKey.Action) -> Void)?
    var keysRequest = 0

    /// The Pencil draws and fingers only move the picture: Only Draw with Apple Pencil is on (nil
    /// until the surface has read it).
    private var pencilOnly: Bool?

    /// Deep enough that a Pencil outlines a star of a few canvas units comfortably (to Fill it).
    static let maximumZoom: CGFloat = 12
    /// Room around the picture at zoom 1, so it reads as a card.
    static let margin: CGFloat = 12
    /// How long a touch is held still before it is a hold, iOS's own half second, and how far it
    /// may wander meanwhile: little, so a slow, careful stroke still draws.
    static let pressDuration: TimeInterval = 0.5
    static let pressMovement: CGFloat = 4
    /// How long two or three fingers are held before they keep undoing or redoing (a pinch that
    /// waits this long before it moves takes one step), and how often they then step: faster the
    /// longer they're held, down to `fastestRepeat`, each step once the last has landed.
    static let repeatDelay: TimeInterval = 0.5
    static let firstRepeat: TimeInterval = 0.25
    static let fastestRepeat: TimeInterval = 0.07
    /// A pinch over within this long is a quick pinch, when it at least halves or doubles the
    /// zoom's step (its scale under `quickIn`, over `quickOut`).
    static let quickPinch: TimeInterval = 0.35
    static let quickIn: CGFloat = 0.7
    static let quickOut: CGFloat = 1.4

    private static let allTouches = [UITouch.TouchType.direct, .indirect, .pencil, .indirectPointer]
        .map { NSNumber(value: $0.rawValue) }

    private let scrollView = UIScrollView()
    /// The picture at zoom 1, which the scroll view zooms: touches read in its coordinates.
    private let content = UIView()
    private let brush = UIPanGestureRecognizer()
    private let tap = UITapGestureRecognizer()
    private let press = UILongPressGestureRecognizer()
    private let undoTap = UITapGestureRecognizer()
    private let redoTap = UITapGestureRecognizer()
    private let undoHold = UILongPressGestureRecognizer()
    private let redoHold = UILongPressGestureRecognizer()
    private let fullScreenTap = UITapGestureRecognizer()
    /// Where the brush's finger came down: the stroke starts there, not where the pan began, past
    /// its slop (UIKit's translation at `.began` doesn't reach back to the touch).
    private var touchDown: CGPoint?
    /// The stroke under way is the Pencil's: the picture holds still under it.
    private var pencilStroke = false
    /// Undo or Redo, stepping while their fingers are held, and where the fingers came down.
    private var repeating: Task<Void, Never>?
    private var repeatStart: CGPoint?
    /// When a pinch began, at what zoom, and the part of the picture then on screen (normalized).
    private var pinchStart: (time: TimeInterval, zoom: CGFloat, visible: CGRect)?
    /// The part of the picture on screen before a quick pinch fitted it, for a quick pinch out.
    private var beforeFit: CGRect?
    private var fittedSize: CGSize = .zero
    private var reported: (rect: CGRect, zoom: CGFloat)?
    private var isLayingOut = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        scrollView.delegate = self
        scrollView.backgroundColor = .clear
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.bouncesZoom = true
        scrollView.delaysContentTouches = false
        scrollView.scrollsToTop = false
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = Self.maximumZoom
        // One finger is the brush's: the picture moves with two.
        scrollView.panGestureRecognizer.minimumNumberOfTouches = 2
        scrollView.pinchGestureRecognizer?.addTarget(self, action: #selector(handlePinch(_:)))
        content.isUserInteractionEnabled = false
        scrollView.addSubview(content)
        addSubview(scrollView)

        brush.addTarget(self, action: #selector(handleBrush(_:)))
        brush.maximumNumberOfTouches = 1
        brush.delegate = self
        scrollView.addGestureRecognizer(brush)
        tap.addTarget(self, action: #selector(handleTap(_:)))
        scrollView.addGestureRecognizer(tap)
        // Held still, a touch is a hold; moved, the brush's. A tap waits for the hold to fail,
        // which it does the moment the finger lifts early.
        press.addTarget(self, action: #selector(handlePress(_:)))
        press.minimumPressDuration = Self.pressDuration
        press.allowableMovement = Self.pressMovement
        press.delegate = self
        scrollView.addGestureRecognizer(press)
        tap.require(toFail: press)

        for (recognizer, touches) in [(undoTap, 2), (redoTap, 3), (fullScreenTap, 4)] {
            recognizer.numberOfTouchesRequired = touches
            recognizer.addTarget(self, action: #selector(handleFingers(_:)))
            scrollView.addGestureRecognizer(recognizer)
        }
        for (recognizer, touches) in [(undoHold, 2), (redoHold, 3)] {
            recognizer.numberOfTouchesRequired = touches
            recognizer.minimumPressDuration = Self.repeatDelay
            recognizer.allowableMovement = Self.repeatMovement
            // Beside the scroll view's pan and pinch: fingers that move go on to move the picture.
            recognizer.delegate = self
            recognizer.addTarget(self, action: #selector(handleRepeat(_:)))
            scrollView.addGestureRecognizer(recognizer)
        }
        // A tap is the fewest fingers it can be, once more of them have lifted or held on.
        undoTap.require(toFail: redoTap)
        undoTap.require(toFail: fullScreenTap)
        redoTap.require(toFail: fullScreenTap)
        undoTap.require(toFail: undoHold)
        redoTap.require(toFail: redoHold)

        scrollView.addGestureRecognizer(UIHoverGestureRecognizer(target: self, action: #selector(handleHover(_:))))
        addInteraction(UIPencilInteraction(delegate: self))
        addInteraction(UIDropInteraction(delegate: self))
        applyDrawingPolicy()
        NotificationCenter.default.addObserver(
            self, selector: #selector(appBecameActive), name: UIApplication.didBecomeActiveNotification, object: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// How far held fingers may move before they are moving the picture, not stepping.
    static let repeatMovement: CGFloat = 10

    /// No system editing gestures over the picture: three fingers redo here, and never show
    /// iPadOS's undo bar.
    override var editingInteractionConfiguration: UIEditingInteractionConfiguration { .none }

    // MARK: Keys

    /// First responder while on screen (the painting canvas's way), so its keys come before the
    /// menu bar's, which the Paint menu shares some of, and VoiceOver meets no stand-ins for them.
    override var canBecomeFirstResponder: Bool { true }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else { return }
        Task { @MainActor [weak self] in _ = self?.becomeFirstResponder() }
    }

    override var keyCommands: [UIKeyCommand]? {
        keys.indices.map { index in
            let key = keys[index]
            let command = UIKeyCommand(
                title: key.title, action: #selector(handleKey(_:)), input: key.input, modifierFlags: key.modifiers,
                propertyList: index)
            command.wantsPriorityOverSystemBehavior = true
            return command
        }
    }

    @objc private func handleKey(_ command: UIKeyCommand) {
        guard let index = command.propertyList as? Int, keys.indices.contains(index) else { return }
        onKey?(keys[index].action)
    }

    /// Only Draw with Apple Pencil may have changed in Settings while the app was away.
    @objc private func appBecameActive() { applyDrawingPolicy() }

    /// iPadOS's Only Draw with Apple Pencil, as PencilKit's default policy reads it: on, the Pencil
    /// (and a pointer) draws and taps, one finger moves the picture and two zoom it, and a finger
    /// held still picks a color; off, fingers draw as the Pencil does and two move the picture.
    private func applyDrawingPolicy() {
        let only = UIPencilInteraction.prefersPencilOnlyDrawing
        guard only != pencilOnly else { return }
        pencilOnly = only
        let drawing = only ? [UITouch.TouchType.pencil, .indirectPointer].map { NSNumber(value: $0.rawValue) } : Self.allTouches
        brush.allowedTouchTypes = drawing
        tap.allowedTouchTypes = drawing
        press.allowedTouchTypes = Self.allTouches
        scrollView.panGestureRecognizer.minimumNumberOfTouches = only ? 1 : 2
        scrollView.panGestureRecognizer.allowedTouchTypes = only
            ? [NSNumber(value: UITouch.TouchType.direct.rawValue)] : Self.allTouches
        scrollView.pinchGestureRecognizer?.allowedTouchTypes = only
            ? [UITouch.TouchType.direct, .indirectPointer].map { NSNumber(value: $0.rawValue) } : Self.allTouches
    }

    /// While the Pencil draws, or a finger holds to pick a color, a palm or another finger neither
    /// moves the picture nor ends the stroke.
    private func holdPicture(_ held: Bool) {
        scrollView.panGestureRecognizer.isEnabled = !held
        scrollView.pinchGestureRecognizer?.isEnabled = !held
    }

    override func layoutSubviews() {
        isLayingOut = true
        defer { isLayingOut = false }
        super.layoutSubviews()
        // Zoomed in, the same part of the picture stays on screen (full screen, a rotation): what
        // the frame showed before it changes.
        let shown = fittedSize.width > 0 && scrollView.zoomScale > 1.01 ? visiblePart() : nil
        scrollView.frame = bounds
        let fitted = CompareView.fitted(aspectRatio, in: bounds.insetBy(dx: Self.margin, dy: Self.margin).size)
        if fitted != fittedSize {
            let kept = shown
            fittedSize = fitted
            scrollView.zoomScale = 1
            content.frame = CGRect(origin: .zero, size: fitted)
            scrollView.contentSize = fitted
            if let kept {
                centre()
                scrollView.zoom(to: onContent(kept), animated: false)
            }
        }
        centre()
        report()
    }

    /// Insets that centre the picture while it is smaller than the frame.
    private func centre() {
        let size = content.frame.size
        let x = max(0, (bounds.width - size.width) / 2), y = max(0, (bounds.height - size.height) / 2)
        scrollView.contentInset = UIEdgeInsets(top: y, left: x, bottom: y, right: x)
    }

    /// The part of the picture on screen, normalized.
    private func visiblePart() -> CGRect {
        guard fittedSize.width > 0, fittedSize.height > 0 else { return CGRect(x: 0, y: 0, width: 1, height: 1) }
        let shown = scrollView.convert(scrollView.bounds, to: content).intersection(CGRect(origin: .zero, size: fittedSize))
        return CGRect(
            x: shown.minX / fittedSize.width, y: shown.minY / fittedSize.height,
            width: shown.width / fittedSize.width, height: shown.height / fittedSize.height)
    }

    /// A normalized part of the picture in the content's coordinates.
    private func onContent(_ part: CGRect) -> CGRect {
        CGRect(
            x: part.minX * fittedSize.width, y: part.minY * fittedSize.height,
            width: part.width * fittedSize.width, height: part.height * fittedSize.height)
    }

    /// The last focus asked for (`RefineFocus.id`).
    var focusedRequest: Int?

    /// Zooms in on `focus.rect` (normalized to the picture); the whole picture fits it.
    func focus(on focus: RefineFocus) {
        focusedRequest = focus.id
        beforeFit = nil
        guard fittedSize.width > 0, fittedSize.height > 0 else { return }
        scrollView.zoom(to: onContent(focus.rect), animated: focus.animated)
    }

    private func report() {
        let rect = content.frame.offsetBy(dx: -scrollView.contentOffset.x, dy: -scrollView.contentOffset.y)
        let zoom = scrollView.zoomScale
        if let reported, reported.rect == rect, reported.zoom == zoom { return }
        reported = (rect, zoom)
        // Never inside a layout pass SwiftUI may be running.
        if isLayingOut {
            Task { @MainActor [weak self] in self?.onLayout?(rect, zoom) }
        } else {
            onLayout?(rect, zoom)
        }
    }

    // MARK: UIScrollViewDelegate

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { content }
    func scrollViewDidScroll(_ scrollView: UIScrollView) { report() }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        cancelDrawing()
        stopRepeating()
        // A move of the picture forgets the way back from a quick pinch; a pinch's own drift
        // doesn't.
        if pinchStart == nil, !scrollView.isZooming { beforeFit = nil }
    }

    func scrollViewWillBeginZooming(_ scrollView: UIScrollView, with view: UIView?) {
        cancelDrawing()
        stopRepeating()
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        centre()
        report()
    }

    /// Two fingers came down while one was drawing: they move the picture, and the stroke goes.
    /// (The Pencil's stroke holds the picture still instead, `holdPicture`.)
    private func cancelDrawing() {
        guard brush.state == .began || brush.state == .changed else { return }
        brush.isEnabled = false
        brush.isEnabled = true
    }

    // MARK: Touches

    @objc private func handleBrush(_ recognizer: UIPanGestureRecognizer) {
        let location = recognizer.location(in: content)
        switch recognizer.state {
        case .began:
            // The keys again, if another view (a color picker's field) took them meanwhile.
            if !isFirstResponder { _ = becomeFirstResponder() }
            if pencilStroke { holdPicture(true) }
            // The stroke starts where the finger came down, before the pan's slop (a stroke's
            // first ten points or so were lost, so a shape drawn in strokes didn't close).
            let moved = recognizer.translation(in: content)
            let start = touchDown ?? CGPoint(x: location.x - moved.x, y: location.y - moved.y)
            touchDown = nil
            onDraw?(.began, normalized(start))
            onDraw?(.moved, normalized(location))
        case .changed:
            onDraw?(.moved, normalized(location))
        case .ended:
            endStroke()
            onDraw?(.ended, normalized(location))
        default:
            endStroke()
            onDraw?(.cancelled, normalized(location))
        }
    }

    private func endStroke() {
        if pencilStroke { holdPicture(false) }
        pencilStroke = false
        touchDown = nil
    }

    @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended else { return }
        onTap?(normalized(recognizer.location(in: content)))
    }

    /// The Eyedropper's hold: where it began, where it moves, and where it lifts.
    @objc private func handlePress(_ recognizer: UILongPressGestureRecognizer) {
        let point = normalized(recognizer.location(in: content))
        switch recognizer.state {
        case .began:
            holdPicture(true)
            onHold?(.began, point)
        case .changed:
            onHold?(.moved, point)
        case .ended:
            holdPicture(false)
            onHold?(.ended, point)
        default:
            holdPicture(false)
            onHold?(.cancelled, point)
        }
    }

    /// A tap of two fingers undoes, of three redoes, of four asks for the full screen.
    @objc private func handleFingers(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended else { return }
        switch recognizer.numberOfTouchesRequired {
        case 2: onUndo?()
        case 3: onRedo?()
        default: onFullScreen?()
        }
    }

    /// Two fingers held keep undoing, three keep redoing, until they lift, run out of steps or
    /// move the picture.
    @objc private func handleRepeat(_ recognizer: UILongPressGestureRecognizer) {
        let at = recognizer.location(in: self)
        switch recognizer.state {
        case .began:
            cancelDrawing()
            repeatStart = at
            startRepeating(redo: recognizer === redoHold)
        case .changed:
            if scrollView.isZooming { stopRepeating() }
            if let start = repeatStart, hypot(at.x - start.x, at.y - start.y) > Self.repeatMovement { stopRepeating() }
        default:
            stopRepeating()
        }
    }

    /// Steps at once, then again and again, faster the longer the fingers stay, each step waiting
    /// for the last to land (`onRepeat` says when there's none left).
    private func startRepeating(redo: Bool) {
        stopRepeating()
        guard onRepeat?(redo) == true else { return }
        repeating = Task { @MainActor [weak self] in
            var interval = RefineSurfaceView.firstRepeat
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled, let self else { return }
                guard self.onRepeat?(redo) == true else { return }
                interval = max(RefineSurfaceView.fastestRepeat, interval * 0.85)
            }
        }
    }

    private func stopRepeating() {
        repeating?.cancel()
        repeating = nil
        repeatStart = nil
    }

    /// A quick pinch in fits the picture to the screen; a quick pinch out right after goes back to
    /// what was on screen before.
    @objc private func handlePinch(_ pinch: UIPinchGestureRecognizer) {
        switch pinch.state {
        case .began:
            pinchStart = (CACurrentMediaTime(), scrollView.zoomScale, visiblePart())
        case .ended:
            guard let start = pinchStart, CACurrentMediaTime() - start.time < Self.quickPinch else {
                pinchStart = nil
                beforeFit = nil
                return
            }
            pinchStart = nil
            let animated = !UIAccessibility.isReduceMotionEnabled
            if pinch.scale < Self.quickIn, start.zoom > 1.01 {
                beforeFit = start.visible
                // After the scroll view's own end of the pinch.
                Task { @MainActor [weak self] in self?.scrollView.setZoomScale(1, animated: animated) }
            } else if pinch.scale > Self.quickOut, start.zoom < 1.01, let back = beforeFit {
                beforeFit = nil
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.scrollView.zoom(to: self.onContent(back), animated: animated)
                }
            } else {
                beforeFit = nil
            }
        case .cancelled, .failed:
            pinchStart = nil
        default:
            break
        }
    }

    @objc private func handleHover(_ recognizer: UIHoverGestureRecognizer) {
        switch recognizer.state {
        case .began, .changed:
            onHover?(normalized(recognizer.location(in: content)))
        default:
            onHover?(nil)
        }
    }

    private func normalized(_ p: CGPoint) -> SIMD2<Float> {
        guard fittedSize.width > 0, fittedSize.height > 0 else { return .zero }
        return SIMD2(Float(p.x / fittedSize.width), Float(p.y / fittedSize.height))
    }

    /// A pinch may begin as a stroke: the scroll view's gestures run beside the brush's and
    /// cancel its stroke (`cancelDrawing`) rather than lose to it.
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
    ) -> Bool {
        // A hold and a stroke are one finger's: whichever comes first has it; and so are a tap and
        // a stroke, with a tool whose stroke does something: a drag of about ten points was both
        // (a curve's small bend laid it straight and began another; an eraser's short rub dabbed
        // too, CI October 28).
        let pair = Set([ObjectIdentifier(gestureRecognizer), ObjectIdentifier(other)])
        return pair != Set([ObjectIdentifier(press), ObjectIdentifier(brush)])
            && !(strokes && pair == Set([ObjectIdentifier(tap), ObjectIdentifier(brush)]))
    }

    /// A stroke can't begin under a hold that has begun, nor a hold under a stroke; with a tool
    /// that drags, a touch held still waits for its drag.
    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer === brush { return press.state != .began && press.state != .changed }
        if gestureRecognizer === press { return holdPicks && brush.state != .began && brush.state != .changed }
        // Fingers held still step, not fingers zooming or moving the picture, nor a third finger
        // joining two that already step.
        if gestureRecognizer === undoHold || gestureRecognizer === redoHold {
            return !scrollView.isZooming && !scrollView.isDragging && repeating == nil
        }
        return super.gestureRecognizerShouldBegin(gestureRecognizer)
    }

    /// Notes where a stroke's first touch came down, and whether it is the Pencil's.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        // Only a touch that can start the stroke: the first, of a kind the brush takes.
        if gestureRecognizer === brush, brush.numberOfTouches == 0,
           brush.allowedTouchTypes.contains(NSNumber(value: touch.type.rawValue)) {
            touchDown = touch.location(in: content)
            pencilStroke = touch.type == .pencil
        }
        return true
    }
}

extension RefineSurfaceView: UIPencilInteractionDelegate {
    // Honour the Apple Pencil settings: each gesture does what they ask, or nothing.
    func pencilInteraction(_ interaction: UIPencilInteraction, didReceiveTap tap: UIPencilInteraction.Tap) {
        guard let action = RefinePencilAction(UIPencilInteraction.preferredTapAction) else { return }
        onPencil?(action, tap.hoverPose?.location)
    }

    func pencilInteraction(_ interaction: UIPencilInteraction, didReceiveSqueeze squeeze: UIPencilInteraction.Squeeze) {
        guard squeeze.phase == .ended, let action = RefinePencilAction(UIPencilInteraction.preferredSqueezeAction) else { return }
        onPencil?(action, squeeze.hoverPose?.location)
    }
}

/// A palette swatch dragged onto the picture (`RefinePaletteBar`): only the app's own drags, which
/// carry the swatch's text.
extension RefineSurfaceView: UIDropInteractionDelegate {
    func dropInteraction(_ interaction: UIDropInteraction, canHandle session: UIDropSession) -> Bool {
        session.localDragSession != nil && session.canLoadObjects(ofClass: NSString.self)
    }

    func dropInteraction(_ interaction: UIDropInteraction, sessionDidUpdate session: UIDropSession) -> UIDropProposal {
        let takes = onDropHover?(normalized(session.location(in: content))) ?? false
        return UIDropProposal(operation: takes ? .copy : .forbidden)
    }

    func dropInteraction(_ interaction: UIDropInteraction, sessionDidExit session: UIDropSession) {
        _ = onDropHover?(nil)
    }

    func dropInteraction(_ interaction: UIDropInteraction, sessionDidEnd session: UIDropSession) {
        _ = onDropHover?(nil)
    }

    func dropInteraction(_ interaction: UIDropInteraction, performDrop session: UIDropSession) {
        let point = normalized(session.location(in: content))
        _ = session.loadObjects(ofClass: NSString.self) { [weak self] items in
            guard let text = (items.first as? NSString).map({ String($0) }) else { return }
            Task { @MainActor in self?.onDrop?(text, point) }
        }
    }
}

/// The Eyedropper's hold under the finger: where it is (normalized to the picture) and the color
/// it would pick (OKLab); none where there's no cell.
struct RefineHold: Equatable {
    let at: SIMD2<Float>
    let color: SIMD3<Float>?
}

/// The Eyedropper's loupe, as drawing apps show it while a finger holds to pick: a ring above the
/// finger (below it near the top), the color under the finger in its upper half over the current
/// paint in its lower half.
struct RefineLoupe: View {
    /// The color under the finger; nil off the picture's cells.
    let picked: Color?
    /// The current paint, which the pick would replace.
    let current: Color?

    static let diameter: CGFloat = 78
    static let ring: CGFloat = 18
    /// How far above the finger it sits, so the fingertip doesn't hide it.
    static let lift: CGFloat = 86

    /// Where the loupe goes for a finger at `point`, within a canvas of `size`.
    static func position(over point: CGPoint, in size: CGSize) -> CGPoint {
        // Its outer ring's reach, and a little room.
        let half = (diameter + ring) / 2 + 4
        let y = point.y - lift < half ? point.y + lift : point.y - lift
        return CGPoint(x: min(max(point.x, half), max(half, size.width - half)), y: y)
    }

    var body: some View {
        let inner = Self.diameter - Self.ring
        ZStack {
            // From three o'clock, clockwise: the lower half, then the upper.
            Circle()
                .trim(from: 0, to: 0.5)
                .stroke(current ?? Color.secondary.opacity(0.25), lineWidth: Self.ring)
            Circle()
                .trim(from: 0.5, to: 1)
                .stroke(picked ?? Color.secondary.opacity(0.25), lineWidth: Self.ring)
            Circle()
                .strokeBorder(.white.opacity(0.9), lineWidth: 1.5)
                .frame(width: Self.diameter + Self.ring, height: Self.diameter + Self.ring)
            Circle()
                .strokeBorder(.black.opacity(0.25), lineWidth: 0.75)
                .frame(width: Self.diameter + Self.ring + 2, height: Self.diameter + Self.ring + 2)
            Circle()
                .strokeBorder(.white.opacity(0.9), lineWidth: 1.5)
                .frame(width: inner, height: inner)
        }
        .frame(width: Self.diameter, height: Self.diameter)
        .shadow(color: .black.opacity(0.2), radius: 6, y: 2)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// What the Pencil's hover shows over the picture in `rect`: the Eraser's or the Brush's reach as
/// a ring where it would touch, or the outline of the cell a tap there would take (a dragged
/// swatch's too).
struct RefineHoverMark: View {
    enum Mark: Equatable {
        /// A ring at a picture point (0…1), its radius a fraction of the picture's long side.
        case ring(at: SIMD2<Float>, radius: Float)
        /// A region of the template on screen.
        case cell(Int)
    }

    let mark: Mark
    let base: CreateModel.Preview?
    let rect: CGRect

    /// The cell's outline, holes too, in canvas units.
    private var rings: [[SIMD2<Float>]] {
        guard case .cell(let region) = mark, let template = base?.template, region < template.regions.count else { return [] }
        return template.polygons(ofRegion: region)
    }

    var body: some View {
        let mark = mark, rect = rect, color = Theme.signature, rings = rings
        let size = base.map { CGSize(width: $0.template.width, height: $0.template.height) } ?? .zero
        Canvas { context, _ in
            guard rect.width > 0, rect.height > 0 else { return }
            switch mark {
            case .ring(let at, let radius):
                let r = CGFloat(radius) * max(rect.width, rect.height)
                let centre = CGPoint(x: rect.minX + CGFloat(at.x) * rect.width, y: rect.minY + CGFloat(at.y) * rect.height)
                let ring = Path(ellipseIn: CGRect(x: centre.x - r, y: centre.y - r, width: 2 * r, height: 2 * r))
                context.stroke(ring, with: .color(.white.opacity(0.8)), lineWidth: 2.5)
                context.stroke(ring, with: .color(LineArtDrawing.ink.opacity(0.6)), lineWidth: 1)
            case .cell:
                guard size.width > 0, size.height > 0 else { return }
                let s = max(rect.width / size.width, rect.height / size.height)
                var outlined = context
                outlined.clip(to: Path(rect))
                outlined.translateBy(x: rect.midX - size.width * s / 2, y: rect.midY - size.height * s / 2)
                outlined.scaleBy(x: s, y: s)
                var path = Path()
                for ring in rings where ring.count >= 3 {
                    path.addLines(ring.map { CGPoint(x: CGFloat($0.x), y: CGFloat($0.y)) })
                    path.closeSubpath()
                }
                outlined.stroke(path, with: .color(color.opacity(0.8)), style: RefineInkLayer.style(1.5 / s))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
