#if DEBUG
import CoreGraphics
import PaintCore
import SwiftUI
import os
import simd

/// Demo scenarios for the painting screen, deterministic for CI screenshots. The template is
/// generated from a bundled photo:
///
/// - `paint`: fresh canvas, fit to screen
/// - `paint-progress`: ~55 % painted color by color, the color in progress selected
/// - `paint-zoom`: zoomed ~4× into the canvas, numbers and highlight visible
/// - `paint-complete`: finished painting (line art dissolved)
/// - `paint-dark`: `paint-progress` for dark appearance
/// - `paint-dark-paper`: `paint-progress` on dark paper (the Paper setting at Dark)
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
/// - `paint-names-plain`: `paint-progress` under Settings › Color Names › Plain (structured names only)
/// - `paint-palette`: ~30 % painted, the palette in four rows in rainbow order (Settings › Palette)
/// - `paint-long-text`, `paint-complete-long-text`: `paint-progress` and `paint-complete` with a long
///   title and every localized string twice as long (`ci/screenshots.sh` adds
///   `-NSDoubleLocalizedStrings YES` to scenarios named `*-long-text`): the progress badge, palette
///   caption and completion bar as translations would stress them
///
/// Layered line art from the real pipeline (the stand-in edge map `SyntheticTemplate.edgeMap`
/// for the learned detector) at the default Line Appearance:
/// - `paint-layered`: fresh canvas, fit to screen (the 1× look: outlines, faint texture)
/// - `paint-layered-progress`: ~45 % painted, the color in progress selected (painted lines
///   dissolve, the selected color's cells are outlined boldly whatever their layer)
/// - `paint-layered-zoom2`, `paint-layered-zoomed`: zoomed 2× and 4× into the drawing, the
///   fainter layers coming in
/// - `paint-layered-dark-paper`: `paint-layered-progress` on dark paper
/// - `paint-layered-inked`: `paint-layered-progress` with a Line Appearance whose outlines stay
///   over the paint (lines between painted cells keep their ink)
///
/// A coloring book of the red fox from the real pipeline, with the real edge detector (the
/// stand-in map when the model is unavailable):
/// - `paint-book`: fresh canvas, fit to screen (the drawing in thick ink, nothing else)
/// - `paint-book-progress`: ~45 % painted, the color in progress selected (the drawing stays
///   over the paint; the selected color's cells are hatched, not outlined)
/// - `paint-book-zoomed`: zoomed 4× into the busiest part, a color selected
/// - `paint-book-dark-paper`: `paint-book-progress` on dark paper
struct PaintDemoView: View {
    let scenario: String
    @State private var demo: Demo?
    @Environment(\.dynamicTypeSize) private var systemTypeSize

    var body: some View {
        ZStack {
            if let demo {
                PaintView(
                    session: demo.session, title: demo.title, onClose: {},
                    initialCamera: demo.camera, fillDurationScale: demo.fillDurationScale, showsPhoto: demo.showsPhoto)
                    .environment(\.sourcePhotoLoader, demo.photo.map { name in
                        SourcePhotoLoader(load: { size in await Self.photo(name, maxPixelSize: size) })
                    })
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
            let layered = scenario.hasPrefix("paint-layered"), book = scenario.hasPrefix("paint-book")
            let photo = layered ? "santa-fe-freight" : book ? "red-fox" : "parrots"
            let template: Template?
            if layered || book {
                template = await Self.drawnTemplate(photo: photo, style: book ? .coloringBook : .layered)
            } else {
                template = await Self.template(photo: photo)
            }
            // Titles are the person's own words, which pseudo-localization doesn't lengthen.
            let title = scenario.hasSuffix("-long-text")
                ? "Two Parrots on a Branch in the Morning Light"
                : (template == nil ? "Mosaic" : (layered ? "Freight Train" : book ? "Red Fox" : "Parrots"))
            demo = Demo(
                scenario: scenario, template: template ?? SyntheticTemplate.make(), title: title,
                photo: template == nil ? nil : photo)
        }
    }

    /// The photo the demo template is generated from, so the overlay lines up for real.
    @concurrent
    private static func photo(_ name: String, maxPixelSize: Int?) async -> CGImage? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "jpg") else { return nil }
        return ImageCodec.image(at: url, maxPixelSize: maxPixelSize)
    }

    /// The photo's classic template: the classic demos show the original look.
    @concurrent
    private static func template(photo: String) async -> Template? {
        let settings = GenerationSettings(lineArt: LineArtSettings(style: .classic))
        guard let url = Bundle.main.url(forResource: photo, withExtension: "jpg"),
              let image = try? PhotoLoader.load(url: url, maxPixelSize: 2048),
              let output = try? TemplateGenerator(settings: settings).generate(from: image)
        else { return nil }
        return output.template.mesh.indices.isEmpty ? nil : output.template
    }

    /// The photo's layered or coloring-book template from the real pipeline. Layered demos keep
    /// the stand-in edge map (`SyntheticTemplate.edgeMap`) their screenshots were judged with;
    /// a coloring book draws from the real detector (`LineArtInputs.compute`), falling back to
    /// the stand-in when the model is unavailable.
    @concurrent
    private static func drawnTemplate(photo: String, style: LineArtSettings.Style) async -> Template? {
        var settings = GenerationSettings()
        settings.lineArt.style = style
        guard let url = Bundle.main.url(forResource: photo, withExtension: "jpg"),
              let image = try? PhotoLoader.load(url: url, maxPixelSize: 2048),
              let small = try? PhotoLoader.load(url: url, maxPixelSize: 640)
        else { return nil }
        var input: LineArtInput?
        if style == .coloringBook, let cgImage = PhotoLoader.cgImage(from: image) {
            input = try? await LineArtInputs.compute(for: cgImage)
            Log.demo.notice("demo \(photo, privacy: .public): edge detector \(input == nil ? "unavailable, using the stand-in map" : "ran", privacy: .public)")
        }
        guard let output = try? TemplateGenerator(settings: settings)
            .generate(from: image, lineArt: input ?? LineArtInput(edges: SyntheticTemplate.edgeMap(for: small)))
        else { return nil }
        return output.template.lineArt == nil || output.template.mesh.indices.isEmpty ? nil : output.template
    }
}

