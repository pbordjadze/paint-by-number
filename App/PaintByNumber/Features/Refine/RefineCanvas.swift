import PaintCore
import SwiftUI
import UIKit

/// What the painter did on the Refine screen that the template doesn't show yet, in the order
/// they did it, over the drawing in `rect` (view coordinates): lines drawn in the drawing's own
/// ink and weight, and the eraser's passes and the lines tapped away showing the paper or the
/// photo beneath, so whatever they took out is gone at once. `trace` is the pen's line or the
/// eraser's pass still under the finger; while the eraser is down a ring shows its reach, and
/// rings mark where the Smart Pen's ends will join (`joins`).
struct RefineInkLayer: View {
    let lines: [TemplateRefinements.Line]
    let trace: [SIMD2<Float>]?
    /// The trace is the line as it will be drawn (the Smart Pen's), not the finger's samples.
    let traceIsDrawn: Bool
    /// Where the pen's ends will join lines.
    let joins: [SIMD2<Float>]
    /// The trace is the eraser's, not the pen's.
    let erasing: Bool
    /// The eraser's reach either side of its pass, a fraction of the picture's long side.
    let eraserRadius: Float
    let rect: CGRect
    /// The drawing's line width, in points.
    let lineWidth: CGFloat
    /// The photo, when it shows beneath the drawing; nil: the paper does.
    let photo: CGImage?

