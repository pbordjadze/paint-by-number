import CoreGraphics
import Foundation
import PaintCore
import Testing
@testable import PaintByNumber

/// The short Making-of as everyone's wait (`FormingShow`, painting-company row 361): the graphite
/// lasts as long as the making, the lines burn in no longer than the plain forming drew them,
/// a tap skips, and Reduce Motion and The Making-of switched on bring none of it.
@MainActor
struct FormingShowTests {
    /// SideStore and Debug builds play it; the release keeps the plain forming.
    @Test func itPlaysOnlyWhereThePictureFormsWithLines() {
        #if UNRELEASED
        #expect(FormingShow.isOn)
        #else
        #expect(!FormingShow.isOn)
        #endif
        guard FormingShow.isOn else { return }
        #expect(FormingShow.plays(forms: true, reduceMotion: false, playsMakingOf: false, skipped: nil))
        #expect(FormingShow.plays(forms: true, reduceMotion: false, playsMakingOf: false, skipped: .toPainting))
        // A tap before the template was made sends it to the plain forming.
        #expect(!FormingShow.plays(forms: true, reduceMotion: false, playsMakingOf: false, skipped: .toPlainLines))
        // Not a page from scratch or a drawing; Reduce Motion is the plain cross-fade, and with
        // The Making-of on the whole show plays after Start as it did.
        #expect(!FormingShow.plays(forms: false, reduceMotion: false, playsMakingOf: false, skipped: nil))
        #expect(!FormingShow.plays(forms: true, reduceMotion: true, playsMakingOf: false, skipped: nil))
        #expect(!FormingShow.plays(forms: true, reduceMotion: false, playsMakingOf: true, skipped: nil))
        #expect(FormingPlan.passage(forms: true, reduceMotion: true) == .crossFade)
    }

    /// The graphite lingers as long as the template is still being made: the fuse is lit as it
    /// is made, so a slower device sees a longer graphite and the same fuse after it.
    @Test func theGraphiteLastsAsLongAsTheMaking() {
        let began = 10.0
        for making in [1.1, 2.5, 6.0] {
            let made = began + making
            #expect(FormingShow.fuseLit(madeAt: made, graphiteBegan: began) == made)
            #expect(FormingShow.done(madeAt: made) == made + FormingPlan.drawIn)
        }
        // No graphite (made before its drawing was): lit at once.
        #expect(FormingShow.fuseLit(madeAt: 3, graphiteBegan: nil) == 3)
    }

    /// The show never keeps the painting longer than the plain forming did: its lines have
    /// burned in `drawIn` after the template is made, however soon that was; a graphite that
    /// showed for less than `graphiteAtLeast` takes that from the fuse, which burns faster.
    @Test func itNeverOutlastsTheMakingByMoreThanTheDrawingIn() {
        #expect(FormingShow.longestTail <= FormingPlan.drawIn + 1e-9)
        let began = 10.0
        for making in [0, 0.05, 0.1, FormingShow.graphiteAtLeast, 1, 4] {
            let made = began + making
            let lit = FormingShow.fuseLit(madeAt: made, graphiteBegan: began)
            let done = FormingShow.done(madeAt: made)
            #expect(done - made <= FormingPlan.drawIn + 1e-9)
            #expect(lit >= made && lit <= made + FormingShow.graphiteAtLeast + 1e-9)
            #expect(lit >= began + min(making, FormingShow.graphiteAtLeast) - 1e-9)
            // The fuse still burns long enough to follow.
            #expect(done - lit >= FormingPlan.drawIn - FormingShow.graphiteAtLeast - 1e-9)
        }
        // A graphite stamped after the making (a clock gone wrong) waits no longer either.
        #expect(FormingShow.fuseLit(madeAt: 10, graphiteBegan: 50) <= 10 + FormingShow.graphiteAtLeast + 1e-9)
        #expect(FormingShow.graphiteAtLeast <= 0.25 * FormingPlan.drawIn)
        // The numbers take no time of their own: the glide's settling.
        #expect(FormingShow.stars == StartHandoffPlan.settle)
        // The lift waits for the show, and no longer than the drawing in.
        #expect(FormingPlan.liftWait(remaining: FormingShow.longestTail) == FormingShow.longestTail)
        #expect(FormingPlan.liftWait(remaining: 30) == FormingPlan.drawIn)
    }

