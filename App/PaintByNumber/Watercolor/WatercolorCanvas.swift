#if UNRELEASED
import MetalKit
import PaintCore
import Ravenna
import SwiftUI
import UIKit

/// The sheet on screen: an `MTKView` drawn by `WatercolorRenderer`, under an invisible scroll view
/// that gives the system's pan, pinch and deceleration (the main canvas's way, `CanvasView`). A
/// tap lays a wash where it lands, a finger dragged lays the areas it crosses, and two fingers move
/// and zoom, as on the main canvas; Hint and Zen Mode fly the sheet to an area (`fly(to:)`). The
/// view draws every frame only while the sheet is wet. The
/// sheet is the canvas and its paper margins, fitted above `bottomInset` (the paint box lying over
/// the desk); finished, it is signed in pencil in its bottom margin (`signed`).
final class WatercolorCanvasView: UIView, UIScrollViewDelegate {
    let renderer: WatercolorRenderer
    private let metal: MTKView
    private let scroll = UIScrollView()
    private let page = UIView()
    private let signature = UIView()
    private var fittedSize: CGSize = .zero
    /// A tap at a canvas point, with the tolerance a fingertip has at the zoom (canvas units).
    var onTap: ((SIMD2<Float>, Float) -> Void)?
    /// A finger dragged over a canvas point (painting only the paint in hand), the same tolerance.
    var onDrag: ((SIMD2<Float>, Float) -> Void)?
    /// A drag begins (true) or ends (false): one step of Undo.
    var onStroke: ((Bool) -> Void)?
    /// A fingertip on screen, in points: how near a small area a tap still lays it.
    static let fingertip: CGFloat = 16
    /// Points at the bottom the paint box covers: the sheet fits above them.
    var bottomInset: CGFloat = 0 {
        didSet {
            guard bottomInset != oldValue else { return }
            insetChanged = true
            setNeedsLayout()
        }
    }
    private var insetChanged = false
    var reduceMotion = false