@MainActor
private final class Demo {
    let session: PaintingSession
    let title: String
    /// The bundled photo the template was made from; nil for the synthetic mosaic that stands
    /// in when generating from it failed.
    let photo: String?
    var camera: CanvasCamera?
    var fillDurationScale: Float = 1
    var showsPhoto = false
    /// Overrides the system text size (accessibility scenarios).
    var dynamicTypeSize: DynamicTypeSize?
    private let scenario: String

    init(scenario: String, template t: Template, title: String, photo: String?) {
        self.scenario = scenario
        self.title = title
        self.photo = photo
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
        case "paint-dark-paper":
            paint(fraction: 0.55)
            // Registered, not stored: it lasts for this launch, so the next scenario on the same
            // simulator keeps the default light paper.
            UserDefaults.standard.register(defaults: [SettingsKey.paperAppearance: PaperAppearance.dark.rawValue])
        case "paint-names-plain":
            paint(fraction: 0.55)
            session.colorNameStyle = .plain
        case "paint-palette":
            paint(fraction: 0.3)
            // Registered, not stored, like the paper above.
            UserDefaults.standard.register(defaults: [
                SettingsKey.paletteRows: PaletteRows.four.rawValue, SettingsKey.paletteOrder: PaletteOrder.rainbow.rawValue,
            ])
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
        case "paint-layered-progress", "paint-book-progress":
            paint(fraction: 0.45)
        case "paint-layered-dark-paper", "paint-book-dark-paper":
            paint(fraction: 0.45)
            UserDefaults.standard.register(defaults: [SettingsKey.paperAppearance: PaperAppearance.dark.rawValue])
        case "paint-layered-inked":
            paint(fraction: 0.45)
            var appearance = LineAppearance.default
            appearance.outline.painted = 1
            appearance.detail.painted = 0.5
            if let data = try? JSONEncoder().encode(appearance) {
                UserDefaults.standard.register(defaults: [SettingsKey.lineAppearance: data])
            }
        case "paint-layered-zoom2", "paint-layered-zoomed", "paint-book-zoomed":
            paint(fraction: 0.2)
            camera = CanvasCamera(zoom: scenario == "paint-layered-zoom2" ? 2 : 4, center: Self.busiest(t))
        default:
            break
        }
    }

    /// The middle of the busiest of 8 × 8 tiles (most line points, strokes included), where
    /// zooming in shows the layers.
    private static func busiest(_ t: Template) -> SIMD2<Float> {
        let n = 8
        var counts = [Int](repeating: 0, count: n * n)
        func add(_ p: SIMD2<Float>) {
            let i = min(n - 1, max(0, Int(p.x / Float(t.width) * Float(n))))
            let j = min(n - 1, max(0, Int(p.y / Float(t.height) * Float(n))))
            counts[j * n + i] += 1
        }
        t.points.forEach(add)
        t.lineArt?.strokePoints.forEach(add)
        let best = counts.indices.max { counts[$0] < counts[$1] } ?? 0
        return SIMD2((Float(best % n) + 0.5) * Float(t.width), (Float(best / n) + 0.5) * Float(t.height)) / Float(n)
    }

    /// Scenario actions that need the canvas on screen.
    func run() async {
        if scenario == "paint-hint" {
            try? await Task.sleep(for: .seconds(1.5))
            session.showHint(near: SIMD2(Float(session.template.width), Float(session.template.height)) * 0.5)
            let attached = session.canvas != nil
            Log.demo.notice("demo paint-hint: requested (canvas attached: \(attached, privacy: .public))")
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
            Log.demo.notice("demo paint-photo: photo opacity \(opacity, privacy: .public)")
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
        Log.demo.notice(
            "demo paint-fill: painted \(Array(targets), privacy: .public) of color \(color, privacy: .public); frames \(canvas?.framesRendered ?? -1, privacy: .public)")
    }

    private static func center(_ t: Template, _ region: Int) -> SIMD2<Float> {
        t.labels(ofRegion: region).first?.position ?? .zero
    }
}
#endif