    /// Each beat runs from 0 to 1 and stays there, rising all the way.
    @Test func theBeatsRunFromNothingToWhole() {
        let fuse: (Double) -> Double = { FormingShow.fuseProgress(since: $0, length: 0.6) }
        let beats: [(Double) -> Double] = [fuse, FormingShow.starsProgress(since:)]
        for progress in beats {
            #expect(progress(-1) == 0)
            #expect(progress(0) == 0)
            #expect(progress(100) == 1)
            var last = 0.0
            for k in 1...40 {
                let p = progress(Double(k) * 0.05)
                #expect(p >= last)
                last = p
            }
        }
        #expect(FormingShow.fuseProgress(since: 0.6, length: 0.6) == 1)
        #expect(FormingShow.starsProgress(since: FormingShow.stars) == 1)
        // A fuse with no time left is whole at once.
        #expect(FormingShow.fuseProgress(since: 0, length: 0) == 1)
    }

    /// While the template is being made the graphite races out, then ever slower, always moving
    /// and never done: a slow making never shows a still drawing.
    @Test func theGraphiteNeverStandsStill() {
        #expect(FormingShow.graphiteProgress(since: -1) == 0)
        #expect(FormingShow.graphiteProgress(since: 0) == 0)
        #expect(abs(FormingShow.graphiteProgress(since: FormingShow.graphitePace) - FormingShow.graphiteNears / 2) < 1e-9)
        var last = 0.0
        for t in stride(from: 0.25, through: 30, by: 0.25) {
            let p = FormingShow.graphiteProgress(since: t)
            #expect(p > last && p < FormingShow.graphiteNears)
            last = p
        }
        // Still visibly moving after the status comes back.
        let later = FormingShow.graphiteProgress(since: FormingShow.patience + 1) - FormingShow.graphiteProgress(since: FormingShow.patience)
        #expect(later > 0.01)
    }

    /// A tap before the template is made goes to the plain forming; after, to the painting.
    @Test func aTapSkips() {
        #expect(FormingShow.skip(isMade: false) == .toPlainLines)
        #expect(FormingShow.skip(isMade: true) == .toPainting)
        // Skipped to the painting, the lift waits for nothing (the preview says it is done now).
        #expect(FormingPlan.liftWait(remaining: 0) == 0)
        // The moments skipped to the painting: lit and done now, the fuse is whole at once.
        let now = Date.now
        let skipped = FormingMoments(fuseLit: now, fuseDone: now)
        #expect(skipped.fuseProgress(at: now) == 1)
    }

    /// The preview's moments: the graphite races from when it began, the fuse from when it is
    /// lit (which may be a moment ahead) to when it is done, the graphite finishing as it burns;
    /// demos hold either, and nothing moves past their ends.
    @Test func theMomentsFollowTheClock() throws {
        let image = try #require(Self.image())
        let drawing = GraphiteSketch.Drawing(map: image, sheet: FormingPlan.Sheet(paper: SIMD3(1, 1, 1), ink: SIMD3(0, 0, 0)))
        let began = Date(timeIntervalSinceReferenceDate: 1000)
        var moments = FormingMoments(graphite: drawing, graphiteBegan: began)
        #expect(moments.graphiteProgress(at: began) == 0)
        #expect(moments.graphiteProgress(at: began.addingTimeInterval(5)) == FormingShow.graphiteProgress(since: 5))
        #expect(moments.fuseProgress(at: began.addingTimeInterval(5)) == 0)
        // Racing on until the template is made.
        #expect(moments.movesUntil == .distantFuture)

        let made = began.addingTimeInterval(0.05)
        let lit = began.addingTimeInterval(FormingShow.graphiteAtLeast)
        let done = made.addingTimeInterval(FormingPlan.drawIn)
        moments.fuseLit = lit
        moments.fuseDone = done
        #expect(moments.fuseProgress(at: lit.addingTimeInterval(-0.01)) == 0)
        #expect(moments.fuseProgress(at: done) == 1)
        #expect(moments.movesUntil == done)
        // The graphite carries on by the clock until the fuse is lit, then finishes with it.
        let before = lit.addingTimeInterval(-0.01)
        #expect(moments.graphiteProgress(at: before) == FormingShow.graphiteProgress(since: before.timeIntervalSince(began)))
        #expect(abs(moments.graphiteProgress(at: lit) - FormingShow.graphiteProgress(since: FormingShow.graphiteAtLeast)) < 1e-9)
        #expect(abs(moments.graphiteProgress(at: done) - 1) < 1e-9)

        // No graphite drawing, no graphite.
        #expect(FormingMoments(graphiteBegan: began).graphiteProgress(at: began.addingTimeInterval(9)) == 0)
        // Held, nothing moves.
        let held = FormingMoments(
            graphite: drawing, graphiteBegan: began, fuseLit: lit, fuseDone: done, heldGraphite: 0.55, heldFuse: 0.5)
        #expect(held.graphiteProgress(at: .distantFuture) == 0.55)
        #expect(held.fuseProgress(at: .distantFuture) == 0.5)
        #expect(held.movesUntil == nil)
    }

