import CoreGraphics
import Foundation
import PaintCore
import SwiftUI
import Testing
import UIKit
@testable import PaintByNumber

/// A painting opened from the gallery lands as its thumbnail, which the painting then replaces
/// (`ArtworkPaintingView.waitingPage`): the thumbnail has to lie exactly where the canvas opens
/// the page, on every screen, or the painting jumps as it comes (painting-company row 364: it
/// was centered on the whole screen, and moved up and grew on an iPhone).
@MainActor
struct OpeningPlaceTests {
    /// Screens in points as the painting has them (no status bar): the safe area's top and bottom
    /// (and sides, on a phone on its side), and whether the width is regular.
    private struct Screen {
        var name: String
        var size: CGSize
        var safe: EdgeInsets
        var regular: Bool
    }

    private static let screens: [Screen] = [
        Screen(name: "iPhone SE", size: CGSize(width: 375, height: 667), safe: EdgeInsets(), regular: false),
        Screen(name: "iPhone mini", size: CGSize(width: 375, height: 812), safe: EdgeInsets(top: 50, leading: 0, bottom: 34, trailing: 0), regular: false),
        Screen(name: "iPhone 17 Pro", size: CGSize(width: 402, height: 874), safe: EdgeInsets(top: 62, leading: 0, bottom: 34, trailing: 0), regular: false),
        Screen(name: "iPhone 17 Pro Max", size: CGSize(width: 440, height: 956), safe: EdgeInsets(top: 62, leading: 0, bottom: 34, trailing: 0), regular: false),
        Screen(name: "iPhone on its side", size: CGSize(width: 874, height: 402), safe: EdgeInsets(top: 0, leading: 62, bottom: 21, trailing: 62), regular: false),
        Screen(name: "iPhone Duo closed", size: CGSize(width: 466, height: 678), safe: EdgeInsets(top: 44, leading: 0, bottom: 20, trailing: 0), regular: false),
        Screen(name: "iPad mini", size: CGSize(width: 744, height: 1133), safe: EdgeInsets(top: 0, leading: 0, bottom: 20, trailing: 0), regular: true),
        Screen(name: "iPad 11-inch", size: CGSize(width: 834, height: 1210), safe: EdgeInsets(top: 0, leading: 0, bottom: 20, trailing: 0), regular: true),
        Screen(name: "iPad 13-inch", size: CGSize(width: 1032, height: 1376), safe: EdgeInsets(top: 0, leading: 0, bottom: 20, trailing: 0), regular: true),
        Screen(name: "iPad 13-inch on its side", size: CGSize(width: 1376, height: 1032), safe: EdgeInsets(top: 0, leading: 0, bottom: 20, trailing: 0), regular: true),
        Screen(name: "iPad in Slide Over", size: CGSize(width: 375, height: 1376), safe: EdgeInsets(top: 0, leading: 0, bottom: 20, trailing: 0), regular: false),
    ]

    /// The thumbnail's place is where a canvas laid out by `PaintView`'s recipe fits its page: every
    /// screen above, a landscape, a portrait and a square picture, few paints and many, a painting
    /// under way and one finished.
    @Test func theThumbnailLiesWhereTheCanvasOpensThePage() throws {
        _ = try #require(RenderContext.shared)
        let pictures = [(480, 320), (320, 480), (400, 400)].map { width, height in
            SyntheticTemplate.make(.init(width: width, height: height, columns: 6, rows: 6, seed: 3))
        }
        for screen in Self.screens {
            for template in pictures {
                let session = PaintingSession(template: template)
                let size = CGSize(width: template.width, height: template.height)
                for (colors, isComplete) in [(8, false), (30, false), (22, true)] {
                    let opening = PaintingLayout.Opening(size: size, colors: colors, isComplete: isComplete)
                    let inside = CGSize(
                        width: screen.size.width - screen.safe.leading - screen.safe.trailing,
                        height: screen.size.height - screen.safe.top - screen.safe.bottom)
                    let place = ArtworkPaintingView.waitingPlace(
                        of: opening, size: inside, safe: screen.safe, regularWidth: screen.regular,
                        dynamicTypeSize: .large, rows: .auto, foldPlace: nil, rightToLeft: false)

                    // The canvas as `PaintView` lays it: its frame and insets from the same recipe.
                    let inputs = PaintingLayout.screen(
                        size: inside, safe: screen.safe, regularWidth: screen.regular, dynamicTypeSize: .large,
                        rows: .auto, colors: colors, isComplete: isComplete, foldPlace: nil, rightToLeft: false)
                    let layout = PaintingLayout(inputs)
                    let canvasRect = layout.canvasRect(inputs: inputs, rightToLeft: false)
                    let canvas = CanvasView(session: session)
                    canvas.frame = canvasRect
                    canvas.chromeInsets = PaintingLayout.uiInsets(layout.canvasInsets, rightToLeft: false)
                    canvas.layoutIfNeeded()
                    let drawn = canvas.templateFrame.offsetBy(dx: canvasRect.minX, dy: canvasRect.minY)
                    #expect(
                        StartHandoffPlan.matches(place, drawn),
                        "\(screen.name), \(size), \(colors) paints, finished \(isComplete): \(place) vs \(drawn)")
                }
            }
        }
    }

    /// Right to left, the thumbnail's place is the left-to-right one mirrored, the palette beside the
    /// page on the other side; and the safe area a left-to-right view reads is turned round first.
    @Test func rightToLeftMirrorsThePlace() {
        let screen = Self.screens.first { $0.name == "iPad 13-inch on its side" }!
        let opening = PaintingLayout.Opening(size: CGSize(width: 1000, height: 672), colors: 22, isComplete: false)
        let inside = CGSize(width: screen.size.width, height: screen.size.height - screen.safe.bottom)
        func place(_ rightToLeft: Bool) -> CGRect {
            ArtworkPaintingView.waitingPlace(
                of: opening, size: inside, safe: screen.safe, regularWidth: true, dynamicTypeSize: .large, rows: .auto,
                foldPlace: nil, rightToLeft: rightToLeft)
        }
        let leftToRight = place(false), rightToLeft = place(true)
        #expect(abs(rightToLeft.minX - (screen.size.width - leftToRight.maxX)) < 0.01)
        #expect(abs(rightToLeft.minY - leftToRight.minY) < 0.01)

        let read = EdgeInsets(top: 1, leading: 2, bottom: 3, trailing: 4)
        #expect(ArtworkPaintingView.directed(read, rightToLeft: true) == EdgeInsets(top: 1, leading: 4, bottom: 3, trailing: 2))
        #expect(ArtworkPaintingView.directed(read, rightToLeft: false) == read)
    }
}
