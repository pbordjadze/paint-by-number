import CoreGraphics
import Foundation
import PaintCore
import SwiftUI
import Testing
import UIKit
@testable import PaintByNumber

/// The painting screen on an iPhone Duo (`PaintingLayout.Mode`): half open, the painting has a page
/// of its own either side of the fold and nothing is laid on the crease; and the canvas keeps the
/// painter's place as the Duo opens, closes or folds (`CanvasView.layoutSubviews`).
@MainActor
struct DuoLayoutTests {
    /// The inner display upright and on its side, in points, as the iPhone Duo simulator has it.
    private static let upright = CGSize(width: 669, height: 951)
    private static let onItsSide = CGSize(width: 951, height: 669)
    private static let picture = CGSize(width: 480, height: 640)

    /// Half open like a laptop: the painting stands above the fold, the bar and the whole palette
    /// lie below it, and nothing crosses it.
    @Test func halfOpenLikeALaptopThePaintingStandsAboveTheFold() {
        let fold = CGRect(x: 0, y: 460, width: 669, height: 32)
        let inputs = inputs(Self.upright, fold: fold)
        let layout = PaintingLayout(inputs)
        #expect(layout.mode == .easel)
        let canvas = layout.canvasRect(inputs: inputs, rightToLeft: false)
        #expect(canvas.minY == 0 && canvas.maxY == fold.minY && canvas.width == Self.upright.width)
        let page = layout.page(of: Self.picture, inputs: inputs, rightToLeft: false)
        #expect(page.minY >= inputs.safe.top && page.maxY <= fold.minY)
        #expect(layout.controls.top == fold.maxY)
        // The bar and the palette fit the half below the fold, the palette every color at once.
        let bars = PaintingLayout.topGap + PaintingLayout.barHeight(regularWidth: true) + PaintingLayout.canvasGap
            + layout.palette.thickness + PaintingLayout.bottomGap
        #expect(fold.maxY + bars <= Self.upright.height - inputs.safe.bottom)
        #expect(!layout.palette.side)
        #expect(layout.palette.lines == layout.palette.metrics.lines(
            count: inputs.colors, length: Self.upright.width - 2 * PaintingLayout.edge, maxLines: .max))
    }

    /// Half open like a book: the painting on the leading page, the bars on the trailing one;
    /// mirrored in a right-to-left layout, which gives the fold from the leading edge too.
    @Test func halfOpenLikeABookThePaintingHasThePageBesideTheFold() {
        let fold = CGRect(x: 460, y: 0, width: 32, height: 669)
        let inputs = inputs(Self.onItsSide, fold: fold)
        let layout = PaintingLayout(inputs)
        #expect(layout.mode == .book)
        let canvas = layout.canvasRect(inputs: inputs, rightToLeft: false)
        #expect(canvas.minX == 0 && canvas.maxX == fold.minX && canvas.height == Self.onItsSide.height)
        let page = layout.page(of: Self.picture, inputs: inputs, rightToLeft: false)
        #expect(page.maxX <= fold.minX && page.minY >= inputs.safe.top)
        #expect(layout.controls.leading == fold.maxX)

        let mirrored = layout.canvasRect(inputs: inputs, rightToLeft: true)
        #expect(mirrored.minX == Self.onItsSide.width - fold.minX && mirrored.maxX == Self.onItsSide.width)
        let mirroredPage = layout.page(of: Self.picture, inputs: inputs, rightToLeft: true)
        #expect(mirroredPage.minX >= Self.onItsSide.width - fold.minX)
    }

    /// Flat or closed (no fold), and for a fold that leaves no room for a page either side of it or
    /// doesn't cross the screen, the screen stays whole, laid out as on any other device.
    @Test func withoutAFoldThatSharesItOutTheScreenStaysWhole() {
        let flat = inputs(Self.onItsSide, fold: nil)
        let whole = PaintingLayout(flat)
        #expect(whole.mode == .whole)
        #expect(whole.canvasFrame == EdgeInsets() && whole.controls == flat.safe)
        #expect(whole.palette.side)
        for fold in [
            CGRect(x: 0, y: 100, width: 669, height: 32),  // too near the top for a page above it
            CGRect(x: 0, y: 460, width: 300, height: 32),  // not across the screen
            CGRect.zero,
        ] {
            #expect(PaintingLayout(inputs(Self.upright, fold: fold)).mode == .whole, "\(fold)")
        }
    }

    /// The canvas laid out in its page fits the page where the layout says, as the create flow's
    /// picture expects it (`StartHandoff`).
    @Test func theCanvasFitsItsPageBesideTheFoldWhereTheLayoutSays() throws {
        _ = try #require(RenderContext.shared)
        let template = Fixtures.mosaic
        let size = CGSize(width: template.width, height: template.height)
        for (screen, fold) in [
            (Self.upright, CGRect(x: 0, y: 460, width: 669, height: 32)),
            (Self.onItsSide, CGRect(x: 460, y: 0, width: 32, height: 669)),
        ] {
            let inputs = inputs(screen, fold: fold, colors: PaletteBar.visibleColorCount(template))
            let layout = PaintingLayout(inputs)
            let rect = layout.canvasRect(inputs: inputs, rightToLeft: false)
            let canvas = CanvasView(session: PaintingSession(template: template))
            canvas.frame = rect
            canvas.chromeInsets = PaintingLayout.uiInsets(layout.canvasInsets, rightToLeft: false)
            canvas.layoutIfNeeded()
            let shown = canvas.templateFrame.offsetBy(dx: rect.minX, dy: rect.minY)
            let expected = layout.page(of: size, inputs: inputs, rightToLeft: false)
            #expect(StartHandoffPlan.matches(shown, expected), "\(screen): \(shown) vs \(expected)")
        }
    }

    /// Closed to open, open to half open: a painting zoomed in keeps its scale and its center, the
    /// new room showing more or less of it around them; a fitted one fits its new room.
    @Test func theCanvasKeepsThePaintersPlaceAsTheDuoOpensAndFolds() {
        let template = Fixtures.mosaic
        let canvas = CanvasView(session: PaintingSession(template: template))
        canvas.initialCamera = CanvasCamera(zoom: 3, center: SIMD2(240, 320))
        canvas.frame = CGRect(x: 0, y: 0, width: 466, height: 678)  // closed: the outer display
        canvas.chromeInsets = UIEdgeInsets(top: 60, left: 0, bottom: 120, right: 40)
        canvas.layoutIfNeeded()
        let scale = canvas.templateFrame.width / CGFloat(template.width)
        let center = canvas.camera.center

        for (frame, insets) in [
            (CGRect(origin: .zero, size: Self.onItsSide), UIEdgeInsets(top: 70, left: 0, bottom: 10, right: 190)),
            (CGRect(x: 0, y: 0, width: 460, height: 669), UIEdgeInsets(top: 30, left: 0, bottom: 30, right: 6)),
        ] {
            canvas.frame = frame
            canvas.chromeInsets = insets
            canvas.layoutIfNeeded()
            #expect(abs(canvas.templateFrame.width / CGFloat(template.width) - scale) < 0.001, "\(frame)")
            #expect(abs(canvas.camera.center.x - center.x) < 1 && abs(canvas.camera.center.y - center.y) < 1, "\(frame)")
        }

        canvas.zoomToFit(animated: false)
        canvas.frame = CGRect(x: 0, y: 0, width: 466, height: 678)
        canvas.chromeInsets = UIEdgeInsets(top: 60, left: 0, bottom: 120, right: 40)
        canvas.layoutIfNeeded()
        #expect(abs(canvas.relativeZoom - 1) < 0.001, "a fitted painting fits its new room")
    }

    private func inputs(_ screen: CGSize, fold: CGRect?, colors: Int = 24) -> PaintingLayout.Inputs {
        let safe = EdgeInsets(top: 24, leading: 0, bottom: 20, trailing: 0)
        return PaintingLayout.Inputs(
            size: CGSize(width: screen.width - safe.leading - safe.trailing, height: screen.height - safe.top - safe.bottom),
            safe: safe, regularWidth: true, dynamicTypeSize: .large, rows: .auto, colors: colors, isComplete: false,
            fold: fold)
    }
}
