import PaintCore
import SwiftUI
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
                    .task { await demo.run() }
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
        case "paint-fill":
            paint(fraction: 0.2)
            fillDurationScale = 160
        default:
            break
        }
    }

    /// Scenario actions that need the canvas on screen.
    func run() async {
        guard scenario == "paint-fill" else { return }
        try? await Task.sleep(for: .seconds(1.5))
        let t = session.template
        guard let color = session.selectedColor else { return }
        let targets = t.regions.indices
            .filter { session.colorOf($0) == color && !session.isPainted($0) }
            .sorted { t.regions[$0].area > t.regions[$1].area }
            .prefix(8)
        for r in targets {
            let b = t.regions[r].bounds
            session.paint([r], from: SIMD2(Float(b.minX) + 2, Float(b.minY) + 2), animated: true)
        }
    }

    private static func center(_ t: Template, _ region: Int) -> SIMD2<Float> {
        t.labels(ofRegion: region).first?.position ?? .zero
    }
}
