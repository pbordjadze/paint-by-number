#if UNRELEASED
import CoreGraphics
import Foundation
import Metal
import PaintCore
import Testing
@testable import PaintByNumber

/// Stained Glass as a mode of the painting canvas (painting-company row 366): the canvas's own
/// frame recipe (`RenderContext.encode`) with `GlassMode` in the content draws the window's
/// lenses over its photo and its lead in place of the paint, and leaves out the canvas's outlines
/// and numbers.
@MainActor
struct GlassModeTests {
    @Test func aPouredGlassTintsItsLensAndTheLeadIsDark() throws {
        let t = Fixtures.mosaic
        let context = try #require(RenderContext.shared)
        let scene = try #require(CanvasScene(template: t, context: context))
        let photo = try #require(Self.greyPhoto(width: t.width, height: t.height))
        let mode = try #require(GlassMode(template: t, texture: GlassTexture(template: t), offered: t.palette, photo: photo,
                                          context: context))
        // The most colorful paint, glazed into its first piece, over a plain grey photo.
        let glass = t.palette.indices.max { Self.chroma(t.palette[$0]) < Self.chroma(t.palette[$1]) }!
        let r = try #require(t.regions.indices.first { Int(t.regions[$0].colorIndex) == glass })
        let other = try #require(t.regions.indices.first { $0 != r })
        // The numbers' visibility rides the frame's uniforms as well as `Content.numbers`.
        let uniforms = CanvasSnapshot.uniforms(scene: scene, width: t.width, height: t.height, options: .painting)
        let numberedUniforms = CanvasSnapshot.uniforms(
            scene: scene, width: t.width, height: t.height, options: CanvasSnapshot.Options(outlines: false, numbers: true))

        func frame(glazed: Bool, framed: Bool = true, outlines: Bool = true, numbers: Bool = false) throws -> CGImage {
            var states = [RegionState](repeating: .settled(painted: false), count: scene.regionCount)
            for i in states.indices { states[i].mode = GlassMode.code(glass: nil, replacing: nil, framed: framed) }
            if glazed {
                states[r] = .settled(painted: true)
                states[r].mode = GlassMode.code(glass: glass, replacing: nil)
            }
            return try #require(CanvasSnapshot.image(
                scene: scene, states: states, uniforms: numbers ? numberedUniforms : uniforms,
                content: RenderContext.Content(outlines: outlines, numbers: numbers, mode: mode),
                width: t.width, height: t.height, context: context))
        }
        let clear = try frame(glazed: false), poured = try frame(glazed: true)
        record(clear, "glass-mode-clear")
        record(poured, "glass-mode-poured")
        let before = PixelReader(clear), after = PixelReader(poured)
        let inside = t.anchor(ofRegion: r), elsewhere = t.anchor(ofRegion: other)
        func luma(_ p: SIMD3<Int>) -> Int { (p.x * 3 + p.y * 6 + p.z) / 10 }
        func colorfulness(_ p: SIMD3<Int>) -> Int { max(p.x, p.y, p.z) - min(p.x, p.y, p.z) }
        let x = Int(inside.x), y = Int(inside.y)
        #expect(colorfulness(before[x, y]) < 12, "a clear lens shows the grey photo")
        #expect(colorfulness(after[x, y]) > colorfulness(before[x, y]) + 30, "a poured glass tints its lens")
        #expect(after[Int(elsewhere.x), Int(elsewhere.y)] == before[Int(elsewhere.x), Int(elsewhere.y)],
                "the other pieces stay as they were")
        // A pixel on the lead between two pieces is darker than the clear lens beside it.
        let edge = try #require((0..<(t.width - 1)).lazy.compactMap { x -> SIMD2<Int>? in
            return t.regionMap[x, y] != t.regionMap[x + 1, y] ? SIMD2(x, y) : nil
        }.first)
        #expect(luma(before[edge.x, edge.y]) + 40 < luma(before[x, y]), "the lead is dark")
        // The lead is the drawing: the canvas's own outlines never show.
        let unoutlined = PixelReader(try frame(glazed: true, outlines: false))
        for (px, py) in [(x, y), (edge.x, edge.y), (Int(elsewhere.x), Int(elsewhere.y))] {
            #expect(unoutlined[px, py] == after[px, py])
        }
        // By number: a piece waiting for its glass shows its number, a glazed one doesn't.
        let numbered = PixelReader(try frame(glazed: true, numbers: true))
        #expect(numbered[x, y] == after[x, y], "a glazed piece's number is gone")
        let shown = (0..<t.height).contains { py in
            (0..<t.width).contains { px in Int(t.regionMap[px, py]) != r && numbered[px, py] != after[px, py] }
        }
        #expect(shown, "the unglazed pieces are numbered")
        // A piece not yet framed is the photo dimmed, its lead a thin line.
        let unframed = PixelReader(try frame(glazed: false, framed: false))
        #expect(luma(unframed[x, y]) + 20 < luma(before[x, y]), "an unframed piece waits in the dark")
        #expect(luma(unframed[edge.x, edge.y]) > luma(before[edge.x, edge.y]), "its lead is only a thin line")
    }

    /// Past white (`ExtendedRange`): drawn into the extended range, a whole window's poured glass
    /// glows brighter than white once the sun has passed, as far as the screen's headroom lets it;
    /// with no headroom, or before the sun, nothing goes past white.
    @Test func aWholeWindowGlowsPastWhite() throws {
        let t = Fixtures.mosaic
        let context = try #require(RenderContext.shared)
        let scene = try #require(CanvasScene(template: t, context: context))
        let photo = try #require(Self.greyPhoto(width: t.width, height: t.height, level: 0.8))
        let mode = try #require(GlassMode(template: t, texture: GlassTexture(template: t), offered: t.palette, photo: photo,
                                          context: context))
        var states = [RegionState](repeating: .settled(painted: true), count: scene.regionCount)
        for r in states.indices { states[r].mode = GlassMode.code(glass: Int(t.regions[r].colorIndex), replacing: nil) }
        let w = t.width, h = t.height
        let uniforms = CanvasSnapshot.uniforms(scene: scene, width: w, height: h, options: .painting)

        func brightest(headroom: Float) throws -> Float {
            let format = RenderContext.extendedFormat
            let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format, width: w, height: h, mipmapped: false)
            d.usage = [.renderTarget, .shaderRead]
            d.storageMode = .private
            let color = try #require(context.device.makeTexture(descriptor: d))
            let outlines = try #require(context.makeOutlineTarget(width: w, height: h))
            let rowBytes = w * 8
            let readBack = try #require(context.device.makeBuffer(length: rowBytes * h, options: .storageModeShared))
            let buffer = try #require(context.device.makeBuffer(
                bytes: states, length: MemoryLayout<RegionState>.stride * states.count, options: .storageModeShared))
            let commands = try #require(context.queue.makeCommandBuffer())
            context.encode(
                commands, scene: scene, states: buffer, uniforms: uniforms,
                targets: RenderContext.Targets(
                    color: color, multisample: context.makeMultisampleTarget(width: w, height: h, format: format),
                    outlines: outlines),
                content: RenderContext.Content(mode: mode, headroom: headroom))
            let blit = try #require(commands.makeBlitCommandEncoder())
            blit.copy(from: color, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                      sourceSize: MTLSize(width: w, height: h, depth: 1), to: readBack, destinationOffset: 0,
                      destinationBytesPerRow: rowBytes, destinationBytesPerImage: rowBytes * h)
            blit.endEncoding()
            commands.commit()
            commands.waitUntilCompleted()
            let values = readBack.contents().bindMemory(to: Float16.self, capacity: w * h * 4)
            var most: Float = 0
            for i in 0..<(w * h) { most = max(most, Float(values[i * 4]), Float(values[i * 4 + 1]), Float(values[i * 4 + 2])) }
            return most
        }
        // The hour's light over the glass adds a little past white, which only the glow outdoes.
        mode.sun(at: 0, held: 1, passes: true, hour: 12)
        let lit = try brightest(headroom: 3), plain = try brightest(headroom: 1)
        #expect(lit > 1.5, "the lit glass goes past white")
        #expect(plain < 1.25, "with no headroom nothing does")
        mode.sun(at: 1_000_000, passes: true, hour: 12)
        #expect(try brightest(headroom: 3) < 1.25, "nor before the sun has passed")
        mode.sun(at: 0, held: 1, passes: true, hour: nil)
        #expect(try brightest(headroom: 3) < 1.25, "nor in a window not whole")
    }

    private static func chroma(_ p: PaletteColor) -> Float { (p.oklab.y * p.oklab.y + p.oklab.z * p.oklab.z).squareRoot() }

    private static func greyPhoto(width: Int, height: Int, level: CGFloat = 0.5) -> CGImage? {
        guard let space = CGColorSpace(name: CGColorSpace.displayP3),
              let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.setFillColor(CGColor(colorSpace: space, components: [level, level, level, 1]) ?? CGColor(gray: level, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()
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

    /// By hand and by number (Paul's interface, November 22, 2026): a piece takes glass only once
    /// it is framed, and only its own number's; Undo takes back a pour, then a frame.
    @Test func aPieceIsFramedBeforeItTakesItsOwnGlass() throws {
        let t = Fixtures.mosaic
        let context = try #require(RenderContext.shared)
        let mode = try #require(GlassMode(template: t, texture: GlassTexture(template: t), offered: t.palette, photo: nil,
                                          context: context))
        let model = GlassGlazeModel(id: UUID(), template: t, glazing: Glazing(pieces: t.regions.count, offered: t.palette),
                                    offered: t.palette, mode: mode)
        let r = try #require(t.regions.indices.first { !model.hidden.contains($0) })
        let own = Int(t.regions[r].colorIndex)
        model.selected = own
        #expect(!model.glaze(r, animated: false), "a bare piece takes no glass")
        model.frame([r])
        #expect(model.framedByHand == 1 && model.canUndo)
        if t.palette.count > 1 {
            model.selected = (own + 1) % t.palette.count
            #expect(!model.glaze(r, animated: false), "another number's glass doesn't go in")
        }
        model.selected = own
        #expect(model.glaze(r, animated: false) && model.glazedCount == 1)
        model.undo()
        #expect(model.glazedCount == 0 && model.framedByHand == 1, "Undo takes the glass back first")
        model.undo()
        #expect(model.framedByHand == 0 && !model.canUndo, "then the frame")
    }

    /// A pour's region state carries both glasses: the one poured and the one under it.
    @Test func aPourCarriesTheGlassItReplaces() {
        let framed = Float(GlassMode.framedFlag)
        #expect(GlassMode.code(glass: nil, replacing: nil, framed: false) == 0)
        #expect(GlassMode.code(glass: nil, replacing: nil) == framed)
        #expect(GlassMode.code(glass: 0, replacing: nil) == 1 + framed)
        #expect(GlassMode.code(glass: 4, replacing: 2) == 5 + 1024 * 3 + framed)
    }
}
#endif
