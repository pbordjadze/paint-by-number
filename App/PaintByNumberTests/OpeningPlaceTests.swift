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
    /// A screen in points: the safe area (left and right as UIKit has them) with the status bar
    /// showing, as the gallery leaves it, and as the painting has it once the bar has gone.
    private struct Screen {
        var name: String
        var size: CGSize
        var shown: EdgeInsets
        var hidden: EdgeInsets
        var bar: CGRect
        var barHidden = false
        var idiom: UIUserInterfaceIdiom
        var regular: Bool
    }

    private static func insets(top: CGFloat = 0, left: CGFloat = 0, bottom: CGFloat = 0, right: CGFloat = 0) -> EdgeInsets {
        EdgeInsets(top: top, leading: left, bottom: bottom, trailing: right)
    }

    private static let screens: [Screen] = [
        Screen(
            name: "iPhone SE", size: CGSize(width: 375, height: 667), shown: insets(top: 20), hidden: insets(),
            bar: CGRect(x: 0, y: 0, width: 375, height: 20), idiom: .phone, regular: false),
        Screen(
            name: "iPhone mini", size: CGSize(width: 375, height: 812), shown: insets(top: 50, bottom: 34),
            hidden: insets(top: 50, bottom: 34), bar: CGRect(x: 0, y: 0, width: 375, height: 50), idiom: .phone,
            regular: false),
        Screen(
            name: "iPhone 17 Pro", size: CGSize(width: 402, height: 874), shown: insets(top: 62, bottom: 34),
            hidden: insets(top: 62, bottom: 34), bar: CGRect(x: 0, y: 0, width: 402, height: 54), idiom: .phone,
            regular: false),
        Screen(
            name: "iPhone 17 Pro Max", size: CGSize(width: 440, height: 956), shown: insets(top: 62, bottom: 34),
            hidden: insets(top: 62, bottom: 34), bar: CGRect(x: 0, y: 0, width: 440, height: 54), idiom: .phone,
            regular: false),
        Screen(
            name: "iPhone on its side", size: CGSize(width: 874, height: 402), shown: insets(left: 62, bottom: 21, right: 62),
            hidden: insets(left: 62, bottom: 21, right: 62), bar: .zero, barHidden: true, idiom: .phone, regular: false),
        Screen(
            name: "a phone with its bar down the side", size: CGSize(width: 466, height: 678),
            shown: insets(top: 20, bottom: 20, right: 44), hidden: insets(top: 20, bottom: 20),
            bar: CGRect(x: 422, y: 0, width: 44, height: 678), idiom: .phone, regular: false),
        Screen(
            name: "iPad mini", size: CGSize(width: 744, height: 1133), shown: insets(top: 24, bottom: 20),
            hidden: insets(bottom: 20), bar: CGRect(x: 0, y: 0, width: 744, height: 24), idiom: .pad, regular: true),
        Screen(
            name: "iPad 11-inch", size: CGSize(width: 834, height: 1210), shown: insets(top: 24, bottom: 20),
            hidden: insets(bottom: 20), bar: CGRect(x: 0, y: 0, width: 834, height: 24), idiom: .pad, regular: true),
        Screen(
            name: "iPad 13-inch", size: CGSize(width: 1032, height: 1376), shown: insets(top: 24, bottom: 20),
            hidden: insets(bottom: 20), bar: CGRect(x: 0, y: 0, width: 1032, height: 24), idiom: .pad, regular: true),
        Screen(
            name: "iPad 13-inch on its side", size: CGSize(width: 1376, height: 1032), shown: insets(top: 24, bottom: 20),
            hidden: insets(bottom: 20), bar: CGRect(x: 0, y: 0, width: 1376, height: 24), idiom: .pad, regular: true),
    ]

    /// What hiding each screen's bar takes from its safe area.
    @Test func theSafeAreaWithoutTheStatusBarIsPredicted() {
        for screen in Self.screens {
            let bar = ArtworkPaintingView.StatusBarAtOpen.measured(
                screen.shown, barFrame: screen.bar, barHidden: screen.barHidden, fullScreen: true, idiom: screen.idiom,
                screenWidth: screen.size.width)
            #expect(ArtworkPaintingView.StatusBarAtOpen.predicted(bar, insets: screen.shown) == screen.hidden, "\(screen.name)")
            // Once the safe area has followed, it is the painting's as it is.
            #expect(ArtworkPaintingView.StatusBarAtOpen.predicted(bar, insets: screen.hidden) == screen.hidden, "\(screen.name)")
            #expect(ArtworkPaintingView.StatusBarAtOpen.isGone(bar, insets: screen.hidden), "\(screen.name)")
        }
        // A window that isn't the whole screen keeps its bar.
        let pad = Self.screens.first { $0.name == "iPad 13-inch" }!
        #expect(
            ArtworkPaintingView.StatusBarAtOpen.measured(
                pad.shown, barFrame: pad.bar, barHidden: false, fullScreen: false, idiom: .pad, screenWidth: pad.size.width)
                == nil)
    }

    /// On every screen above, for a landscape, a portrait and a square picture, few paints and many,
    /// under way and finished: the thumbnail, laid out while the status bar still shows and again
    /// once the safe area has followed, lies on screen where a canvas laid out as `PaintView` lays
    /// it in the painting's safe area fits its page, within a point.
    @Test func theThumbnailLiesWhereTheCanvasOpensThePage() throws {
        _ = try #require(RenderContext.shared)
        let pictures = [(480, 320), (320, 480), (400, 400)].map { width, height in
            SyntheticTemplate.make(.init(width: width, height: height, columns: 6, rows: 6, seed: 3))
        }
        for screen in Self.screens {
            let bar = ArtworkPaintingView.StatusBarAtOpen.measured(
                screen.shown, barFrame: screen.bar, barHidden: screen.barHidden, fullScreen: true, idiom: screen.idiom,
                screenWidth: screen.size.width)
            for template in pictures {
                let session = PaintingSession(template: template)
                let size = CGSize(width: template.width, height: template.height)
                for (colors, isComplete) in [(8, false), (30, false), (22, true)] {
                    let opening = PaintingLayout.Opening(
                        size: size, colors: colors, isComplete: isComplete, doors: Self.doors(on: screen))
                    let drawn = canvasPage(
                        session, on: screen, colors: colors, isComplete: isComplete, doors: opening.doors)
                    for insets in [screen.shown, screen.hidden] {
                        let reader = CGSize(
                            width: screen.size.width - insets.leading - insets.trailing,
                            height: screen.size.height - insets.top - insets.bottom)
                        let frame = ArtworkPaintingView.waitingFrame(
                            of: opening, readerSize: reader, insets: insets, bar: bar, regularWidth: screen.regular,
                            dynamicTypeSize: .large, rows: .auto, foldPlace: nil, rightToLeft: false)
                        let onScreen = frame.offsetBy(dx: insets.leading, dy: insets.top)
                        #expect(
                            StartHandoffPlan.matches(onScreen, drawn),
                            "\(screen.name), \(size), \(colors) paints, finished \(isComplete), top \(insets.top): \(onScreen) vs \(drawn)")
                    }
                }
            }
        }
    }

    /// Right to left with uneven sides (a palette beside the page on an iPad on its side): the
    /// thumbnail is where the right-to-left painting screen puts the page.
    @Test func rightToLeftKeepsThePlace() {
        let screen = CGSize(width: 1376, height: 1032)
        // Read left to right, as the waiting page reads them.
        let read = Self.insets(left: 10, bottom: 20, right: 30)
        let opening = PaintingLayout.Opening(size: CGSize(width: 1000, height: 672), colors: 22, isComplete: false)
        let reader = CGSize(width: screen.width - 40, height: screen.height - 20)
        let frame = ArtworkPaintingView.waitingFrame(
            of: opening, readerSize: reader, insets: read, bar: nil, regularWidth: true, dynamicTypeSize: .large,
            rows: .auto, foldPlace: nil, rightToLeft: true)
        // The painting screen's own reading, right to left: its leading edge is the right.
        let safe = EdgeInsets(top: 0, leading: 30, bottom: 20, trailing: 10)
        let inputs = PaintingLayout.screen(
            size: reader, safe: safe, regularWidth: true, dynamicTypeSize: .large, rows: .auto, colors: 22,
            isComplete: false, foldPlace: nil, rightToLeft: true)
        let page = PaintingLayout(inputs).page(of: opening.size, inputs: inputs, rightToLeft: true)
        #expect(StartHandoffPlan.matches(frame.offsetBy(dx: 10, dy: 0), page), "\(frame) vs \(page)")
        #expect(PaintingLayout(inputs).palette.side)
        #expect(page.minX > screen.width - page.maxX, "the palette lies on the left, the page on the right")
    }

    /// The page a canvas laid out as `PaintView` lays it on `screen`, its status bar gone, fits
    /// for `session`, in the whole screen's coordinates.
    #if UNRELEASED
    /// A finished painting's panel, its doors under its row, is as tall as the painting screen
    /// counts on before building it (`CompletionBar.panelHeight`): taller, the page moved up as a
    /// finished painting opened. Four doors (a painter's photo) and five (a library picture), on
    /// every screen above that has room for them, in English at the Large size and in German at
    /// the largest the panel allows; a long unnamed title's second line may reach no further than
    /// the canvas's margin round the page.
    @Test func theDoorsPanelIsAsTallAsTheLayoutCountsOn() throws {
        let template = Fixtures.stripes()
        let session = try PaintingSession(template: template, progress: ArtworkFactory.progress(painting: 1, of: template))
        try #require(session.isComplete)
        let cases: [(locale: String, size: DynamicTypeSize, title: String, named: Bool, slack: CGFloat)] = [
            ("en", .large, "October 6", true, 0.5),
            ("de", .xxLarge, "6. Oktober", true, 0.5),
            ("en", .large, "Morning Glories at the Old Mill, No. 2", false, CanvasView.margin),
        ]
        for screen in Self.screens where !screen.name.contains("bar down the side") {
            for count in [3, 4] {
                for test in cases {
                    let doors = PaintingLayout.Doors(count: count, compactHeight: screen.size.height < 500)
                    let safe = screen.hidden
                    let inside = CGSize(
                        width: screen.size.width - safe.leading - safe.trailing,
                        height: screen.size.height - safe.top - safe.bottom)
                    let inputs = PaintingLayout.screen(
                        size: inside, safe: safe, regularWidth: screen.regular, dynamicTypeSize: test.size,
                        rows: .auto, colors: 2, isComplete: true, completionHeight: 1, doors: doors, foldPlace: nil,
                        rightToLeft: false)
                    guard let metrics = PaintingLayout.doorMetrics(doors, inputs: inputs) else { continue }
                    let counted = CompletionBar.panelHeight(metrics, dynamicTypeSize: test.size)
                    #expect(inputs.completionHeight == counted, "\(screen.name): the layout counts on the panel, never on a measurement")
                    let bar = CompletionBar(
                        session: session, title: test.title, share: CompletionShare(), sealBounces: 0, onReplay: {},
                        onStopReplay: {}, onShareTimelapse: {}, onName: test.named ? nil : {}, isNamed: test.named,
                        onClose: {}, doors: metrics, onChange: count == 5 ? {} : nil,
                        original: count == 5 ? OriginalWork.all.values.first : nil)
                        .environment(\.locale, Locale(identifier: test.locale))
                        .environment(\.dynamicTypeSize, test.size)
                    let host = UIHostingController(rootView: bar)
                    let width = inside.width - 2 * PaintingLayout.edge
                    let measured = host.sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude)).height
                    #expect(
                        measured <= counted + test.slack,
                        "\(screen.name), \(count) doors, \(test.locale) \(test.size), \(test.title): measured \(measured), counted \(counted)")
                }
            }
        }
    }
    #endif

    /// The doors after Finished a painting of the library shows there, The Original too (SideStore
    /// and Debug builds; none in the release).
    private static func doors(on screen: Screen) -> PaintingLayout.Doors? {
        #if UNRELEASED
        PaintingLayout.Doors(count: 4, compactHeight: screen.size.height < 500)
        #else
        nil
        #endif
    }

    private func canvasPage(
        _ session: PaintingSession, on screen: Screen, colors: Int, isComplete: Bool, doors: PaintingLayout.Doors?
    ) -> CGRect {
        let safe = screen.hidden
        let inside = CGSize(
            width: screen.size.width - safe.leading - safe.trailing, height: screen.size.height - safe.top - safe.bottom)
        let inputs = PaintingLayout.screen(
            size: inside, safe: safe, regularWidth: screen.regular, dynamicTypeSize: .large, rows: .auto,
            colors: colors, isComplete: isComplete, doors: doors, foldPlace: nil, rightToLeft: false)
        let layout = PaintingLayout(inputs)
        let canvasRect = layout.canvasRect(inputs: inputs, rightToLeft: false)
        let canvas = CanvasView(session: session)
        canvas.frame = canvasRect
        canvas.chromeInsets = PaintingLayout.uiInsets(layout.canvasInsets, rightToLeft: false)
        canvas.layoutIfNeeded()
        return canvas.templateFrame.offsetBy(dx: canvasRect.minX, dy: canvasRect.minY)
    }
}