    var body: some View {
        let lines = lines, trace = trace, erasing = erasing, eraserRadius = eraserRadius, rect = rect
        let lineWidth = lineWidth, photo = photo, traceIsDrawn = traceIsDrawn, joins = joins
        let joinColor = Theme.signature
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
                if photo != nil {
                    canvas.stroke(path, with: .color(.white.opacity(0.75)), style: Self.style(lineWidth + 2.5))
                }
                canvas.stroke(path, with: .color(LineArtDrawing.ink), style: Self.style(lineWidth))
            }
            // What lies beneath the drawing, over `covered`.
            func uncover(_ covered: Path) {
                var beneath = canvas
                beneath.clip(to: covered)
                if let photo {
                    beneath.draw(Image(decorative: photo, scale: 1), in: rect)
                } else {
                    beneath.fill(Path(rect), with: .color(LineArtDrawing.paper))
                }
            }
            func erase(_ path: Path, radius: Float) {
                uncover(path.strokedPath(Self.style(2 * CGFloat(radius) * long)))
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
                    let width = lineWidth + (photo == nil ? 1.5 : 4)
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
                } else {
                    ink(traceIsDrawn ? polyline(points) : Path(PenPath.path(points)))
                }
            }
            // A ring round each join, wider than the line, so the join shows through it.
            let r = max(2.5 * lineWidth, 5)
            for join in joins.map(point) {
                let ring = Path(ellipseIn: CGRect(x: join.x - r, y: join.y - r, width: 2 * r, height: 2 * r))
                canvas.fill(ring, with: .color(joinColor.opacity(0.18)))
                canvas.stroke(ring, with: .color(joinColor), lineWidth: 1.5)
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
/// swatch of the photo's color (`LineEdit.photoColor`, what the pipeline paints it with) where
/// each fill the template doesn't have yet was tapped, until the template that has it comes. An
/// area whose fill was cleared since shows no more.
struct RefineFillLayer: View, Equatable {
    let base: CreateModel.Preview?
    /// The fills of the refinements, in order.
    let fills: [TemplateRefinements.Line]
    /// The photo the pipeline reads, for the swatches' color; it is the same while Refine is open.
    let photo: RGBAImage?
    let rect: CGRect

    /// How opaque an area's paint is laid over the drawing.
    static let areaOpacity: Double = 0.75
    /// A swatch's radius, in points on screen.
    static let swatchRadius: CGFloat = 6

    nonisolated static func == (a: RefineFillLayer, b: RefineFillLayer) -> Bool {
        a.base?.id == b.base?.id && a.fills == b.fills && a.rect == b.rect && (a.photo == nil) == (b.photo == nil)
    }

    var body: some View {
        let areas = Self.areas(base?.template, fills: fills), rect = rect
        let made = (base?.refinements.lines ?? []).filter { $0.kind == .fill }
        let swatches = fills.filter { !made.contains($0) && !$0.points.isEmpty }.compactMap { fill -> (SIMD2<Float>, Color)? in
            guard let photo else { return nil }
            let lab = LineEdit.photoColor(at: fill.points[0], in: photo)
            let rgb = ColorScience.okLabToEncoded(lab, space: photo.colorSpace)
            let color = Color(photo.colorSpace == .displayP3 ? .displayP3 : .sRGB, red: Double(rgb.x), green: Double(rgb.y), blue: Double(rgb.z))
            return (fill.points[0], color)
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
                for (point, color) in swatches {
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

    /// The areas of `template` a fill made (its detail areas holding one of `fills`' points):
    /// their rings in canvas units and their paint.
    static func areas(_ template: Template?, fills: [TemplateRefinements.Line]) -> [(rings: [[SIMD2<Float>]], paint: Color)] {
        guard let template, !template.detailRegions.isEmpty else { return [] }
        var filled = Set<Int>()
        for fill in fills where !fill.points.isEmpty {
            if let r = RefineFills.region(of: fill.points[0], in: template), template.isDetailRegion(r) { filled.insert(r) }
        }
        return filled.sorted().map { (template.polygons(ofRegion: $0), PaletteBar.paint(template, Int(template.regions[$0].colorIndex))) }
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

/// Where a finger is in a stroke on the refine canvas.
enum RefineTouch {
    case began, moved, ended, cancelled
}

/// The refine canvas's touches: an invisible scroll view zooms and moves the picture with two
/// fingers, with the system's feel (the painting canvas's way), while one finger draws or taps;
/// a tap of two fingers undoes, as in drawing apps. Once an Apple Pencil touches it (or with
/// Only Draw with Apple Pencil on), the Pencil draws and taps, and one finger moves the picture
/// too, as on the painting canvas; the Pencil's double tap is reported. Reports where the
/// picture is in its frame and its zoom, and touches in picture coordinates (0…1, origin
/// top-left).
struct RefineTouchSurface: UIViewRepresentable {
    var aspectRatio: CGFloat
    var onLayout: (CGRect, CGFloat) -> Void
    var onDraw: (RefineTouch, SIMD2<Float>) -> Void
    var onTap: (SIMD2<Float>) -> Void
    var onUndo: () -> Void
    var onPencilTap: () -> Void

    func makeUIView(context: Context) -> RefineSurfaceView { RefineSurfaceView() }

    func updateUIView(_ view: RefineSurfaceView, context: Context) {
        view.onLayout = onLayout
        view.onDraw = onDraw
        view.onTap = onTap
        view.onUndo = onUndo
        view.onPencilTap = onPencilTap
        view.aspectRatio = aspectRatio
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
    var onPencilTap: (() -> Void)?

    /// The Pencil draws and fingers only move the picture: an Apple Pencil touched the canvas,
    /// or Only Draw with Apple Pencil is on. Stays so while the screen is open.
    private(set) var pencilDraws = false

    /// Deep enough that a Pencil outlines a star of a few canvas units comfortably (to Fill it).
    static let maximumZoom: CGFloat = 12
    /// Room around the picture at zoom 1, so it reads as a card.
    static let margin: CGFloat = 12

    private let scrollView = UIScrollView()
    /// The picture at zoom 1, which the scroll view zooms: touches read in its coordinates.
    private let content = UIView()
    private let brush = UIPanGestureRecognizer()
    private let tap = UITapGestureRecognizer()
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
        content.isUserInteractionEnabled = false
        scrollView.addSubview(content)
        addSubview(scrollView)

        brush.addTarget(self, action: #selector(handleBrush(_:)))
        brush.maximumNumberOfTouches = 1
        brush.delegate = self
        scrollView.addGestureRecognizer(brush)
        tap.addTarget(self, action: #selector(handleTap(_:)))
        scrollView.addGestureRecognizer(tap)
        let undo = UITapGestureRecognizer(target: self, action: #selector(handleUndo(_:)))
        undo.numberOfTouchesRequired = 2
        scrollView.addGestureRecognizer(undo)
        addInteraction(UIPencilInteraction(delegate: self))
        if UIPencilInteraction.prefersPencilOnlyDrawing { drawWithPencil() }
    }

    /// From now on the Pencil (and a pointer) draws and taps; one finger moves the picture, two
    /// zoom it.
    private func drawWithPencil() {
        guard !pencilDraws else { return }
        pencilDraws = true
        let drawing = [UITouch.TouchType.pencil, .indirectPointer].map { NSNumber(value: $0.rawValue) }
        brush.allowedTouchTypes = drawing
        tap.allowedTouchTypes = drawing
        scrollView.panGestureRecognizer.minimumNumberOfTouches = 1
        scrollView.panGestureRecognizer.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        scrollView.pinchGestureRecognizer?.allowedTouchTypes = [UITouch.TouchType.direct, .indirectPointer]
            .map { NSNumber(value: $0.rawValue) }
    }

    /// While the Pencil draws, a palm or a finger beside it neither moves the picture nor ends
    /// the stroke.
    private func holdPicture(_ held: Bool) {
        guard pencilDraws else { return }
        scrollView.panGestureRecognizer.isEnabled = !held
        scrollView.pinchGestureRecognizer?.isEnabled = !held
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layoutSubviews() {
        isLayingOut = true
        defer { isLayingOut = false }
        super.layoutSubviews()
        scrollView.frame = bounds
        let fitted = CompareView.fitted(aspectRatio, in: bounds.insetBy(dx: Self.margin, dy: Self.margin).size)
        if fitted != fittedSize {
            fittedSize = fitted
            scrollView.zoomScale = 1
            content.frame = CGRect(origin: .zero, size: fitted)
            scrollView.contentSize = fitted
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
    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) { cancelDrawing() }
    func scrollViewWillBeginZooming(_ scrollView: UIScrollView, with view: UIView?) { cancelDrawing() }

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
            holdPicture(true)
            // The stroke starts where the finger came down, before the pan's slop.
            let moved = recognizer.translation(in: content)
            onDraw?(.began, normalized(CGPoint(x: location.x - moved.x, y: location.y - moved.y)))
            onDraw?(.moved, normalized(location))
        case .changed:
            onDraw?(.moved, normalized(location))
        case .ended:
            holdPicture(false)
            onDraw?(.ended, normalized(location))
        default:
            holdPicture(false)
            onDraw?(.cancelled, normalized(location))
        }
    }

    @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended else { return }
        onTap?(normalized(recognizer.location(in: content)))
    }

    @objc private func handleUndo(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended else { return }
        onUndo?()
    }

    private func normalized(_ p: CGPoint) -> SIMD2<Float> {
        guard fittedSize.width > 0, fittedSize.height > 0 else { return .zero }
        return SIMD2(Float(p.x / fittedSize.width), Float(p.y / fittedSize.height))
    }

    /// A pinch may begin as a stroke: the scroll view's gestures run beside the brush's and
    /// cancel its stroke (`cancelDrawing`) rather than lose to it.
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
    ) -> Bool { true }

    /// The first touch of an Apple Pencil hands drawing to it (the brush sees every touch until
    /// then).
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        if touch.type == .pencil { drawWithPencil() }
        return true
    }
}

extension RefineSurfaceView: UIPencilInteractionDelegate {
    // Honour the Apple Pencil settings: the double tap may be turned off there.
    func pencilInteraction(_ interaction: UIPencilInteraction, didReceiveTap tap: UIPencilInteraction.Tap) {
        guard UIPencilInteraction.preferredTapAction != .ignore else { return }
        onPencilTap?()
    }
}
