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
            #expect(FormingShow.done(madeAt: made, graphiteBegan: began) == made + FormingShow.fuse)
        }
        // No graphite (made before its drawing was): lit at once.
        #expect(FormingShow.fuseLit(madeAt: 3, graphiteBegan: nil) == 3)
    }

    /// Made almost at once, the graphite still shows a moment, and never more than that: the
    /// show ends at most `longestTail` after the template is made, whatever the clocks say.
    @Test func itNeverOutlastsTheMakingByMoreThanASmallTail() {
        let began = 10.0
        for making in [0, 0.1, 0.3, FormingShow.graphiteAtLeast, 1, 4] {
            let made = began + making
            let done = FormingShow.done(madeAt: made, graphiteBegan: began)
            #expect(done - made <= FormingShow.longestTail + 1e-9)
            #expect(done - made >= FormingShow.fuse - 1e-9)
            #expect(FormingShow.fuseLit(madeAt: made, graphiteBegan: began) >= began + min(making, FormingShow.graphiteAtLeast) - 1e-9)
        }
        // A graphite stamped after the making (a clock gone wrong) waits no longer either.
        #expect(FormingShow.done(madeAt: 10, graphiteBegan: 50) - 10 <= FormingShow.longestTail + 1e-9)
        // The tail is about the plain forming's: the fuse is its drawing in, and the graphite's
        // least is under half a second at full speed.
        #expect(FormingShow.fuse == FormingPlan.drawIn)
        #expect(FormingShow.graphiteAtLeast <= StartHandoffPlan.glide)
        #expect(FormingShow.longestTail <= 2.5 * StartHandoffPlan.glide)
        // The numbers take no time of their own: the glide's settling.
        #expect(FormingShow.stars == StartHandoffPlan.settle)
        // The lift waits for the show, and no longer than its longest.
        #expect(FormingPlan.liftWait(until: 5 + FormingShow.longestTail, now: 5) == FormingShow.longestTail)
    }

    /// Each beat runs from 0 to 1 and stays there, rising all the way.
    @Test func theBeatsRunFromNothingToWhole() {
        let beats: [(Double) -> Double] = [
            FormingShow.graphiteProgress(since:), FormingShow.fuseProgress(since:), FormingShow.starsProgress(since:),
        ]
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
        #expect(FormingShow.graphiteProgress(since: FormingShow.graphiteSweep) == 1)
        #expect(FormingShow.fuseProgress(since: FormingShow.fuse) == 1)
        #expect(FormingShow.starsProgress(since: FormingShow.stars) == 1)
    }

    /// A tap before the template is made goes to the plain forming; after, to the painting.
    @Test func aTapSkips() {
        #expect(FormingShow.skip(isMade: false) == .toPlainLines)
        #expect(FormingShow.skip(isMade: true) == .toPainting)
        // Skipped to the painting, the lift waits for nothing (the preview says it is done now).
        #expect(FormingPlan.liftWait(until: 7, now: 7) == 0)
        // The moments skipped to the painting: the fuse is whole at once.
        let now = Date.now
        let skipped = FormingMoments(fuseLit: now.addingTimeInterval(-FormingShow.fuse))
        #expect(skipped.fuseProgress(at: now) == 1)
    }

    /// The preview's moments: the graphite spreads from when it began, the fuse from when it is
    /// lit (which may be a moment ahead), demos hold either, and nothing moves past their ends.
    @Test func theMomentsFollowTheClock() throws {
        let image = try #require(Self.image())
        let began = Date(timeIntervalSinceReferenceDate: 1000)
        var moments = FormingMoments(graphite: image, graphiteBegan: began)
        #expect(moments.graphiteProgress(at: began) == 0)
        #expect(moments.graphiteProgress(at: began.addingTimeInterval(FormingShow.graphiteSweep)) == 1)
        #expect(moments.fuseProgress(at: began.addingTimeInterval(5)) == 0)
        #expect(moments.movesUntil == began.addingTimeInterval(FormingShow.graphiteSweep))

        let lit = began.addingTimeInterval(FormingShow.graphiteAtLeast)
        moments.fuseLit = lit
        #expect(moments.fuseProgress(at: lit.addingTimeInterval(-0.1)) == 0)
        #expect(moments.fuseProgress(at: lit.addingTimeInterval(FormingShow.fuse)) == 1)
        #expect(moments.movesUntil == max(began.addingTimeInterval(FormingShow.graphiteSweep), lit.addingTimeInterval(FormingShow.fuse)))

        // No graphite drawing, no graphite.
        #expect(FormingMoments(graphiteBegan: began).graphiteProgress(at: began.addingTimeInterval(9)) == 0)
        // Held, nothing moves.
        let held = FormingMoments(graphite: image, graphiteBegan: began, fuseLit: lit, heldGraphite: 0.55, heldFuse: 0.5)
        #expect(held.graphiteProgress(at: .distantFuture) == 0.55)
        #expect(held.fuseProgress(at: .distantFuture) == 0.5)
        #expect(held.movesUntil == nil)
    }

    /// The front reaches its middle first and every corner by the end, farther points later.
    @Test func theFrontCoversThePicture() {
        let rect = CGRect(x: 20, y: 40, width: 300, height: 500)
        let margin: CGFloat = 12
        let middle = FormingShow.Front.origin(in: rect)
        #expect(FormingShow.Front.arrival(of: middle, in: rect, margin: margin) == 0)
        for corner in [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
                       CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.maxX, y: rect.maxY)] {
            let arrival = FormingShow.Front.arrival(of: corner, in: rect, margin: margin)
            #expect(arrival > 0 && arrival < 1)
            // Whole at 1, its soft edge past every corner.
            #expect(FormingShow.Front.path(in: rect, progress: 1, margin: margin).contains(corner))
        }
        for angle in stride(from: 0.0, to: 2 * Double.pi, by: 0.4) {
            var last = 0.0
            for step in 1...10 {
                let r = Double(step) * 20
                let point = CGPoint(x: middle.x + CGFloat(r * cos(angle)), y: middle.y + CGFloat(r * sin(angle)))
                let arrival = FormingShow.Front.arrival(of: point, in: rect, margin: margin)
                #expect(arrival > last)
                last = arrival
            }
        }
        #expect(FormingShow.Front.path(in: rect, progress: 0, margin: margin).isEmpty)
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