    /// The front reaches its middle first and every corner by the end, farther points later.
    @Test func theFrontCoversThePicture() {
        let rect = CGRect(x: 20, y: 40, width: 300, height: 500)
        let middle = FormingShow.Front.origin(in: rect)
        #expect(FormingShow.Front.arrival(of: middle, in: rect) == 0)
        for corner in [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
                       CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.maxX, y: rect.maxY)] {
            let arrival = FormingShow.Front.arrival(of: corner, in: rect)
            #expect(arrival > 0 && arrival < 1)
            // Whole at 1, its soft edge past every corner, wherever the outline wavers in.
            let distance = hypot(Double(corner.x - middle.x), Double(corner.y - middle.y))
            let ratio = distance / FormingShow.Front.reach(in: rect)
            #expect(FormingShow.Front.alpha(ratio: ratio / (1 - FormingShow.Front.wobble)) > 0.999)
            // And the image at 1 reaches past it.
            #expect(FormingShow.Front.side(in: rect) / 2 >= distance)
        }
        for angle in stride(from: 0.0, to: 2 * Double.pi, by: 0.4) {
            var last = 0.0
            for step in 1...10 {
                let r = Double(step) * 20
                let point = CGPoint(x: middle.x + CGFloat(r * cos(angle)), y: middle.y + CGFloat(r * sin(angle)))
                let arrival = FormingShow.Front.arrival(of: point, in: rect)
                #expect(arrival > last)
                last = arrival
            }
        }
        // The soft edge: whole inside it, nothing past the outline.
        #expect(FormingShow.Front.alpha(ratio: 0.5) == 1)
        #expect(FormingShow.Front.alpha(ratio: 1) == 0)
        #expect(abs(FormingShow.Front.alpha(ratio: 1 - FormingShow.Front.edge / 2) - 0.5) < 1e-6)
    }

    /// The graphite's race runs along the strokes: from the strongest one near the middle, a
    /// cell along a stroke is reached before one as near across bare paper, and every cell is
    /// reached by the end.
    @Test func theGraphiteRacesAlongTheStrokes() {
        // A 20 × 9 grid, bare but for a stroke along row 4 and another down column 2.
        let w = 20, h = 9
        var strokes = [Float](repeating: 0, count: w * h)
        for x in 0..<w { strokes[4 * w + x] = 1 }
        for y in 0..<h { strokes[y * w + 2] = 1 }
        let seed = GraphiteSketch.seed(strokes, width: w, height: h)
        #expect(seed == 4 * w + 10)
        let arrivals = GraphiteSketch.arrivals(strokes, width: w, height: h)
        #expect(arrivals.count == w * h)
        #expect(arrivals[seed] == 0)
        #expect(arrivals.allSatisfy { $0 >= 0 && $0 <= 1 })
        // Eight cells along the stroke come before four across the paper.
        #expect(arrivals[4 * w + 18] < arrivals[0 * w + 10])
        // The stroke down column 2 is reached along row 4, then down it, before the paper beside it.
        #expect(arrivals[0 * w + 2] < arrivals[0 * w + 5])
        // Malformed input draws no race.
        #expect(GraphiteSketch.arrivals([0, 1], width: 3, height: 1).isEmpty)
    }

    /// A pixel as the shader draws it: nothing before the race reaches it, then its stroke with
    /// the warm point fresh behind the race's front and gone a little later; the photo's color
    /// drains only near a stroke, and only once reached.
    @Test func theGraphiteDrawsBehindAMovingPoint() {
        let before = GraphiteSketch.shade(arrival: 0.4, stroke: 1, halo: 1, progress: 0.39)
        #expect(before == GraphiteSketch.Shade(ink: 0, point: 0, wash: 0))
        // Just reached: the point, at full pressure.
        let fresh = GraphiteSketch.shade(arrival: 0.4, stroke: 1, halo: 1, progress: 0.4 + GraphiteSketch.edge)
        #expect(fresh.point > 0.6 && fresh.ink > fresh.point && fresh.ink <= 1)
        #expect(abs(fresh.wash - GraphiteSketch.wash) < 1e-9)
        // Long passed: the pencil's own grey, no point left.
        let passed = GraphiteSketch.shade(arrival: 0.4, stroke: 1, halo: 1, progress: 0.4 + 2 * GraphiteSketch.fresh)
        #expect(passed.point == 0 && abs(passed.ink - GraphiteSketch.pencil) < 1e-9)
        // A faint stroke is faint; bare paper far from any stroke keeps the photo.
        #expect(GraphiteSketch.shade(arrival: 0.1, stroke: 0.3, halo: 1, progress: 1).ink < 0.3)
        #expect(GraphiteSketch.shade(arrival: 0.1, stroke: 0, halo: 0, progress: 1) == GraphiteSketch.Shade(ink: 0, point: 0, wash: 0))
    }

    /// The graphite is the painting's own line drawing: a line of the drawing map is a stroke and
    /// its neighbourhood drains, bare paper far from it keeps the photo; a contour the drawing
    /// misses is drawn too, thinner; and the race reaches every pixel, along the lines first.
    @Test func theGraphiteDrawsTheLinesFound() async throws {
        let w = 96, h = 64
        var drawing = [UInt8](repeating: 0, count: w * h), contours = [UInt8](repeating: 0, count: w * h)
        // The drawing: a line along row 30. The contours: a line down column 70.
        for x in 0..<w { drawing[30 * w + x] = 230 }
        for y in 0..<h { contours[y * w + 70] = 255 }
        let lines = LineArtInput(
            drawing: EdgeMap(width: w, height: h, values: drawing), contours: EdgeMap(width: w, height: h, values: contours),
            detector: .drawingAndContours)
        let strokes = GraphiteSketch.strokes(lines)
        #expect(strokes[30 * w + 20] > 0.7)
        #expect(strokes[10 * w + 70] > 0.5 && strokes[10 * w + 70] < strokes[30 * w + 20] + 0.2)
        #expect(strokes[10 * w + 20] == 0)
        let halo = GraphiteSketch.halo(strokes, width: w, height: h)
        #expect(halo[30 * w + 20] > 0.2 && halo[32 * w + 20] > 0.1 && halo[10 * w + 20] < 0.01)

        let sheet = FormingPlan.Sheet(paper: SIMD3(0.95, 0.94, 0.9), ink: SIMD3(0.1, 0.1, 0.12))
        let made = try #require(await GraphiteSketch.draw(lines, sheet: sheet))
        #expect(made.map.width == w && made.map.height == h)
        let line = try Self.pixel(of: made.map, x: 20, y: 30), paper = try Self.pixel(of: made.map, x: 20, y: 10)
        #expect(line.green > 0.6 && line.blue > 0.2)
        #expect(paper.green < 0.01 && paper.blue < 0.01)
        // Along the drawn line the race comes sooner than across the paper as far away.
        let along = try Self.pixel(of: made.map, x: 90, y: 30), across = try Self.pixel(of: made.map, x: 20, y: 2)
        #expect(along.red < across.red)
    }

    /// A pixel's red, green and blue (premultiplied), 0…1, in an image.
    private static func pixel(of image: CGImage, x: Int, y: Int) throws -> (red: Double, green: Double, blue: Double) {
        let context = try #require(CGContext(
            data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        // The one pixel is the image's (x, y), y from the top.
        context.draw(image, in: CGRect(x: -x, y: y + 1 - image.height, width: image.width, height: image.height))
        let data = try #require(context.data)
        func channel(_ k: Int) -> Double { Double(data.load(fromByteOffset: k, as: UInt8.self)) / 255 }
        return (channel(0), channel(1), channel(2))
    }

    /// The numbers' twinkles: one per label up to the limit, spread over the page, each lit only
    /// while the front passes.
    @Test func theNumbersComeOutLikeStars() {
        let template = Fixtures.mosaic
        let all = FormingShow.Stars(template)
        #expect(all.labels.count == template.labels.count)
        let few = FormingShow.Stars(template, limit: 10)
        #expect(few.labels.count <= 10 && few.labels.count >= 5)
        for label in all.labels {
            #expect(label.x >= 0 && label.x <= 1)
            #expect(label.y >= 0 && label.y <= Float(template.height) / Float(template.width))
            #expect(label.z > 0)
        }
        #expect(FormingShow.Stars.twinkle(arrival: 0.4, progress: 0.3) == 0)
        #expect(FormingShow.Stars.twinkle(arrival: 0.4, progress: 0.4 + FormingShow.Stars.life / 2) > 0.99)
        #expect(FormingShow.Stars.twinkle(arrival: 0.4, progress: 0.4 + FormingShow.Stars.life) < 1e-9)
        #expect(FormingShow.Stars.twinkle(arrival: 0.4, progress: 0.9) == 0)
    }

    private static func image() -> CGImage? {
        guard let context = CGContext(
            data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        return context.makeImage()
    }
}