    init(renderer: WatercolorRenderer) {
        self.renderer = renderer
        metal = MTKView(frame: .zero, device: renderer.device)
        super.init(frame: .zero)
        metal.colorPixelFormat = WatercolorRenderer.colorFormat
        metal.framebufferOnly = true
        metal.preferredFramesPerSecond = 60
        metal.enableSetNeedsDisplay = true
        metal.isPaused = true
        metal.isUserInteractionEnabled = false
        metal.delegate = renderer
        if let layer = metal.layer as? CAMetalLayer {
            layer.colorspace = CGColorSpace(name: CGColorSpace.displayP3)
        }
        addSubview(metal)
        let t = renderer.painting.template
        page.frame = CGRect(x: 0, y: 0, width: t.width, height: t.height)
        let margins = WatercolorRenderer.margins(of: t)
        signature.frame = CGRect(x: 0, y: CGFloat(t.height), width: CGFloat(t.width), height: CGFloat(margins.bottom))
        signature.alpha = 0
        signature.isUserInteractionEnabled = false
        page.addSubview(signature)
        scroll.addSubview(page)
        scroll.delegate = self
        scroll.showsHorizontalScrollIndicator = false
        scroll.showsVerticalScrollIndicator = false
        scroll.contentInsetAdjustmentBehavior = .never
        scroll.bouncesZoom = true
        scroll.backgroundColor = .clear
        addSubview(scroll)
        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped(_:)))
        scroll.addGestureRecognizer(tap)
        // One finger paints, two move the sheet: the main canvas's way.
        scroll.panGestureRecognizer.minimumNumberOfTouches = 2
        let drag = UIPanGestureRecognizer(target: self, action: #selector(dragged(_:)))
        drag.maximumNumberOfTouches = 1
        scroll.addGestureRecognizer(drag)
        EraSounds.shared.sheetOpened()
        renderer.onActivity = { [weak self] active in
            self?.setRunning(active)
            // Still again: the water has dried (`EraSounds` says it once a tap).
            if !active { EraSounds.shared.sheetDried() }
        }
        // A wash laid any other way (VoiceOver's action, a demo) wakes the sheet too.
        renderer.painting.onTap = { [weak self] in self?.setRunning(true) }
        // Undo puts the sheet back: drawn again whole, and running if it was wet then.
        renderer.painting.onRestore = { [weak self] in
            guard let self else { return }
            self.setRunning(true)
            self.metal.setNeedsDisplay()
        }
        isAccessibilityElement = false
        // A sheet opened with washes still wet goes on drying at once, not at the first tap.
        setRunning(renderer.needsFrames)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// The sheet's size in canvas units: the canvas and its margins.
    private var sheetSize: CGSize {
        let t = renderer.painting.template
        let margins = WatercolorRenderer.margins(of: t)
        return CGSize(width: CGFloat(t.width) + 2 * CGFloat(margins.side),
                      height: CGFloat(t.height) + CGFloat(margins.side + margins.bottom))
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        metal.frame = bounds
        scroll.frame = bounds
        guard bounds.width > 0, bounds.height > bottomInset, bounds.size != fittedSize || insetChanged else { return }
        insetChanged = false
        let sheet = sheetSize
        let fit = min(bounds.width / sheet.width, (bounds.height - bottomInset) / sheet.height) * 0.96
        // A settle under way counts as fitted: the new fit takes its place.
        let wasFitted = fittedSize == .zero || settling != nil || abs(scroll.zoomScale - scroll.minimumZoomScale) < 0.001
        cancelSettling()
        let refitting = fittedSize != .zero
        fittedSize = bounds.size
        // Only into more room (the paint box put away, a turn): less, as the box is first
        // measured, is taken at once.
        let settles = wasFitted && refitting && fit > scroll.zoomScale && !reduceMotion
        // While settling, the old zoom stays allowed (a minimum above it would jump to it).
        scroll.minimumZoomScale = settles ? min(fit, scroll.zoomScale) : fit
        // Up to about eight screen points a canvas unit: close enough to watch a front creep.
        scroll.maximumZoomScale = max(fit * 4, 8)
        if wasFitted {
            // The paint box put away: the sheet settles into the room it leaves.
            if settles { settle(to: fit) } else { scroll.zoomScale = fit }
        }
        center()
        updateView()
        sharpenSignature()
    }

    private var settling: (link: CADisplayLink, from: CGFloat, to: CGFloat, start: CFTimeInterval)?

    /// Zooms to `zoom` over a moment, frame by frame, so the sheet the renderer draws follows
    /// (a UIView animation would move only the scroll view's presentation, not the sheet).
    private func settle(to zoom: CGFloat) {
        cancelSettling()
        let link = CADisplayLink(target: self, selector: #selector(settleStep(_:)))
        settling = (link, scroll.zoomScale, zoom, CACurrentMediaTime())
        link.add(to: .main, forMode: .common)
    }

    @objc private func settleStep(_ link: CADisplayLink) {
        guard let s = settling else { return link.invalidate() }
        let t = min(1, (CACurrentMediaTime() - s.start) / 0.6)
        let eased = t * t * (3 - 2 * t)
        scroll.zoomScale = s.from + (s.to - s.from) * eased
        center()
        updateView()
        if t >= 1 {
            link.invalidate()
            settling = nil
            scroll.minimumZoomScale = s.to
            sharpenSignature()
        }
    }

    /// Stops a settle where it stands (a new fit, or the painter's own pinch or pan).
    private func cancelSettling() {
        guard let s = settling else { return }
        s.link.invalidate()
        settling = nil
        scroll.minimumZoomScale = min(scroll.minimumZoomScale, scroll.zoomScale)
    }

    func scrollViewWillBeginZooming(_ scrollView: UIScrollView, with view: UIView?) {
        cancelSettling()
        cancelFlight()
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        cancelSettling()
        cancelFlight()
    }

    func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
        sharpenSignature()
    }

    /// The title at the left of the bottom margin, no wider than most of it, and the year at the
    /// right; each label only as large as its words, since it is drawn as sharp as the zoom.
    private func layOutSignature() {
        let b = signature.bounds
        let lift = b.height * 0.034
        for (i, label) in signature.subviews.enumerated() {
            label.sizeToFit()
            let width = min(label.bounds.width, b.width * 0.7)
            let x = i == 0 ? 0 : b.width - width
            label.frame = CGRect(x: x, y: (b.height - label.bounds.height) / 2 - lift, width: width, height: label.bounds.height)
        }
    }

    /// The pencil drawn at the pixels the zoom shows it at (a label is drawn once, at its scale).
    private func sharpenSignature() {
        let scale = min(12, max(2, scroll.zoomScale * traitCollection.displayScale))
        for label in signature.subviews where abs(label.contentScaleFactor - scale) > 0.5 {
            label.contentScaleFactor = scale
            label.setNeedsDisplay()
        }
    }

    /// Insets that keep the whole sheet in reach, and center it while it fits.
    private func center() {
        let zoom = scroll.zoomScale
        let margins = WatercolorRenderer.margins(of: renderer.painting.template)
        let side = CGFloat(margins.side) * zoom, bottom = CGFloat(margins.bottom) * zoom
        let sheet = CGSize(width: sheetSize.width * zoom, height: sheetSize.height * zoom)
        let x = max(0, (bounds.width - sheet.width) / 2)
        let y = max(0, (bounds.height - bottomInset - sheet.height) / 2)
        scroll.contentInset = UIEdgeInsets(top: y + side, left: x + side, bottom: y + bottom + bottomInset, right: x + side)
    }

    /// Signs a finished painting in pencil: its title at the left of the bottom margin and the
    /// era's year at the right, written in as the paint box goes, or there at once.
    func sign(_ signed: Bool, title: String, animated: Bool) {
        if signature.subviews.isEmpty, signed {
            let margins = WatercolorRenderer.margins(of: renderer.painting.template)
            let size = CGFloat(margins.bottom) * 0.34
            let base = UIFont.systemFont(ofSize: size, weight: .regular).fontDescriptor
            let descriptor = base.withDesign(.serif)?.withSymbolicTraits(.traitItalic) ?? base
            let font = UIFont(descriptor: descriptor, size: size)
            let pencil = UIColor(red: 0.44, green: 0.43, blue: 0.44, alpha: 0.9)
            for text in [title, EraClock.text(of: EraYear.watercolor)] {
                let label = UILabel()
                label.text = text
                label.font = font
                label.textColor = pencil
                label.lineBreakMode = .byTruncatingTail
                label.isAccessibilityElement = false
                signature.addSubview(label)
            }
            sharpenSignature()
        }
        if let written = signature.subviews.first as? UILabel, written.text != title { written.text = title }
        layOutSignature()
        let alpha: CGFloat = signed ? 1 : 0
        guard signature.alpha != alpha else { return }
        if animated && !reduceMotion {
            UIView.animate(withDuration: 1.4, delay: 0.5, options: [.curveEaseOut]) { self.signature.alpha = alpha }
        } else {
            signature.alpha = alpha
        }
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { page }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        center()
        updateView()
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) { updateView() }

    /// The renderer's view of the canvas: canvas units at the top-left pixel and per pixel.
    private func updateView() {
        let zoom = Float(scroll.zoomScale)
        let scale = Float(metal.contentScaleFactor)
        renderer.offset = SIMD2(Float(scroll.contentOffset.x), Float(scroll.contentOffset.y)) / zoom
        renderer.unitsPerPixel = 1 / (zoom * scale)
        metal.setNeedsDisplay()
    }

    /// A fingertip's reach in canvas units at the zoom.
    private var tolerance: Float { Float(Self.fingertip / max(scroll.zoomScale, 0.01)) }

    @objc private func tapped(_ recognizer: UITapGestureRecognizer) {
        cancelFlight()
        let p = recognizer.location(in: page)
        onTap?(SIMD2(Float(p.x), Float(p.y)), tolerance)
        setRunning(true)
    }

    /// The last point a drag reached, so the areas between two touches are laid too.
    private var lastDrag: CGPoint?

    @objc private func dragged(_ recognizer: UIPanGestureRecognizer) {
        let p = recognizer.location(in: page)
        switch recognizer.state {
        case .began:
            cancelFlight()
            lastDrag = p
            onStroke?(true)
            onDrag?(SIMD2(Float(p.x), Float(p.y)), tolerance)
        case .changed:
            // Every few canvas units along the way: a quick stroke skips no area.
            let from = lastDrag ?? p
            let length = hypot(p.x - from.x, p.y - from.y)
            let step = max(2, 4 / scroll.zoomScale)
            let n = max(1, Int((length / step).rounded(.up)))
            for k in 1...n {
                let t = CGFloat(k) / CGFloat(n)
                onDrag?(SIMD2(Float(from.x + (p.x - from.x) * t), Float(from.y + (p.y - from.y) * t)), 0)
            }
            lastDrag = p
        default:
            lastDrag = nil
            onStroke?(false)
        }
        setRunning(true)
    }

    /// Draws the sheet again while it is still (the paint in hand changed: its hatch moves).
    func redraw() { metal.setNeedsDisplay() }

    // MARK: Flying (Hint, Zen Mode)

    private var flight: (link: CADisplayLink, from: (zoom: CGFloat, center: CGPoint), to: (zoom: CGFloat, center: CGPoint),
                         start: CFTimeInterval, duration: Double)?

    /// Flies the sheet to show `area` (canvas units) at a zoom that makes a small one easy to
    /// tap, never further out than the fit (the main canvas's hint: `CanvasView`'s flights).
    /// Reduce Motion cuts there.
    func fly(to area: CGRect) {
        cancelSettling()
        cancelFlight()
        let visibleHeight = max(bounds.height - bottomInset, 1)
        // The area about a third of the view's short side, within the zoom's range.
        let side = max(area.width, area.height, 24)
        let wanted = min(bounds.width, visibleHeight) / 3 / side
        let zoom = min(max(wanted, scroll.minimumZoomScale, scroll.zoomScale * 0.75), scroll.maximumZoomScale)
        let target = (zoom: max(zoom, scroll.minimumZoomScale), center: CGPoint(x: area.midX, y: area.midY))
        let from = (zoom: scroll.zoomScale, center: visibleCenter)
        if reduceMotion {
            apply(zoom: target.zoom, center: target.center)
            return
        }
        let distance = hypot(target.center.x - from.center.x, target.center.y - from.center.y) * scroll.zoomScale
        let duration = min(0.9, 0.35 + Double(distance) / 2400)
        let link = CADisplayLink(target: self, selector: #selector(flightStep(_:)))
        flight = (link, from, target, CACurrentMediaTime(), duration)
        link.add(to: .main, forMode: .common)
    }

    /// The canvas point at the middle of the room above the paint box.
    private var visibleCenter: CGPoint {
        let zoom = scroll.zoomScale
        let visible = CGPoint(x: bounds.width / 2, y: (bounds.height - bottomInset) / 2)
        return CGPoint(x: (scroll.contentOffset.x + visible.x) / zoom, y: (scroll.contentOffset.y + visible.y) / zoom)
    }

    /// Zoom and offset that put canvas point `center` at the middle of the room above the box.
    private func apply(zoom: CGFloat, center c: CGPoint) {
        scroll.zoomScale = zoom
        center()
        let visible = CGPoint(x: bounds.width / 2, y: (bounds.height - bottomInset) / 2)
        let inset = scroll.contentInset
        let size = scroll.contentSize
        var offset = CGPoint(x: c.x * zoom - visible.x, y: c.y * zoom - visible.y)
        offset.x = min(max(offset.x, -inset.left), max(size.width + inset.right - bounds.width, -inset.left))
        offset.y = min(max(offset.y, -inset.top), max(size.height + inset.bottom - bounds.height, -inset.top))
        scroll.contentOffset = offset
        updateView()
    }

    @objc private func flightStep(_ link: CADisplayLink) {
        guard let f = flight else { return link.invalidate() }
        let t = min(1, (CACurrentMediaTime() - f.start) / f.duration)
        let e = t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
        // Zoom eased in log space, the center along a straight line: no swing past the target.
        let zoom = exp(log(f.from.zoom) + (log(f.to.zoom) - log(f.from.zoom)) * e)
        let c = CGPoint(x: f.from.center.x + (f.to.center.x - f.from.center.x) * e,
                        y: f.from.center.y + (f.to.center.y - f.from.center.y) * e)
        apply(zoom: zoom, center: c)
        if t >= 1 { cancelFlight() }
    }

    private func cancelFlight() {
        flight?.link.invalidate()
        flight = nil
    }

    /// Draws every frame while the sheet needs it, and only when asked otherwise.
    func setRunning(_ running: Bool) {
        // MTKView's own modes: its display link while running, drawing on request otherwise.
        if running && metal.isPaused {
            renderer.resume()
            metal.enableSetNeedsDisplay = false
            metal.isPaused = false
        } else if !running && !metal.isPaused {
            metal.isPaused = true
            metal.enableSetNeedsDisplay = true
        }
    }
}

/// `WatercolorCanvasView` in SwiftUI.
struct WatercolorCanvas: UIViewRepresentable {
    let renderer: WatercolorRenderer
    var bottomInset: CGFloat = 0
    /// Whether the painting is finished and signed.
    var signed = false
    var title = ""
    var reduceMotion = false
    /// An area to fly to (Hint, Zen Mode), and a count that moves each time it is asked.
    var flyTo: (area: CGRect, count: Int)?
    let onTap: (SIMD2<Float>, Float) -> Void
    let onDrag: (SIMD2<Float>, Float) -> Void

    /// The paint in hand: its areas are hatched, so a change draws the sheet again.
    var selected: Int?

    final class Coordinator {
        var flights = 0
        var selected: Int?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WatercolorCanvasView {
        let view = WatercolorCanvasView(renderer: renderer)
        view.onTap = onTap
        view.onDrag = onDrag
        view.onStroke = { [painting = renderer.painting] began in
            if began { painting.beginStroke() } else { painting.endStroke() }
        }
        view.reduceMotion = reduceMotion
        view.bottomInset = bottomInset
        view.sign(signed, title: title, animated: false)
        context.coordinator.flights = flyTo?.count ?? 0
        context.coordinator.selected = selected
        return view
    }

    func updateUIView(_ view: WatercolorCanvasView, context: Context) {
        view.onTap = onTap
        view.onDrag = onDrag
        view.reduceMotion = reduceMotion
        view.bottomInset = bottomInset
        view.sign(signed, title: title, animated: true)
        if selected != context.coordinator.selected {
            context.coordinator.selected = selected
            view.redraw()
        }
        if let flyTo, flyTo.count != context.coordinator.flights {
            context.coordinator.flights = flyTo.count
            view.fly(to: flyTo.area)
        }
    }
}
#endif
