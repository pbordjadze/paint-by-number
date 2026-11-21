#if UNRELEASED
import CoreGraphics
import Foundation
import Metal
import PaintCore
import Testing
@testable import PaintByNumber

/// Stained Glass as a mode of the painting canvas (painting-company row 366): the canvas's own
/// frame recipe (`RenderContext.encode`) with `GlassMode` in the content draws the window's glass
/// and lead in place of the paint, and leaves out the canvas's outlines and numbers.
@MainActor
struct GlassModeTests {
    @Test func glazedGlassShinesOverUnlitAndTheLeadIsDark() throws {
        let t = Fixtures.mosaic
        let context = try #require(RenderContext.shared)
        let scene = try #require(CanvasScene(template: t, context: context))
        let mode = try #require(GlassMode(template: t, texture: GlassTexture(template: t), offered: t.palette, context: context))
        // The brightest paint, glazed into its first piece.
        let glass = t.palette.indices.max { t.palette[$0].oklab.x < t.palette[$1].oklab.x }!
        let r = try #require(t.regions.indices.first { Int(t.regions[$0].colorIndex) == glass })
        let other = try #require(t.regions.indices.first { $0 != r })
        let uniforms = CanvasSnapshot.uniforms(scene: scene, width: t.width, height: t.height, options: .painting)

        func frame(glazed: Bool, outlines: Bool = true, numbers: Bool = true) throws -> CGImage {
            var states = [RegionState](repeating: .settled(painted: false), count: scene.regionCount)
            if glazed {
                states[r] = .settled(painted: true)
                states[r].mode = GlassMode.code(glass: glass, replacing: nil)
            }
            return try #require(CanvasSnapshot.image(
                scene: scene, states: states, uniforms: uniforms,
                content: RenderContext.Content(outlines: outlines, numbers: numbers, mode: mode),
                width: t.width, height: t.height, context: context))
        }
        let unlit = try frame(glazed: false), lit = try frame(glazed: true)
        record(unlit, "glass-mode-unlit")
        record(lit, "glass-mode-lit")
        let before = PixelReader(unlit), after = PixelReader(lit)
        let inside = t.anchor(ofRegion: r), elsewhere = t.anchor(ofRegion: other)
        func luma(_ p: SIMD3<Int>) -> Int { (p.x * 3 + p.y * 6 + p.z) / 10 }
        #expect(luma(after[Int(inside.x), Int(inside.y)]) > luma(before[Int(inside.x), Int(inside.y)]) + 40,
                "a glazed piece shines over its unlit glass")
        #expect(after[Int(elsewhere.x), Int(elsewhere.y)] == before[Int(elsewhere.x), Int(elsewhere.y)],
                "the other pieces stay as they were")
        // A pixel on the lead between two pieces is darker than the glazed glass it holds.
        let edge = try #require((0..<(t.width - 1)).lazy.compactMap { x -> SIMD2<Int>? in
            let y = Int(inside.y)
            return t.regionMap[x, y] != t.regionMap[x + 1, y] ? SIMD2(x, y) : nil
        }.first)
        #expect(luma(after[edge.x, edge.y]) + 40 < luma(after[Int(inside.x), Int(inside.y)]), "the lead is dark")
        // The lead is the drawing: the canvas's own outlines and numbers never show.
        let bare = PixelReader(try frame(glazed: true, outlines: false, numbers: false))
        for (x, y) in [(Int(inside.x), Int(inside.y)), (edge.x, edge.y), (Int(elsewhere.x), Int(elsewhere.y))] {
            #expect(bare[x, y] == after[x, y])
        }
    }

    /// A whole window stands in the light of the hour: moonlight dims it at night, the day is
    /// clear, the evening amber, and the hours between ease from one to the next.
    @Test func theLightFollowsTheHour() {
        let night = GlassMode.daylight(hour: 2), noon = GlassMode.daylight(hour: 12)
        let evening = GlassMode.daylight(hour: 18.5), dusk = GlassMode.daylight(hour: 19.5)
        #expect(night.w > 0.3 && noon.w == 0)
        #expect(night.z > night.x, "moonlight is blue")
        #expect(evening.x > evening.z * 3, "the evening is amber")
        #expect(dusk.w > evening.w && dusk.w < night.w)
        #expect(GlassMode.daylight(hour: 0) == GlassMode.daylight(hour: 24))
        #expect(GlassGlazeModel.hour(Calendar.current.date(bySettingHour: 18, minute: 30, second: 0, of: .now)!) == 18.5)
    }

    /// A pour rings soft glass, pale glass higher than deep, on the Moon's scale.
    @Test func aPourRingsItsGlass() {
        #expect(SoundPlayer.glassNote(lightness: 0.8) > SoundPlayer.glassNote(lightness: 0.45))
        #expect(SoundPlayer.glassNote(lightness: 0) == 0)
        #expect(SoundPlayer.glassNote(lightness: 1) == SoundPlayer.moonScale.count - 1)
        let cues = SoundPlayer.glassCues(index: 3, velocity: 0.7)
        #expect(cues.first?.voice == .twinkle(index: 3))
        #expect(cues.allSatisfy { $0.volume < 0.35 }, "a soft note")
    }

    /// A pour's region state carries both glasses: the one poured and the one under it.
    @Test func aPourCarriesTheGlassItReplaces() {
        #expect(GlassMode.code(glass: nil, replacing: nil) == 0)
        #expect(GlassMode.code(glass: 0, replacing: nil) == 1)
        #expect(GlassMode.code(glass: 4, replacing: 2) == 5 + 1024 * 3)
    }
}
#endif
