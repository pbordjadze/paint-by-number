#if UNRELEASED
import MetalKit
import PaintCore
import Ravenna
import SwiftUI
import UIKit

/// The sheet on screen: an `MTKView` drawn by `WatercolorRenderer`, under an invisible scroll view
/// that gives the system's pan, pinch and deceleration (the main canvas's way, `CanvasView`). A
/// tap lays a wash where it lands; the view draws every frame only while the sheet is wet. The
/// sheet is the canvas and its paper margins, fitted above `bottomInset` (the paint box lying over
/// the desk); finished, it is signed in pencil in its bottom margin (`signed`).
final class WatercolorCanvasView: UIView, UIScrollViewDelegate {
    let renderer: WatercolorRenderer
    private let metal: MTKView
    private let scroll = UIScrollView()
    private let page = UIView()
    private let signature = UIView()
    private var fittedSize: CGSize = .zero
    var onTap: ((SIMD2<Float>) -> Void)?
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
        renderer.onActivity = { [weak self] active in self?.setRunning(active) }
        // A wash laid any other way (VoiceOver's action, a demo) wakes the sheet too.
        renderer.painting.onTap = { [weak self] in self?.setRunning(true) }
        isAccessibilityElement = false
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
        let wasFitted = fittedSize == .zero || abs(scroll.zoomScale - scroll.minimumZoomScale) < 0.001
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
    }

    private var settling: (link: CADisplayLink, from: CGFloat, to: CGFloat, start: CFTimeInterval)?

    /// Zooms to `zoom` over a moment, frame by frame, so the sheet the renderer draws follows
    /// (a UIView animation would move only the scroll view's presentation, not the sheet).
    private func settle(to zoom: CGFloat) {
        settling?.link.invalidate()
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
            let b = signature.bounds
            let frames = [CGRect(x: 0, y: 0, width: b.width * 0.7, height: b.height),
                          CGRect(x: b.width * 0.75, y: 0, width: b.width * 0.25, height: b.height)]
            let texts = [(title, NSTextAlignment.left), (EraClock.text(of: EraYear.watercolor), .right)]
            for ((text, alignment), frame) in zip(texts, frames) {
                let label = UILabel(frame: frame.offsetBy(dx: 0, dy: -size * 0.1))
                label.text = text
                label.font = font
                label.textColor = pencil
                label.textAlignment = alignment
                label.lineBreakMode = .byTruncatingTail
                // Drawn sharp enough to zoom into, as the sheet is.
                label.contentScaleFactor = 4
                label.isAccessibilityElement = false
                signature.addSubview(label)
            }
        }
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

    @objc private func tapped(_ recognizer: UITapGestureRecognizer) {
        let p = recognizer.location(in: page)
        onTap?(SIMD2(Float(p.x), Float(p.y)))
        setRunning(true)
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
    let onTap: (SIMD2<Float>) -> Void

    func makeUIView(context: Context) -> WatercolorCanvasView {
        let view = WatercolorCanvasView(renderer: renderer)
        view.onTap = onTap
        view.reduceMotion = reduceMotion
        view.bottomInset = bottomInset
        view.sign(signed, title: title, animated: false)
        return view
    }

    func updateUIView(_ view: WatercolorCanvasView, context: Context) {
        view.onTap = onTap
        view.reduceMotion = reduceMotion
        view.bottomInset = bottomInset
        view.sign(signed, title: title, animated: true)
    }
}
#endif
