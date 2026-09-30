import CoreGraphics
import Foundation
import Metal
import PaintCore
import QuartzCore
import UIKit
import os
import simd

/// Where the canvas looks when it first lays out (demo scenarios, restored sessions).
struct CanvasCamera: Equatable {
    /// Zoom relative to "fit the whole canvas".
    var zoom: CGFloat
    /// Canvas point to centre in the visible area.
    var center: SIMD2<Float>
}

enum PencilAction { case tap, squeeze }

/// The painting surface: a `CAMetalLayer` driven by an invisible `UIScrollView` overlay so
/// pan, pinch, deceleration and rubber-banding are exactly the system's. Renders with a
/// display link only while something changes (gesture, deceleration, paint animation).
///
/// Gestures: tap paints (with tolerance), a quick second tap on something unpaintable zooms,
/// press-and-drag paints every matching region under the finger, Apple Pencil paints
/// directly while fingers navigate, and Pencil hover previews the region under the tip.
final class CanvasView: UIView, PaintingCanvas {
    override class var layerClass: AnyClass { CAMetalLayer.self }

    let session: PaintingSession
    /// Areas covered by floating chrome; the canvas fits inside and can scroll clear of them.
    var chromeInsets: UIEdgeInsets = .zero {
        didSet { if chromeInsets != oldValue { setNeedsLayout() } }
    }
    var showsNumbers = true {
        didSet { if showsNumbers != oldValue { numbersChanged() } }
    }
    var initialCamera: CanvasCamera?
    var onPencilAction: ((PencilAction) -> Void)?
    /// Scales fill animation durations (demo scenarios freeze a fill mid-way).
    var fillDurationScale: Float = 1

    private let template: Template
    private let scene: CanvasScene?
    private let renderer: CanvasRenderer?
    private let scrollView = UIScrollView()
    private let zoomView = UIView()
    private var displayLink: CADisplayLink?
    private let epoch = CACurrentMediaTime()

    // Render scheduling
    private var needsRender = true
    private var idleTicks = 0
    private var activeUntil: Float = 0
    private var lastCamera: Camera?

    // Visual state fed to the shaders (renderer clock, seconds)
    private var selectionTime: Float = -10_000
    private var pulseRegion = -1
    private var pulseStart: Float = -10_000
    private var bumpRegion = -1
    private var bumpStart: Float = -10_000
    private var hoverRegion = -1
    private var brushPoint: CGPoint?
    private var numbersFrom: Float = 1
    private var numbersTo: Float = 1
    private var numbersStart: Float = -10_000
    private var shineStart: Float = -10_000
    private var replayTask: Task<Void, Never>?
    private var isReplaying = false
    private var shineColor = -1

    // Camera
    private var fitZoom: CGFloat = 1
    private var laidOutSize: CGSize = .zero
    private var laidOutInsets: UIEdgeInsets = .zero
    private var cameraAnimation: CameraAnimation?
    private var isApplyingCamera = false

    // Gestures
    private var tapRecognizer: UITapGestureRecognizer!
    private var tapBeganWhileMoving = false
    private var tapWasFinger = false
    private var lastTap: (time: CFTimeInterval, point: CGPoint, painted: Bool)?
    private var dragLast: SIMD2<Float>?

    private static let margin: CGFloat = 16
    private static let tapTolerance: CGFloat = 14
    private static let brushRadius: CGFloat = 11

    private struct Camera: Equatable {
        var zoom: CGFloat
        var origin: CGPoint
    }

    private struct CameraAnimation {
        var fromZoom: CGFloat
        var toZoom: CGFloat
        var fromOffset: CGPoint
        var toOffset: CGPoint
        var start: CFTimeInterval
        var duration: CFTimeInterval
    }

