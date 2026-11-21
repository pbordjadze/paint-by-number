import CoreGraphics
import Foundation
import Testing
import UIKit
@testable import PaintByNumber

/// The picture forming as one act (`FormingPlan`, painting-company row 293): which wait it is,
/// what shows over the photo and when, how the picture goes to the page, and that it takes the
/// hand-off no longer. SideStore and Debug builds; the release keeps its passage.
@MainActor
struct FormingTests {
    @Test func onlyAPictureWithAPhotoPickedOnThePaintPageForms() {
        #expect(FormingPlan.forms(paintsNow: true, isScratch: false, isDrawing: false))
        // The settings' preview, a page from scratch and a drawing keep what they show.
        #expect(!FormingPlan.forms(paintsNow: false, isScratch: false, isDrawing: false))
        #expect(!FormingPlan.forms(paintsNow: true, isScratch: true, isDrawing: false))
        #expect(!FormingPlan.forms(paintsNow: true, isScratch: false, isDrawing: true))
    }

    @Test func oneStatusUntilTheTemplateIsMadeThenItsLines() {
        // Whatever stage the making is at, the wait shows the status and nothing over the photo.
        let waiting = FormingPlan.shown(isMade: false, hasFailed: false, reduceMotion: false, playsShow: false)
        #expect(waiting == FormingPlan.Shown(status: true, lines: false))
        // Made: the lines arrive, and the status has no more to say.
        let made = FormingPlan.shown(isMade: true, hasFailed: false, reduceMotion: false, playsShow: false)
        #expect(made == FormingPlan.Shown(status: false, lines: true))
        // A failure says so in the status's place.
        let failed = FormingPlan.shown(isMade: false, hasFailed: true, reduceMotion: false, playsShow: false)
        #expect(failed == FormingPlan.Shown(status: false, lines: false))
    }

    @Test func noLinesArriveUnderReduceMotionOrBeforeTheShow() {
        for (reduceMotion, playsShow) in [(true, false), (false, true), (true, true)] {
            let waiting = FormingPlan.shown(isMade: false, hasFailed: false, reduceMotion: reduceMotion, playsShow: playsShow)
            #expect(waiting == FormingPlan.Shown(status: true, lines: false))
            let made = FormingPlan.shown(isMade: true, hasFailed: false, reduceMotion: reduceMotion, playsShow: playsShow)
            #expect(made == FormingPlan.Shown(status: false, lines: false))
        }
    }

    /// The picture that leaves has lines only where the preview drew them in: with The
    /// Making-of on there are none, a show made or not.
    @Test func linesLeaveOnlyWhereTheyWereDrawnIn() {
        #expect(FormingPlan.hasLines(reduceMotion: false, playsShow: false))
        #expect(!FormingPlan.hasLines(reduceMotion: true, playsShow: false))
        #expect(!FormingPlan.hasLines(reduceMotion: false, playsShow: true))
        #expect(!FormingPlan.hasLines(reduceMotion: true, playsShow: true))
    }

    /// The photo washes and dries toward the paper its page will have, its lines in that
    /// page's ink: dark paper's too.
    @Test func theWashAndTheInkAreThePagesOwn() {
        let light = FormingPlan.Sheet(paper: CanvasPalette.sheetPaperSRGB, ink: CanvasPalette.sheetInkSRGB)
        let dark = FormingPlan.Sheet(paper: CanvasPalette.darkSheetPaperSRGB, ink: CanvasPalette.darkSheetInkSRGB)
        #expect(light != dark)
        #expect(FormingPlan.sheet(.light, interfaceIsDark: false) == light)
        #expect(FormingPlan.sheet(.light, interfaceIsDark: true) == light)
        #expect(FormingPlan.sheet(.dark, interfaceIsDark: false) == dark)
        #expect(FormingPlan.sheet(.automatic, interfaceIsDark: false) == light)
        #expect(FormingPlan.sheet(.automatic, interfaceIsDark: true) == dark)
        // The canvas's own: what `HandoffPage` draws the page with.
        for (paper, isDark) in [(PaperAppearance.light, true), (.dark, false), (.automatic, true)] {
            let palette = CanvasPalette.resolve(paper, interfaceIsDark: isDark)
            let sheet = FormingPlan.sheet(paper, interfaceIsDark: isDark)
            #expect(palette.paper == CanvasColor.linearP3(sRGB: sheet.paper))
            #expect(palette.ink == CanvasColor.linearP3(sRGB: sheet.ink))
        }
    }

    /// Under the departing lines the wash goes on to plain paper as the page comes in, so no
    /// photo shows at the page's edge; without lines there is no wash before that.
    @Test func theWashDriesToPaperUnderTheLines() {
        #expect(FormingPlan.paperOpacity(hasLines: true, dries: false) == FormingPlan.wash)
        #expect(FormingPlan.paperOpacity(hasLines: false, dries: false) == 0)
        #expect(FormingPlan.paperOpacity(hasLines: true, dries: true) == 1)
        #expect(FormingPlan.paperOpacity(hasLines: false, dries: true) == 1)
        // After the short Making-of the photo dried on the preview: all paper from the lift on.
        #expect(FormingPlan.paperOpacity(hasLines: true, dries: false, showed: true) == 1)
    }

