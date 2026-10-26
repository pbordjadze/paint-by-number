import CoreGraphics
import Foundation
import PaintCore
import SwiftUI
import Testing
import UIKit
@testable import PaintByNumber

/// Where the painting screen puts its page (`PaintingLayout`), which the create flow reads to put
/// its picture there before the painting opens (`StartHandoff`): the place has to be the canvas's
/// own, or the picture would jump as the canvas takes over.
@MainActor
struct PaintingLayoutTests {
    /// The Great Wave's page as CI's simulators' canvases put it (October 25), status bar hidden,
    /// 22 paints: at y 300 on an iPhone 17 Pro and 294.5 on a 13-inch iPad Pro, each within the
    /// point its scroll view rounds the camera to.
    @Test func thePageIsWhereCIsCanvasesPutIt() {
        let template = CGSize(width: 1000, height: 671.5846994535519)
        let phone = inputs(screen: CGSize(width: 402, height: 874), top: 62, bottom: 34, regular: false)
        let onPhone = PaintingLayout(phone).page(of: template, inputs: phone, rightToLeft: false)
        #expect(abs(onPhone.minX - 16) < 0.01 && abs(onPhone.width - 370) < 0.01)
        #expect(abs(onPhone.minY - 300) < 1)

        let pad = inputs(screen: CGSize(width: 1032, height: 1376), top: 0, bottom: 20, regular: true)
        let onPad = PaintingLayout(pad).page(of: template, inputs: pad, rightToLeft: false)
        #expect(abs(onPad.minX - 16) < 0.01 && abs(onPad.width - 1000) < 0.01)
        #expect(abs(onPad.minY - 294.5) < 1)
    }

    /// The canvas, laid out with the layout's insets, fits its page exactly where the layout says,
    /// on a phone, an iPad upright and an iPad on its side (the palette beside the page).
    @Test func theCanvasFitsItsPageWhereTheLayoutSays() throws {
        _ = try #require(RenderContext.shared)
        let template = Fixtures.mosaic
        let session = PaintingSession(template: template)
        let size = CGSize(width: template.width, height: template.height)
        for (screen, top, bottom, regular) in [
            (CGSize(width: 402, height: 874), 62.0, 34.0, false),
            (CGSize(width: 1032, height: 1376), 0.0, 20.0, true),
            (CGSize(width: 1376, height: 1032), 0.0, 20.0, true),
        ] {
            let inputs = inputs(
                screen: screen, top: top, bottom: bottom, regular: regular,
                colors: PaletteBar.visibleColorCount(template))
            let layout = PaintingLayout(inputs)
            #expect(layout.palette.side == (screen.width > screen.height))
            let canvas = CanvasView(session: session)
            canvas.frame = CGRect(origin: .zero, size: screen)
            canvas.chromeInsets = PaintingLayout.uiInsets(layout.canvasInsets, rightToLeft: false)
            canvas.layoutIfNeeded()
            let expected = layout.page(of: size, inputs: inputs, rightToLeft: false)
            #expect(StartHandoffPlan.matches(canvas.templateFrame, expected), "\(screen): \(canvas.templateFrame) vs \(expected)")
        }
    }

    /// A new painting's palette shows every paint that has an area, as its session does.
    @Test func aNewPaintingShowsEveryPaintWithAnArea() {
        let template = Fixtures.mosaic
        let session = PaintingSession(template: template)
        #expect(PaletteBar.visibleColorCount(template) == PaletteBar.visibleColors(session).count)
    }

    private func inputs(
        screen: CGSize, top: CGFloat, bottom: CGFloat, regular: Bool, colors: Int = 22
    ) -> PaintingLayout.Inputs {
        PaintingLayout.Inputs(
            size: CGSize(width: screen.width, height: screen.height - top - bottom),
            safe: EdgeInsets(top: top, leading: 0, bottom: bottom, trailing: 0), regularWidth: regular,
            dynamicTypeSize: .large, rows: .auto, colors: colors, isComplete: false)
    }
}