    init(session: PaintingSession) {
        self.session = session
        template = session.template
        let context = RenderContext.shared
        let scene = context.flatMap { CanvasScene(template: session.template, context: $0) }
        self.scene = scene
        if let context, let scene {
            renderer = CanvasRenderer(
                scene: scene, context: context,
                states: CanvasView.settledStates(template: session.template, progress: session.progress))
        } else {
            renderer = nil
        }
        super.init(frame: .zero)
        configureLayer(device: context?.device)
        configureScrollView()
        configureGestures()
        isAccessibilityElement = true
        accessibilityLabel = String(localized: "Canvas")
        accessibilityTraits = .allowsDirectInteraction
        registerForTraitChanges([UITraitUserInterfaceStyle.self], action: #selector(appearanceChanged))
        session.canvas = self
        session.onEvent { [weak self] event in self?.celebrate(event) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private var metalLayer: CAMetalLayer { layer as! CAMetalLayer }

    private static func settledStates(template: Template, progress: PaintProgress) -> [RegionState] {
        template.regions.indices.map { i in
            RegionState.settled(painted: progress.isPainted(i), origin: labelPosition(template, i), seed: Float(i % 61) * 0.73)
        }
    }

    private static func labelPosition(_ template: Template, _ region: Int) -> SIMD2<Float> {
        if let label = template.labels(ofRegion: region).first { return label.position }
        let b = template.regions[region].bounds
        return SIMD2(Float(b.minX + b.maxX) / 2, Float(b.minY + b.maxY) / 2)
    }

    // MARK: Setup

    private func configureLayer(device: (any MTLDevice)?) {
        let layer = metalLayer
        layer.device = device
        layer.pixelFormat = RenderContext.colorFormat
        layer.framebufferOnly = true
        layer.colorspace = CGColorSpace(name: CGColorSpace.displayP3)
        layer.maximumDrawableCount = 3
        layer.presentsWithTransaction = false
        layer.isOpaque = true
        backgroundColor = .systemGroupedBackground
    }

    private func configureScrollView() {
        scrollView.delegate = self
        scrollView.backgroundColor = .clear
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.alwaysBounceHorizontal = true
        scrollView.alwaysBounceVertical = true
        scrollView.bouncesZoom = true
        scrollView.delaysContentTouches = false
        scrollView.scrollsToTop = false
        zoomView.frame = CGRect(x: 0, y: 0, width: template.width, height: template.height)
        zoomView.isUserInteractionEnabled = false
        scrollView.addSubview(zoomView)
        scrollView.contentSize = zoomView.bounds.size
        addSubview(scrollView)
    }

    private static let fingerTouches = [
        NSNumber(value: UITouch.TouchType.direct.rawValue),
        NSNumber(value: UITouch.TouchType.indirectPointer.rawValue),
    ]

    private func configureGestures() {
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        tap.allowedTouchTypes = Self.fingerTouches
        tap.delegate = self
        scrollView.addGestureRecognizer(tap)
        tapRecognizer = tap

        let press = UILongPressGestureRecognizer(target: self, action: #selector(handleDragPaint(_:)))
        press.minimumPressDuration = 0.28
        press.allowableMovement = 12
        press.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        scrollView.addGestureRecognizer(press)

        let pencil = UILongPressGestureRecognizer(target: self, action: #selector(handlePencil(_:)))
        pencil.minimumPressDuration = 0
        pencil.allowableMovement = .greatestFiniteMagnitude
        pencil.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.pencil.rawValue)]
        scrollView.addGestureRecognizer(pencil)

        scrollView.addGestureRecognizer(UIHoverGestureRecognizer(target: self, action: #selector(handleHover(_:))))
        addInteraction(UIPencilInteraction(delegate: self))
    }

    /// Fingers navigate; the Pencil paints.
    private func restrictNavigationToFingers() {
        scrollView.panGestureRecognizer.allowedTouchTypes = Self.fingerTouches
            + [NSNumber(value: UITouch.TouchType.indirect.rawValue)]
        scrollView.pinchGestureRecognizer?.allowedTouchTypes = Self.fingerTouches
    }

    // MARK: Lifecycle

    override var canBecomeFirstResponder: Bool { true }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            if displayLink == nil {
                let link = CADisplayLink(target: DisplayLinkTarget(self), selector: #selector(DisplayLinkTarget.tick(_:)))
                link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
                link.add(to: .main, forMode: .common)
                displayLink = link
            }
            setNeedsLayout()
            requestRender()
            // First responder so the window's undo manager serves three-finger undo and ⌘Z.
            Task { self.becomeFirstResponder() }
        } else {
            displayLink?.invalidate()
            displayLink = nil
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let scale = traitCollection.displayScale > 0 ? traitCollection.displayScale : 2
        if contentScaleFactor != scale { contentScaleFactor = scale }
        let drawable = CGSize(width: (bounds.width * scale).rounded(), height: (bounds.height * scale).rounded())
        if metalLayer.drawableSize != drawable { metalLayer.drawableSize = drawable }
        if scrollView.frame != bounds { scrollView.frame = bounds }
        guard bounds.width > 1, bounds.height > 1 else { return }
        guard bounds.size != laidOutSize || chromeInsets != laidOutInsets else { return }

        // Keep looking at the same place across rotation / chrome changes.
        let relative: CGFloat
        let center: SIMD2<Float>
        if laidOutSize != .zero {
            relative = scrollView.zoomScale / fitZoom
            let old = CGRect(origin: .zero, size: laidOutSize).inset(by: laidOutInsets)
            center = canvasPoint(forView: CGPoint(x: old.midX, y: old.midY))
        } else if let initial = initialCamera {
            relative = initial.zoom
            center = initial.center
        } else {
            relative = 1
            center = SIMD2(Float(template.width), Float(template.height)) / 2
        }
        laidOutSize = bounds.size
        laidOutInsets = chromeInsets
        updateZoomLimits()
        restrictNavigationToFingers()
        let z = clampZoom(fitZoom * relative)
        cameraAnimation = nil
        apply(zoom: z, offset: offset(centering: center, zoom: z))
    }

    @objc private func appearanceChanged() {
        requestRender()
    }

    // MARK: Camera

    private func updateZoomLimits() {
        let avail = bounds.inset(by: chromeInsets).insetBy(dx: Self.margin, dy: Self.margin)
        let fit = max(1e-3, min(avail.width / CGFloat(template.width), avail.height / CGFloat(template.height)))
        fitZoom = fit
        // Deep enough that small numbers read comfortably, never absurd.
        let legible = 15 / CGFloat(max(scene?.smallLabelSize ?? 4, 0.25))
        scrollView.minimumZoomScale = fit
        scrollView.maximumZoomScale = min(max(legible, fit * 4), fit * 40)
    }

    private func clampZoom(_ z: CGFloat) -> CGFloat {
        min(max(z, scrollView.minimumZoomScale), scrollView.maximumZoomScale)
    }

    /// Content insets that centre the canvas when it is smaller than the visible area.
    private func insets(forZoom z: CGFloat) -> UIEdgeInsets {
        let avail = bounds.inset(by: chromeInsets).insetBy(dx: Self.margin, dy: Self.margin)
        let w = CGFloat(template.width) * z, h = CGFloat(template.height) * z
        let ex = max(0, (avail.width - w) / 2), ey = max(0, (avail.height - h) / 2)
        return UIEdgeInsets(
            top: chromeInsets.top + Self.margin + ey, left: chromeInsets.left + Self.margin + ex,
            bottom: chromeInsets.bottom + Self.margin + ey, right: chromeInsets.right + Self.margin + ex)
    }

    private func clampedOffset(_ o: CGPoint, zoom z: CGFloat) -> CGPoint {
        let ins = insets(forZoom: z)
        let w = CGFloat(template.width) * z, h = CGFloat(template.height) * z
        let minX = -ins.left, maxX = max(minX, w + ins.right - bounds.width)
        let minY = -ins.top, maxY = max(minY, h + ins.bottom - bounds.height)
        return CGPoint(x: min(max(o.x, minX), maxX), y: min(max(o.y, minY), maxY))
    }

    /// Content offset that shows canvas point `c` in the middle of the visible area.
    private func offset(centering c: SIMD2<Float>, zoom z: CGFloat) -> CGPoint {
        let avail = bounds.inset(by: chromeInsets)
        return clampedOffset(CGPoint(x: CGFloat(c.x) * z - avail.midX, y: CGFloat(c.y) * z - avail.midY), zoom: z)
    }

    private func apply(zoom z: CGFloat, offset o: CGPoint) {
        isApplyingCamera = true
        if scrollView.zoomScale != z { scrollView.zoomScale = z }
        scrollView.contentInset = insets(forZoom: z)
        scrollView.contentOffset = o
        isApplyingCamera = false
        requestRender()
    }

    private func animateCamera(zoom: CGFloat, offset: CGPoint, duration: CFTimeInterval) {
        if UIAccessibility.isReduceMotionEnabled {
            cameraAnimation = nil
            apply(zoom: zoom, offset: offset)
            return
        }
        cameraAnimation = CameraAnimation(
            fromZoom: scrollView.zoomScale, toZoom: zoom, fromOffset: scrollView.contentOffset, toOffset: offset,
            start: CACurrentMediaTime(), duration: duration)
        requestRender()
    }

    private func stepCameraAnimation(at time: CFTimeInterval) {
        guard let a = cameraAnimation else { return }
        let t = min(1, max(0, (time - a.start) / a.duration))
        let e = CGFloat(1 - pow(1 - t, 3))
        let z = a.fromZoom * pow(a.toZoom / a.fromZoom, e)
        var o: CGPoint
        if abs(a.toZoom - a.fromZoom) < a.fromZoom * 1e-4 {
            o = CGPoint(x: a.fromOffset.x + (a.toOffset.x - a.fromOffset.x) * e,
                        y: a.fromOffset.y + (a.toOffset.y - a.fromOffset.y) * e)
        } else {
            // Scale about the fixed point of the start→end similarity: one continuous motion.
            let cx = (a.toOffset.x - a.fromOffset.x) / (a.toZoom - a.fromZoom)
            let cy = (a.toOffset.y - a.fromOffset.y) / (a.toZoom - a.fromZoom)
            let fx = cx * a.fromZoom - a.fromOffset.x, fy = cy * a.fromZoom - a.fromOffset.y
            o = CGPoint(x: cx * z - fx, y: cy * z - fy)
        }
        if t >= 1 {
            o = a.toOffset
            cameraAnimation = nil
        }
        apply(zoom: t >= 1 ? a.toZoom : z, offset: o)
    }

    /// The current view transform (view = origin + canvas · zoom). Reads presentation values
    /// only while UIKit animates the scroll view (e.g. zoom bounce), so ordinary scrolling
    /// never lags a frame behind the model values.
    private func currentCamera() -> Camera {
        let zl = zoomView.layer, sl = scrollView.layer
        let animating = !(zl.animationKeys()?.isEmpty ?? true) || !(sl.animationKeys()?.isEmpty ?? true)
        let z = animating ? (zl.presentation() ?? zl) : zl
        let s = animating ? (sl.presentation() ?? sl) : sl
        let scale = z.transform.m11
        let size = z.bounds.size
        return Camera(
            zoom: scale,
            origin: CGPoint(
                x: z.position.x - z.anchorPoint.x * size.width * scale - s.bounds.origin.x,
                y: z.position.y - z.anchorPoint.y * size.height * scale - s.bounds.origin.y))
    }

    private func canvasPoint(forView p: CGPoint) -> SIMD2<Float> {
        let c = currentCamera()
        return SIMD2(Float((p.x - c.origin.x) / c.zoom), Float((p.y - c.origin.y) / c.zoom))
    }

    private func canvasPoint(_ zoomViewPoint: CGPoint) -> SIMD2<Float> {
        SIMD2(Float(zoomViewPoint.x), Float(zoomViewPoint.y))
    }

    /// Canvas point at the middle of the visible area.
    var visibleCenter: SIMD2<Float> {
        let avail = bounds.inset(by: chromeInsets)
        return canvasPoint(forView: CGPoint(x: avail.midX, y: avail.midY))
    }

    func zoomToFit(animated: Bool = true) {
        let center = SIMD2(Float(template.width), Float(template.height)) / 2
        let target = offset(centering: center, zoom: fitZoom)
        if animated {
            animateCamera(zoom: fitZoom, offset: target, duration: 0.5)
        } else {
            apply(zoom: fitZoom, offset: target)
        }
    }

    /// Keyboard zoom about the middle of the visible area.
    func zoom(by factor: CGFloat) {
        let avail = bounds.inset(by: chromeInsets)
        let anchor = CGPoint(x: avail.midX, y: avail.midY)
        let target = clampZoom(scrollView.zoomScale * factor)
        let c = canvasPoint(forView: anchor)
        let o = clampedOffset(CGPoint(x: CGFloat(c.x) * target - anchor.x, y: CGFloat(c.y) * target - anchor.y), zoom: target)
        animateCamera(zoom: target, offset: o, duration: 0.3)
    }

    /// Double-tap: zoom in around the point, or back out to fit when already deep.
    private func zoomStep(at view: CGPoint) {
        let z = scrollView.zoomScale, maxZ = scrollView.maximumZoomScale
        if z > maxZ * 0.8 {
            zoomToFit()
            return
        }
        let target = clampZoom(max(z * 2.5, fitZoom * 2.5))
        let c = canvasPoint(forView: view)
        let o = clampedOffset(CGPoint(x: CGFloat(c.x) * target - view.x, y: CGFloat(c.y) * target - view.y), zoom: target)
        animateCamera(zoom: target, offset: o, duration: 0.42)
    }

    /// Reveals a region: zoom until its number reads comfortably (without overflowing the
    /// view), centre it, then pulse it.
    func reveal(region: Int) {
        let r = template.regions[region]
        let center = Self.labelPosition(template, region)
        let labelSize = CGFloat(max(scene?.labelSizes[region] ?? 8, 0.5))
        let extent = CGFloat(max(r.bounds.width, r.bounds.height, 1))
        let avail = bounds.inset(by: chromeInsets)
        let legible = 17 / labelSize
        let roomy = 0.45 * min(avail.width, avail.height) / extent
        // Always fly in a little so the eye follows to the spot, but never past a view-filling region.
        let z = clampZoom(max(scrollView.zoomScale, min(roomy, max(legible, fitZoom * 2))))
        animateCamera(zoom: z, offset: offset(centering: center, zoom: z), duration: 0.55)
        pulseRegion = region
        pulseStart = now() + 0.4
        activeUntil = max(activeUntil, pulseStart + 2.1)
    }

    /// Asks the session for a hint near what the user is looking at.
    func showHint() {
        session.showHint(near: visibleCenter)
    }

    // MARK: Rendering

    private func now() -> Float { Float(CACurrentMediaTime() - epoch) }

    func requestRender() {
        needsRender = true
        idleTicks = 0
        displayLink?.isPaused = false
    }

    fileprivate func tick(_ link: CADisplayLink) {
        stepCameraAnimation(at: CACurrentMediaTime())
        let time = Float(link.targetTimestamp - epoch)
        let camera = currentCamera()
        let moving = scrollView.isTracking || scrollView.isDecelerating || scrollView.isZooming
            || scrollView.isZoomBouncing || cameraAnimation != nil
            || !(zoomView.layer.animationKeys()?.isEmpty ?? true) || !(scrollView.layer.animationKeys()?.isEmpty ?? true)
        guard needsRender || moving || time < activeUntil || camera != lastCamera else {
            idleTicks += 1
            if idleTicks > 3 { link.isPaused = true }
            return
        }
        idleTicks = 0
        guard let renderer else { return }
        let palette = CanvasPalette.appearance(dark: traitCollection.userInterfaceStyle == .dark)
        let uniforms = makeUniforms(time: time, camera: camera, palette: palette)
        let content = RenderContext.Content(
            outlines: true, numbers: true, brush: brushPoint != nil,
            shadowMargin: Float(44 * contentScaleFactor),
            clear: MTLClearColor(
                red: Double(palette.background.x), green: Double(palette.background.y),
                blue: Double(palette.background.z), alpha: 1))
        if renderer.draw(in: metalLayer, uniforms: uniforms, content: content) {
            needsRender = false
            lastCamera = camera
            framesRendered += 1
            skippedFrames = 0
        } else {
            skippedFrames += 1
            if skippedFrames == 120 { Self.log.error("canvas: no frame produced for 120 ticks") }
        }
    }

    /// Frames presented so far (diagnostics and tests).
    private(set) var framesRendered = 0
    private var skippedFrames = 0
    private static let log = Logger(subsystem: "com.pbordjadze.paintbynumber", category: "canvas")

    /// The paint state the shaders currently see for a region (tests).
    func regionState(_ region: Int) -> RegionState? { renderer?.states[region] }

    private func makeUniforms(time: Float, camera: Camera, palette: CanvasPalette) -> CanvasUniforms {
        let s = Float(contentScaleFactor)
        var u = CanvasUniforms()
        u.transform = SIMD4(Float(camera.origin.x) * s, Float(camera.origin.y) * s, Float(camera.zoom) * s, s)
        u.viewport = SIMD4(
            Float(metalLayer.drawableSize.width), Float(metalLayer.drawableSize.height),
            Float(template.width), Float(template.height))
        u.background = SIMD4(palette.background, 1)
        u.paper = SIMD4(palette.paper, palette.shadowOpacity)
        // Line art gets finer and lighter when zoomed out, where regions are small on screen.
        let depth = Float(log2(max(camera.zoom / fitZoom, 1)))
        let widthPt = min(1.0, 0.5 + 0.22 * depth)
        u.ink = SIMD4(palette.ink, palette.outlineOpacity * min(1, 0.7 + 0.15 * depth))
        let selected = session.selectedColor
        if let selected, let scene, selected < scene.paletteLinear.count {
            u.selected = SIMD4(scene.paletteLinear[selected], 1)
        }
        u.outline = SIMD4(widthPt * s, (widthPt + 0.55) * s, 1, numbersVisibility(at: time))
        u.labels = SIMD4(6.5 * s, 8.5 * s, 22 * s, 16 * s)
        u.numbers = SIMD4(0.5, 0.9, 0.05, 0)
        u.time = SIMD4(time, selectionTime, pulseStart, bumpStart)
        if let brushPoint {
            u.brush = SIMD4(Float(brushPoint.x) * s, Float(brushPoint.y) * s, Float(Self.brushRadius) * s, 1)
        }
        u.shine = SIMD4(shineStart, Float(shineColor), 0, 0)
        u.ids = SIMD4(Int32(selected ?? -1), Int32(hoverRegion), Int32(pulseRegion), Int32(bumpRegion))
        return u
    }

    private func numbersChanged() {
        let t = now()
        numbersFrom = numbersVisibility(at: t)
        numbersTo = showsNumbers && !isReplaying ? 1 : 0
        numbersStart = t
        activeUntil = max(activeUntil, t + 0.3)
        requestRender()
    }

    private func numbersVisibility(at t: Float) -> Float {
        let k = min(max((t - numbersStart) / 0.25, 0), 1)
        return numbersFrom + (numbersTo - numbersFrom) * k * k * (3 - 2 * k)
    }

    /// Replays the painting: the paint lifts off, then every region fills again in the order
    /// it was painted, all scheduled at once so the GPU animates it without per-frame work.
    func replay() {
        guard let renderer, !session.progress.log.isEmpty else { return }
        replayTask?.cancel()
        isReplaying = true
        numbersChanged()
        zoomToFit()
        let painted = session.progress.log.map { Int($0.region) }
        let lift: Float = 0.45
        let time = now()
        for r in painted {
            renderer.update(r, RegionState(
                origin: Self.labelPosition(template, r), start: time, duration: lift, radius: 0, painted: 0,
                seed: Float(r % 61) * 0.73))
        }
        activeUntil = max(activeUntil, time + lift)
        requestRender()
        replayTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Double(lift) + 0.25))
            guard let self, !Task.isCancelled else { return }
            // About 7 s for a typical painting, never a slog for a large one.
            let span = min(10, max(4, Float(painted.count) * 0.02))
            let step = span / Float(painted.count)
            let begin = now()
            for (i, r) in painted.enumerated() {
                let origin = Self.labelPosition(template, r)
                renderer.update(r, RegionState(
                    origin: origin, start: begin + Float(i) * step, duration: 0.5,
                    radius: farthestDistance(from: origin, in: template.regions[r].bounds), painted: 1,
                    seed: Float(r % 61) * 0.73))
            }
            activeUntil = max(activeUntil, begin + span + 1.5)
            requestRender()
            try? await Task.sleep(for: .seconds(Double(span) + 0.4))
            guard !Task.isCancelled else { return }
            isReplaying = false
            numbersChanged()
            celebrate(.artworkCompleted)
        }
    }

    /// Finishing a color sweeps a gloss over it once its last fill has landed; finishing the
    /// painting sweeps the whole canvas.
    private func celebrate(_ event: PaintEvent) {
        let delay: Float
        switch event {
        case let .colorCompleted(color):
            shineColor = color
            delay = 0.35
        case .artworkCompleted:
            shineColor = -1
            delay = 0.6
        default:
            return
        }
        shineStart = now() + delay
        activeUntil = max(activeUntil, shineStart + 1.2)
        requestRender()
    }

    private func bump(_ region: Int) {
        bumpRegion = region
        bumpStart = now()
        activeUntil = max(activeUntil, bumpStart + 1.5)
        requestRender()
    }

    // MARK: PaintingCanvas

    func session(_ session: PaintingSession, didPaint regions: [Int], from origin: SIMD2<Float>, animated: Bool) {
        guard let renderer else { return }
        let time = now()
        let zoom = Float(scrollView.zoomScale)
        var longest: Float = 0
        for r in regions {
            let seed = Float(r % 61) * 0.73
            guard animated else {
                renderer.update(r, .settled(painted: true, origin: Self.labelPosition(template, r), seed: seed))
                continue
            }
            let start = paintOrigin(for: r, near: origin)
            let radius = farthestDistance(from: start, in: template.regions[r].bounds)
            // Bigger on screen → a little longer, so every fill reads as one smooth stroke.
            let duration = min(0.6, max(0.25, 0.2 + radius * zoom / 700)) * fillDurationScale
            renderer.update(r, RegionState(origin: start, start: time, duration: duration, radius: radius, painted: 1, seed: seed))
            longest = max(longest, duration)
        }
        if animated { FeedbackEngine.shared.fillDuration = TimeInterval(longest) }
        activeUntil = max(activeUntil, time + longest + 0.75)
        if hoverRegion >= 0 && session.isPainted(hoverRegion) { hoverRegion = -1 }
        requestRender()
    }

    func session(_ session: PaintingSession, didUnpaint regions: [Int]) {
        guard let renderer else { return }
        let time = now()
        for r in regions {
            renderer.update(r, RegionState(
                origin: Self.labelPosition(template, r), start: time, duration: 0.25, radius: 0, painted: 0,
                seed: Float(r % 61) * 0.73))
        }
        activeUntil = max(activeUntil, time + 0.3)
        requestRender()
    }

    func sessionDidChangeSelection(_ session: PaintingSession) {
        selectionTime = now()
        hoverRegion = -1
        activeUntil = max(activeUntil, selectionTime + 2)
        requestRender()
    }

    func session(_ session: PaintingSession, focusOn region: Int) {
        reveal(region: region)
    }

    /// Paint spreads from the touch; when the touch is outside the region (tolerance, drag
    /// brush), start from the region's nearest point instead.
    private func paintOrigin(for region: Int, near p: SIMD2<Float>) -> SIMD2<Float> {
        if template.region(at: p) == region { return p }
        let map = template.regionMap
        let b = template.regions[region].bounds
        let reach = 48
        let cx = Int(p.x), cy = Int(p.y)
        let x0 = max(Int(b.minX), cx - reach), x1 = min(Int(b.maxX) - 1, cx + reach)
        let y0 = max(Int(b.minY), cy - reach), y1 = min(Int(b.maxY) - 1, cy + reach)
        var best: SIMD2<Float>?
        var bestDistance = Float.infinity
        if x0 <= x1 && y0 <= y1 {
            let target = UInt32(region)
            for y in y0...y1 {
                for x in x0...x1 where map[x, y] == target {
                    let q = SIMD2(Float(x) + 0.5, Float(y) + 0.5)
                    let d = simd_distance_squared(q, p)
                    if d < bestDistance { bestDistance = d; best = q }
                }
            }
        }
        return best ?? Self.labelPosition(template, region)
    }

    private func farthestDistance(from p: SIMD2<Float>, in b: PixelBounds) -> Float {
        let xs = [Float(b.minX), Float(b.maxX)], ys = [Float(b.minY), Float(b.maxY)]
        var d: Float = 1
        for x in xs { for y in ys { d = max(d, simd_distance(p, SIMD2(x, y))) } }
        return d
    }

    // MARK: Gestures

    @objc private func handleTap(_ g: UITapGestureRecognizer) {
        guard g.state == .ended, !tapBeganWhileMoving else { return }
        let view = g.location(in: self)
        let p = canvasPoint(g.location(in: zoomView))
        let t = CACurrentMediaTime()
        if let last = lastTap, t - last.time < 0.3, hypot(last.point.x - view.x, last.point.y - view.y) < 40, !last.painted {
            lastTap = nil
            zoomStep(at: view)
            return
        }
        // "Only Draw with Apple Pencil": fingers navigate (double-tap still zooms), pointers paint.
        if tapWasFinger && UIPencilInteraction.prefersPencilOnlyDrawing {
            lastTap = (t, view, false)
            return
        }
        let event = session.tap(at: p, tolerance: Float(Self.tapTolerance / scrollView.zoomScale))
        var painted = false
        switch event {
        case .painted?: painted = true
        case let .rejected(region, _)?: bump(region)
        default: break
        }
        lastTap = (t, view, painted)
    }

    @objc private func handleDragPaint(_ g: UILongPressGestureRecognizer) {
        guard !UIPencilInteraction.prefersPencilOnlyDrawing else { return }
        let p = canvasPoint(g.location(in: zoomView))
        let radius = Float(Self.brushRadius / scrollView.zoomScale)
        switch g.state {
        case .began:
            FeedbackEngine.shared.selectionChanged()
            brushPoint = g.location(in: self)
            dragLast = p
            session.drag(from: p, to: p, radius: radius)
        case .changed:
            brushPoint = g.location(in: self)
            if let last = dragLast { session.drag(from: last, to: p, radius: radius) }
            dragLast = p
        default:
            brushPoint = nil
            dragLast = nil
        }
        requestRender()
    }

    @objc private func handlePencil(_ g: UILongPressGestureRecognizer) {
        let p = canvasPoint(g.location(in: zoomView))
        switch g.state {
        case .began:
            dragLast = p
            if case let .rejected(region, _)? = session.tap(at: p, tolerance: Float(6 / scrollView.zoomScale)) {
                bump(region)
            }
        case .changed:
            if let last = dragLast { session.drag(from: last, to: p, radius: Float(4 / scrollView.zoomScale)) }
            dragLast = p
        default:
            dragLast = nil
        }
    }

    @objc private func handleHover(_ g: UIHoverGestureRecognizer) {
        var region = -1
        if g.state == .began || g.state == .changed {
            let p = canvasPoint(g.location(in: zoomView))
            if let r = template.region(at: p), !session.isPainted(r), session.colorOf(r) == session.selectedColor {
                region = r
            }
        }
        if region != hoverRegion {
            hoverRegion = region
            requestRender()
        }
    }
}

// MARK: - Delegates

extension CanvasView: UIScrollViewDelegate {
    func viewForZooming(in scrollView: UIScrollView) -> UIView? { zoomView }

    func scrollViewDidScroll(_ scrollView: UIScrollView) { requestRender() }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        if !isApplyingCamera { scrollView.contentInset = insets(forZoom: scrollView.zoomScale) }
        requestRender()
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) { cameraAnimation = nil }

    func scrollViewWillBeginZooming(_ scrollView: UIScrollView, with view: UIView?) { cameraAnimation = nil }
}

extension CanvasView: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        if gestureRecognizer === tapRecognizer {
            // A tap that stops a fling (or a camera flight) only stops it.
            tapBeganWhileMoving = scrollView.isDecelerating || cameraAnimation != nil
            tapWasFinger = touch.type == .direct
            cameraAnimation = nil
        }
        return true
    }
}

extension CanvasView: UIPencilInteractionDelegate {
    // Honour the Apple Pencil settings: either gesture may be turned off there.
    func pencilInteraction(_ interaction: UIPencilInteraction, didReceiveTap tap: UIPencilInteraction.Tap) {
        guard UIPencilInteraction.preferredTapAction != .ignore else { return }
        onPencilAction?(.tap)
    }

    func pencilInteraction(_ interaction: UIPencilInteraction, didReceiveSqueeze squeeze: UIPencilInteraction.Squeeze) {
        guard squeeze.phase == .ended, UIPencilInteraction.preferredSqueezeAction != .ignore else { return }
        onPencilAction?(.squeeze)
    }
}

/// Breaks the display link → view retain cycle.
private final class DisplayLinkTarget: NSObject {
    weak var view: CanvasView?

    init(_ view: CanvasView) { self.view = view }

    @objc func tick(_ link: CADisplayLink) { view?.tick(link) }
}
