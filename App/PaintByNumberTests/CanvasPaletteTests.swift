import CoreGraphics
import Foundation
import PaintCore
import Testing
import UIKit
@testable import PaintByNumber

/// The canvas palettes: contrast, the accent on dark paper, and how the Paper preference and
/// the system appearance pick one.
@MainActor
struct CanvasPaletteTests {
    /// WCAG relative luminance of a linear Display P3 color.
    private func luminance(_ c: SIMD3<Float>) -> Double {
        0.2289746 * Double(c.x) + 0.6917385 * Double(c.y) + 0.0792869 * Double(c.z)
    }

    private func contrast(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Double {
        let (hi, lo) = (max(luminance(a), luminance(b)), min(luminance(a), luminance(b)))
        return (hi + 0.05) / (lo + 0.05)
    }

    /// Ink (outlines, numbers) reads on its paper at 4.5:1 or better in every palette.
    @Test(arguments: [("light", CanvasPalette.light), ("dark appearance", CanvasPalette.dark), ("dark paper", CanvasPalette.darkPaper)])
    func inkContrastsWithPaper(name: String, palette: CanvasPalette) {
        let ratio = contrast(palette.ink, palette.paper)
        #expect(ratio >= 4.5, "\(name): \(ratio):1")
    }

    @Test func darkPaperIsADeepWarmGreyWithALightRim() {
        let p = CanvasPalette.darkPaper
        #expect(luminance(p.paper) < 0.03 && p.paper.x >= p.paper.z)
        #expect(luminance(p.background) < luminance(p.paper))
        #expect(p.shadowOpacity == 0 && p.rimOpacity > 0)
        #expect(CanvasPalette.light.rimOpacity == 0 && CanvasPalette.dark.rimOpacity == 0)
    }

    /// Light paper keeps the selected paint as its accent, exactly: its frames are unchanged.
    @Test func lightPaperAccentIsThePaintItself() {
        let paints: [SIMD3<Float>] = [.zero, SIMD3(1, 1, 1), SIMD3(0.02, 0.01, 0.05), SIMD3(0.8, 0.1, 0.1), SIMD3(0.3, 0.6, 0.2)]
        for palette in [CanvasPalette.light, .dark] {
            for paint in paints { #expect(palette.accent(for: paint) == paint) }
            var u = CanvasUniforms()
            u.select(paints[2], palette: palette)
            #expect(u.accent == SIMD4(paints[2], 0.4) && u.selected == SIMD4(paints[2], 1))
        }
    }

    /// On dark paper a dark paint is lightened until it reads, a bright one is left alone.
    @Test func darkPaperLightensDarkAccents() {
        let palette = CanvasPalette.darkPaper
        for paint in [SIMD3<Float>.zero, SIMD3(0.02, 0.01, 0.05), SIMD3(0.1, 0.02, 0.02)] {
            let accent = palette.accent(for: paint)
            #expect(luminance(accent) >= Double(palette.accentFloor) - 0.01, "\(paint) → \(accent)")
            #expect(accent.min() >= 0 && accent.max() <= 1)
        }
        let yellow = SIMD3<Float>(0.9, 0.8, 0.1)
        #expect(palette.accent(for: yellow) == yellow)
        var u = CanvasUniforms()
        u.select(.zero, palette: palette)
        #expect(u.selected == SIMD4(0, 0, 0, 1) && u.accent.w == palette.hatchCeiling && u.accent.x > 0)
    }

    /// The offscreen renders (completion picture, time-lapse) are on light paper whatever the
    /// canvas shows.
    @Test func offscreenRendersStayOnLightPaper() throws {
        for options in [CanvasSnapshot.Options.painting, .preview, .thumbnail] {
            #expect(options.palette.paper == CanvasPalette.light.paper)
        }
        let context = try #require(RenderContext.shared)
        let scene = try #require(CanvasScene(template: Fixtures.mosaic, context: context))
        let u = CanvasSnapshot.uniforms(scene: scene, width: 240, height: 320, options: .preview)
        #expect(u.paper == SIMD4(CanvasPalette.light.paper, 0) && u.rim.w == 0)
    }

    @Test func paperPreferenceAndAppearancePickThePalette() {
        for dark in [false, true] {
            #expect(CanvasPalette.resolve(.dark, interfaceIsDark: dark).paper == CanvasPalette.darkPaper.paper)
        }
        #expect(CanvasPalette.resolve(.light, interfaceIsDark: false).paper == CanvasPalette.light.paper)
        #expect(CanvasPalette.resolve(.light, interfaceIsDark: true).paper == CanvasPalette.dark.paper)
        #expect(CanvasPalette.resolve(.automatic, interfaceIsDark: false).paper == CanvasPalette.light.paper)
        #expect(CanvasPalette.resolve(.automatic, interfaceIsDark: true).paper == CanvasPalette.darkPaper.paper)
        #expect(PaperAppearance.default == .light)
        #expect(PaperAppearance.allCases.map(\.name) == ["Light", "Dark", "Automatic"])
    }

    /// The canvas resolves its paper from the preference and the trait collection it inherits
    /// from its window, so a system appearance change reaches an Automatic canvas. A view
    /// outside a window never sees an appearance change, hence the window, as in the app.
    @Test func canvasResolvesPaperFromPreferenceAndTraits() throws {
        let canvas = CanvasView(session: PaintingSession(template: Fixtures.mosaic))
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 700)
        window.overrideUserInterfaceStyle = .light
        window.addSubview(canvas)
        canvas.frame = window.bounds
        window.isHidden = false
        defer { window.isHidden = true }
        canvas.layoutIfNeeded()
        func paper(_ palette: CanvasPalette) -> SIMD4<Float> { SIMD4(palette.paper, palette.shadowOpacity) }
        #expect(canvas.frameUniforms().paper == paper(.light))
        canvas.paperAppearance = .dark
        let dark = canvas.frameUniforms()
        #expect(dark.paper == paper(.darkPaper) && dark.rim.w > 0 && dark.ink == SIMD4(CanvasPalette.darkPaper.ink, dark.ink.w))
        canvas.paperAppearance = .automatic
        #expect(canvas.frameUniforms().paper == paper(.light))
        window.overrideUserInterfaceStyle = .dark
        canvas.updateTraitsIfNeeded()
        #expect(canvas.traitCollection.userInterfaceStyle == .dark)
        #expect(canvas.frameUniforms().paper == paper(.darkPaper))
        canvas.paperAppearance = .light
        #expect(canvas.frameUniforms().paper == paper(.dark))
        window.overrideUserInterfaceStyle = .light
        canvas.updateTraitsIfNeeded()
        #expect(canvas.frameUniforms().paper == paper(.light))
    }
}
