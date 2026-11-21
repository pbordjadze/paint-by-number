#if UNRELEASED
import MetalKit
import PaintCore
import SwiftUI
import UIKit

/// The sheet on screen: an `MTKView` drawn by `WatercolorRenderer`, under an invisible scroll view
/// that gives the system's pan, pinch and deceleration (the main canvas's way, `CanvasView`). A
/// tap lays a wash where it lands; the view draws every frame only while the sheet is wet.
final class WatercolorCanvasView: UIView, UIScrollViewDelegate {
    let renderer: WatercolorRenderer
    private let metal: MTKView
    private let scroll = UIScrollView()
    private let page = UIView()
    private var fittedSize: CGSize = .zero
    var onTap: ((SIMD2<Float>) -> Void)?

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
        isAccessibilityElement = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        metal.frame = bounds
        scroll.frame = bounds
        guard bounds.width > 0, bounds.height > 0, bounds.size != fittedSize else { return }
        let t = renderer.painting.template
        let fit = min(bounds.width / CGFloat(t.width), bounds.height / CGFloat(t.height)) * 0.94
        let wasFitted = fittedSize == .zero || abs(scroll.zoomScale - scroll.minimumZoomScale) < 0.001
        fittedSize = bounds.size
        scroll.minimumZoomScale = fit
        // Up to about eight screen points a canvas unit: close enough to watch a front creep.
        scroll.maximumZoomScale = max(fit * 4, 8)
        if wasFitted { scroll.zoomScale = fit }
        center()
        updateView()
    }

    private func center() {
        let content = CGSize(width: page.frame.width, height: page.frame.height)
        let x = max(0, (bounds.width - content.width) / 2), y = max(0, (bounds.height - content.height) / 2)
        scroll.contentInset = UIEdgeInsets(top: y, left: x, bottom: y, right: x)
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
    let onTap: (SIMD2<Float>) -> Void

    func makeUIView(context: Context) -> WatercolorCanvasView {
        let view = WatercolorCanvasView(renderer: renderer)
        view.onTap = onTap
        return view
    }

    func updateUIView(_ view: WatercolorCanvasView, context: Context) {
        view.onTap = onTap
    }
}
#endif
