#if DEBUG
import CoreGraphics
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
/// - `paint-photo`: the source photo shown over a painting in progress
/// - `paint-tip`: a fresh canvas with the first tip ("Tap to Paint") at the selected swatch;
///   the only scenario that shows tips (`PaintTips.configure`)
///
/// Photo-based scenarios have the photo loader, so the top bar is the one users see.
/// - `paint-ax`: `paint-progress`, showing the selected color's name
/// - `paint-ax-large`: `paint-ax` at the largest accessibility text size
/// - `paint-long-text`, `paint-complete-long-text`: `paint-progress` and `paint-complete` with a long
///   title and every localized string twice as long (`ci/screenshots.sh` adds
///   `-NSDoubleLocalizedStrings YES` to scenarios named `*-long-text`): the progress badge, palette
///   caption and completion bar as translations would stress them
struct PaintDemoView: View {
    let scenario: String
    @State private var demo: Demo?
    @Environment(\.dynamicTypeSize) private var systemTypeSize

    init(scenario: String) {
        self.scenario = scenario
    }

    var body: some View {
        ZStack {
            if let demo {
                PaintView(
                    session: demo.session, title: demo.title, onClose: {},
                    initialCamera: demo.camera, fillDurationScale: demo.fillDurationScale, showsPhoto: demo.showsPhoto)
                    .environment(\.sourcePhotoLoader, demo.isSynthetic ? nil : SourcePhotoLoader(load: { size in
                        await Self.photo(maxPixelSize: size)
                    }))
                    .environment(\.dynamicTypeSize, demo.dynamicTypeSize ?? systemTypeSize)
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
            // Titles are the person's own words, which pseudo-localization doesn't lengthen.
            let title = base.hasSuffix("-long-text")
                ? "Two Parrots on a Branch in the Morning Light" : (template == nil ? "Mosaic" : "Parrots")
            demo = Demo(
                scenario: base, template: template ?? SyntheticTemplate.make(), title: title, isSynthetic: template == nil)
        }
    }

    /// The photo the demo template is generated from, so the overlay lines up for real.
    @concurrent
    private static func photo(maxPixelSize: Int?) async -> CGImage? {
        guard let url = Bundle.main.url(forResource: "parrots", withExtension: "jpg") else { return nil }
        return ImageCodec.image(at: url, maxPixelSize: maxPixelSize)
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
    let isSynthetic: Bool
    var camera: CanvasCamera?
    var fillDurationScale: Float = 1
    var showsPhoto = false
    /// Overrides the system text size (accessibility scenarios).
    var dynamicTypeSize: DynamicTypeSize?
    private let scenario: String

    init(scenario: String, template t: Template, title: String, isSynthetic: Bool) {
        self.scenario = scenario
        self.title = title
        self.isSynthetic = isSynthetic
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
        case "paint-progress", "paint-dark", "paint-ax", "paint-long-text":
            paint(fraction: 0.55)
        case "paint-ax-large":
            paint(fraction: 0.55)
            dynamicTypeSize = .accessibility5
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
        case "paint-complete", "paint-complete-long-text":
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
        case "paint-photo":
            paint(fraction: 0.4)
            showsPhoto = true
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
        if scenario == "paint-photo" {
            // Ready once the photo has loaded and faded in.
            let clock = ContinuousClock()
            let deadline = clock.now + .seconds(5)
            var opacity: Float = 0
            while clock.now < deadline {
                opacity = (session.canvas as? CanvasView)?.photoOpacity ?? 0
                if opacity >= 0.999 { break }
                try? await Task.sleep(for: .milliseconds(100))
            }
            Self.log.notice("demo paint-photo: photo opacity \(opacity, privacy: .public)")
            return
        }
        if scenario == PaintTips.demoScenario {
            // TipKit evaluates eligibility asynchronously; the popover is up well within this.
            try? await Task.sleep(for: .seconds(1.5))
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
#endif