    /// The departing picture is one layout carried by one transform: at the start, the middle
    /// and the end of the move its layers, each filling the layout, show in one rect, the
    /// picture's own, and the transform moves evenly as the rect does. A page's shape a
    /// rounding off the photo's splits the difference top and bottom.
    @Test func thePictureTravelsAsOne() {
        let entry = CGRect(x: 46, y: 504, width: 940, height: 648)
        let place = CGRect(x: 18, y: 316, width: 996, height: 687)
        let layout = CGRect(origin: .zero, size: place.size)
        // The photo, the wash, the lines and the page are all laid out on this one rect.
        let layers = Array(repeating: layout, count: 4)
        func rect(_ p: CGFloat) -> CGRect {
            CGRect(
                x: entry.minX + (place.minX - entry.minX) * p, y: entry.minY + (place.minY - entry.minY) * p,
                width: entry.width + (place.width - entry.width) * p, height: entry.height + (place.height - entry.height) * p)
        }
        let travels = ([0, 0.5, 1] as [CGFloat]).map { FormingPlan.carry(layout: layout.size, to: rect($0)) }
        for (p, travel) in zip([0, 0.5, 1] as [CGFloat], travels) {
            let shown = layers.map(travel.applied(to:))
            #expect(Set(shown.map(\.debugDescription)).count == 1, "The layers part at \(p)")
            let target = rect(p)
            #expect(abs(shown[0].width - target.width) < 1e-9)
            #expect(abs(shown[0].midX - target.midX) < 1e-9 && abs(shown[0].midY - target.midY) < 1e-9)
            #expect(abs(shown[0].minY - target.minY) < 0.5 && abs(shown[0].maxY - target.maxY) < 0.5)
        }
        // Arrived, nothing is transformed but its place: the page is drawn as the canvas draws it.
        #expect(travels[2] == PictureTravel(scale: 1, dx: place.minX, dy: place.minY))
        // Half way is half the transform.
        #expect(abs(travels[1].scale - (travels[0].scale + travels[2].scale) / 2) < 1e-9)
        #expect(abs(travels[1].dx - (travels[0].dx + travels[2].dx) / 2) < 1e-9)
        #expect(abs(travels[1].dy - (travels[0].dy + travels[2].dy) / 2) < 1e-9)
    }

    @Test func thePhotoIsCarriedToThePageOrFadesToItUnderReduceMotion() {
        #expect(FormingPlan.passage(forms: true, reduceMotion: false) == .carried)
        #expect(FormingPlan.passage(forms: true, reduceMotion: true) == .crossFade)
        // Any other start is the preview's picture departing, as the release's always is.
        #expect(FormingPlan.passage(forms: false, reduceMotion: false) == .preview)
        #expect(FormingPlan.passage(forms: false, reduceMotion: true) == .preview)
    }

    /// The lines are drawn in long enough to follow, slowed with the hand-off, over a photo
    /// calmed part of the way to the paper; the lift waits for what is left of the drawing and
    /// no longer, and the photo dries in the hand-off's own settling.
    @Test func theLinesAreDrawnInBeforeTheLift() {
        #expect(FormingPlan.drawIn == 1.4 * StartHandoffPlan.glide)
        #expect(FormingPlan.drawIn >= 0.6 && FormingPlan.drawIn / StartHandoffPlan.glide <= 1.6)
        #expect(FormingPlan.wash >= 0.35 && FormingPlan.wash <= 0.5)
        #expect(FormingPlan.feather > 0 && FormingPlan.feather < 0.5)
        let drawn = 5 + FormingPlan.drawIn
        #expect(FormingPlan.liftWait(until: drawn, now: 5) == FormingPlan.drawIn)
        #expect(abs(FormingPlan.liftWait(until: drawn, now: 5 + FormingPlan.drawIn / 2) - FormingPlan.drawIn / 2) < 1e-9)
        // A save that outlasted the drawing waits for nothing, nor does a picture with no lines;
        // a clock gone backward, no longer than the longest drawing (`FormingShow`'s too).
        #expect(FormingPlan.liftWait(until: drawn, now: drawn) == 0)
        #expect(FormingPlan.liftWait(until: drawn, now: 30) == 0)
        #expect(FormingPlan.liftWait(until: nil, now: 5) == 0)
        #expect(FormingPlan.liftWait(until: 1000, now: 5) == max(FormingPlan.drawIn, FormingShow.longestTail))
        #expect(FormingPlan.dries == StartHandoffPlan.settle)
        #expect(FormingPlan.dries <= StartHandoffPlan.glide)
    }

    /// The lines leave the preview as heavy as it drew them: the probe reads the comparison's own
    /// scale, the picture's size beside the painting's on its screen.
    @Test func theProbeReadsTheComparisonsLineScale() throws {
        #expect(CompareView.canvasScale(of: CGSize(width: 400, height: 200), aspect: 2, canvas: CGSize(width: 800, height: 1000)) == 0.5)
        #expect(CompareView.canvasScale(of: CGSize(width: 300, height: 600), aspect: 0.5, canvas: CGSize(width: 800, height: 1000)) == 0.6)
        // No space to compare with: the comparison falls back on its zoom.
        #expect(CompareView.canvasScale(of: CGSize(width: 400, height: 200), aspect: 2, canvas: .zero) == nil)

        let probe = PreviewPictureProbe()
        #expect(probe.lineScale == nil)
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 800, height: 1000)
        let comparison = UIView(frame: CGRect(x: 20, y: 38, width: 400, height: 200))
        window.addSubview(comparison)
        probe.anchor(comparison, aspect: 2, canvas: CGSize(width: 800, height: 1000))
        #expect(probe.lineScale == 0.5)
        probe.anchor(comparison, aspect: 2)
        #expect(probe.lineScale == nil)
    }
}
