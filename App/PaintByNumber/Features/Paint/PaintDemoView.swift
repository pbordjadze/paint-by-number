import PaintCore
import SwiftUI
import os
import simd

/// Demo scenarios for the painting screen, deterministic for CI screenshots. The template is
/// generated from a bundled photo (append `-mosaic` for the synthetic test template):
///
/// - `paint`: fresh canvas, fit to screen
/// - `paint-progress`: ~55 % painted color by color, the color in progress selected
/// - `paint-zoom`: zoomed ~4× into the canvas, numbers and highlight visible
/// - `paint-complete`: finished painting (line art dissolved)
/// - `paint-dark`: `paint-progress` for dark appearance
/// - `paint-fill`: fills frozen mid-animation to inspect the paint front
/// - `paint-hint`: the hint flies the camera to a region of the selected color
/// - `paint-replay`: a finished painting mid-replay
struct PaintDemoView: View {
    let scenario: String
    @State private var demo: Demo?

    init(scenario: String) {
        self.scenario = scenario
    }

    var body: some View {
        ZStack {
            if let demo {
                PaintView(
                    session: demo.session, title: demo.title, onClose: {},
                    initialCamera: demo.camera, fillDurationScale: demo.fillDurationScale)
                    .task {
                        await demo.run()
                        DemoMode.markReady()
                    }
            } else {
                Color(uiColor: .systemGroupedBackground).ignoresSafeArea()
                ProgressView()
            }
        }
        .task {
            let synthetic = scenario.hasSuffix("-mosaic")
            let base = synthetic ? String(scenario.dropLast("-mosaic".count)) : scenario
            var template: Template?
            if !synthetic { template = await Self.template(photo: "parrots") }
            demo = Demo(scenario: base, template: template ?? SyntheticTemplate.make(), title: template == nil ? "Mosaic" : "Parrots")
        }
    }

    @concurrent
    private static func template(photo: String) async -> Template? {
        guard let url = Bundle.main.url(forResource: photo, withExtension: "jpg"),
              let image = try? PhotoLoader.load(url: url, maxPixelSize: 2048),
              let output = try? TemplateGenerator().generate(from: image)
        else { return nil }
        return output.template.mesh.indices.isEmpty ? nil : output.template
    }
}

@MainActor
private final class Demo {
    let session: PaintingSession
    let title: String
    var camera: CanvasCamera?
    var fillDurationScale: Float = 1
    private let scenario: String

    init(scenario: String, template t: Template, title: String) {
        self.scenario = scenario
        self.title = title
        session = PaintingSession(template: t)

        // Paint colors in palette order (how people tend to work), each color top to bottom.
        let order = t.regions.indices.sorted {
            let a = t.regions[$0], b = t.regions[$1]
            if a.colorIndex != b.colorIndex { return a.colorIndex < b.colorIndex }
            return (a.bounds.minY, a.bounds.minX) < (b.bounds.minY, b.bounds.minX)
        }
        func paint(fraction: Double) {
            let count = Int(Double(order.count) * fraction)
            let regions = Array(order.prefix(count))
            if !regions.isEmpty { session.paint(regions, from: .zero, animated: false) }
            if let next = order.dropFirst(count).first { session.select(color: session.colorOf(next)) }
        }

        switch scenario {
        case "paint-progress", "paint-dark":
            paint(fraction: 0.55)
        case "paint-zoom":
            paint(fraction: 0.3)
            // Centre on a mid-sized unpainted region of the selected color near the middle.
            let middle = SIMD2(Float(t.width), Float(t.height)) * 0.5
            let color = session.selectedColor ?? 0
            let candidates = t.regions.indices.filter {
                session.colorOf($0) == color && !session.isPainted($0) && t.regions[$0].inscribedRadius > 6
            }
            let target = candidates.min { simd_distance(Self.center(t, $0), middle) < simd_distance(Self.center(t, $1), middle) }
            camera = CanvasCamera(zoom: 4, center: target.map { Self.center(t, $0) } ?? middle)
        case "paint-complete":
            paint(fraction: 1)
        case "paint-replay":
            paint(fraction: 1)
            // Slowed so the CI screenshot lands mid-replay.
            fillDurationScale = 4
        case "paint-fill":
            paint(fraction: 0.2)
            // Big fills take 0.6 s; stretched so the CI screenshot (~10 s later) lands mid-spread.
            fillDurationScale = 128
        case "paint-hint":
            paint(fraction: 0.4)
        default:
            break
        }
    }

    /// Scenario actions that need the canvas on screen.
    func run() async {
        if scenario == "paint-hint" {
            try? await Task.sleep(for: .seconds(1.5))
            session.showHint(near: SIMD2(Float(session.template.width), Float(session.template.height)) * 0.5)
            let attached = session.canvas != nil
            Self.log.notice("demo paint-hint: requested (canvas attached: \(attached, privacy: .public))")
            return
        }
        if scenario == "paint-replay" {
            try? await Task.sleep(for: .seconds(1.5))
            (session.canvas as? CanvasView)?.replay()
            // Readiness is signalled on return; the screenshot follows ~2 s later, mid-replay.
            try? await Task.sleep(for: .seconds(1.5))
            return
        }
        guard scenario == "paint-fill" else { return }
        try? await Task.sleep(for: .seconds(1.5))
        let t = session.template
        // Large regions whose paint reads clearly against the paper, so the front is visible.
        func luminance(_ r: Int) -> Float {
            ColorScience.relativeLuminance(encoded: t.palette[Int(t.regions[r].colorIndex)].rgb, space: t.colorSpace)
        }
        guard let first = t.regions.indices
            .filter({ !session.isPainted($0) && luminance($0) < 0.3 })
            .max(by: { t.regions[$0].area < t.regions[$1].area })
        else { return }
        let color = session.colorOf(first)
        session.select(color: color)
        let targets = t.regions.indices
            .filter { session.colorOf($0) == color && !session.isPainted($0) }
            .sorted { t.regions[$0].area > t.regions[$1].area }
            .prefix(3)
        for r in targets {
            session.paint([r], from: Self.center(t, r), animated: true)
        }
        let canvas = session.canvas as? CanvasView
        Self.log.notice(
            "demo paint-fill: painted \(Array(targets), privacy: .public) of color \(color, privacy: .public); frames \(canvas?.framesRendered ?? -1, privacy: .public)")
    }

    private static let log = Logger(subsystem: "com.pbordjadze.paintbynumber", category: "demo")

    private static func center(_ t: Template, _ region: Int) -> SIMD2<Float> {
        t.labels(ofRegion: region).first?.position ?? .zero
    }
}
