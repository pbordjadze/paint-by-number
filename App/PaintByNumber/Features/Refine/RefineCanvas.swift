import SwiftUI
import UIKit

/// What the painter did on the Refine screen that the template doesn't show yet, in the order
/// they did it, over the drawing in `rect` (view coordinates): lines drawn in the drawing's own
/// ink and weight, and the eraser's passes and the lines tapped away showing the paper or the
/// photo beneath, so whatever they took out is gone at once. `trace` is the pen's line or the
/// eraser's pass still under the finger; while the eraser is down a ring shows its reach.
struct RefineInkLayer: View {
    let lines: [TemplateRefinements.Line]
    let trace: [SIMD2<Float>]?
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
        let lineWidth = lineWidth, photo = photo
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
                    ink(Path(PenPath.path(points)))
                }
            }
        }
        .allowsHitTesting(false)
    }

    nonisolated static func style(_ width: CGFloat) -> StrokeStyle {
        StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round)
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
/// a tap of two fingers undoes, as in drawing apps. Reports where the picture is in its frame
/// and its zoom, and touches in picture coordinates (0…1, origin top-left).
struct RefineTouchSurface: UIViewRepresentable {
    var aspectRatio: CGFloat
    var onLayout: (CGRect, CGFloat) -> Void
    var onDraw: (RefineTouch, SIMD2<Float>) -> Void
    var onTap: (SIMD2<Float>) -> Void
    var onUndo: () -> Void

    func makeUIView(context: Context) -> RefineSurfaceView { RefineSurfaceView() }

    func updateUIView(_ view: RefineSurfaceView, context: Context) {
        view.onLayout = onLayout
        view.onDraw = onDraw
        view.onTap = onTap
        view.onUndo = onUndo
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

    static let maximumZoom: CGFloat = 6
    /// Room around the picture at zoom 1, so it reads as a card.
    static let margin: CGFloat = 12

    private let scrollView = UIScrollView()
    /// The picture at zoom 1, which the scroll view zooms: touches read in its coordinates.
    private let content = UIView()
    private let brush = UIPanGestureRecognizer()
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
        scrollView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleTap(_:))))
        let undo = UITapGestureRecognizer(target: self, action: #selector(handleUndo(_:)))
        undo.numberOfTouchesRequired = 2
        scrollView.addGestureRecognizer(undo)
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
            // The stroke starts where the finger came down, before the pan's slop.
            let moved = recognizer.translation(in: content)
            onDraw?(.began, normalized(CGPoint(x: location.x - moved.x, y: location.y - moved.y)))
            onDraw?(.moved, normalized(location))
        case .changed:
            onDraw?(.moved, normalized(location))
        case .ended:
            onDraw?(.ended, normalized(location))
        default:
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
}
