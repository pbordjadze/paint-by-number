import CoreGraphics
import Foundation
import Observation
import os
import PaintCore
import StoreKit
import SwiftUI
import TipKit
import UIKit

/// The painting screen: full-bleed Metal canvas, floating Liquid Glass controls on top and
/// the palette at the bottom (trailing edge on a landscape iPad, see `PaletteLayout`). On a
/// half-open iPhone Duo the painting has a page of its own either side of the fold, and the bars
/// and the whole palette the other (`PaintingLayout.Mode`).
///
/// Contract used by the rest of the app: `PaintView(session:title:onClose:)`. Persistence
/// lives outside (observe `session.revision`). With a `sourcePhotoLoader` in the environment
/// the top bar offers the Photo control (see `PhotoPeek`). The gentle tips (`TipDesk`) point at
/// the selected swatch, the top of the canvas, the top bar's controls or the finished page's
/// Replay, one at a time.
///
/// Give Feedback (More, and the Paint menu) captures the painting as it is (`FeedbackCapture`,
/// with the environment's `feedbackSource`) and switches to feedback mode: painting stops, the
/// palette goes, `FeedbackBar` takes the top and `MarkupCanvas` lies over the canvas for drawing;
/// Next opens `FeedbackSheet`.
struct PaintView: View {
    let session: PaintingSession
    var title: String = ""
    var onClose: (() -> Void)?
    /// Names a painting still under the name the app gave it (`Artwork.isNamed`): finished, its
    /// bar's name is tappable (`CompletionBar.onName`). Nil once it has a name.
    var onName: (() -> Void)?
    /// False while the painting has only the name the app gave it (`Artwork.isNamed`).
    var isNamed = true
    /// A painter's own painting, saved in the gallery: finishing it may ask for a rating
    /// (`RatingPrompt`). Refine's Try Painting and the demos don't.
    var asksForRating = false
    /// Where the canvas first looks (demo scenarios); nil = fit.
    var initialCamera: CanvasCamera?
    /// Scales fill animation durations (demo scenarios).
    var fillDurationScale: Float = 1
    /// Told where the template is (global coordinates) once the canvas's first frame is on screen,
    /// and again when a layout moves it: the create flow's picture moves there (`StartHandoff`).
    /// Read when the canvas is made.
    var onTemplateFrame: ((CGRect) -> Void)?
    /// Told once the canvas has drawn this session's first frame (a painting made over in place:
    /// `ArtworkPaintingView` keeps the old screen over it till then).
    var onFirstFrame: (() -> Void)?
    /// ✎ Change (painting-company row 239): the drawing tools on this painting, any time; nil
    /// offers no button (the release, until the drawing tools ship).
    var onChange: (() -> Void)?
    /// False as the screen is left: `ArtworkPaintingView.close`.
    var hidesStatusBar = true

    @State private var controller = CanvasController()
    @Environment(\.startHandoff) private var startHandoff
    @State private var chrome = PaintChromeState()
    @State private var showsNumbers = true
    @State private var confirmRestart = false
    @State private var timelapse: TimelapseRequest?
    @State private var canvasUnavailable = false
    @State private var completionShare = CompletionShare()
    /// Bumped once the completion bar is up after the painting was finished on this screen (not
    /// for a painting opened finished): its seal bounces.
    @State private var sealBounces = 0
    /// Bumped when a painting finished on this screen is the moment to ask for a rating
    /// (`RatingPrompt`); the ask waits for the finale, and leaving the screen cancels it.
    @State private var ratingMoment = 0
    /// This painting has been counted as finished: undoing a fill and finishing again doesn't
    /// count it twice.
    @State private var countedFinish = false
    /// The progress badge names the painting (the top bar's layout that fits has room for it):
    /// the completion bar doesn't name it twice.
    @State private var badgeShowsTitle = false
    /// Whether the top bar's row on screen has Hint: where it doesn't (a phone with ✎ Change),
    /// More offers Show Hint, or a phone had no hint until the bar went quiet.
    @State private var barShowsHint = true
    @State private var peek: PhotoPeek
    @State private var photoUnavailable = false
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.layoutDirection) private var layoutDirection
    /// Where a half-open iPhone Duo's fold lies across the screen (`FoldPlace`), in the safe area.
    @State private var foldPlace: FoldPlace?
    @Environment(\.undoManager) private var undoManager
    @Environment(\.requestReview) private var requestReview
    @Environment(\.sourcePhotoLoader) private var photoLoader
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @Environment(\.accessibilitySwitchControlEnabled) private var switchControlEnabled
    @AppStorage(SettingsKey.paperAppearance) private var paperAppearance = PaperAppearance.default
    @AppStorage(SettingsKey.lineWeight) private var lineWeight = LineWeight.default
    @AppStorage(SettingsKey.paletteRows) private var paletteRows = PaletteRows.default
    @AppStorage(SettingsKey.paletteOrder) private var paletteOrder = PaletteOrder.default
    @AppStorage(SettingsKey.zenMode) private var zenMode = SettingsDefault.zenMode
    @AppStorage(SettingsKey.autoAdvance) private var autoAdvance = SettingsDefault.autoAdvance
    /// Feedback mode while set.
    @State private var feedback: FeedbackDraft?
    /// The white flash of the capture as feedback starts.
    @State private var flashes = false
    /// The thank-you toast's text while it shows.
    @State private var thanks: String?
    /// What Zen Mode does, said as the painter turns it on: the page moving after a fill read as
    /// a fault to a newcomer who had found the switch without its tip (QA, November 7).
    @State private var zenNote: String?
    @State private var zenNoteShowing = 0
    /// The thanks for feedback just sent or shared, waiting for the review sheet to be gone.
    @State private var pendingThanks: String?
    @Environment(\.feedbackSource) private var feedbackSource
    /// Whether ✎ Change waits for the purchase (`UnlimitedPaintings.locksRefine`), which its
    /// button shows before the tap.
    @Environment(UnlimitedPaintings.self) private var paintings: UnlimitedPaintings?
    @Environment(\.displayScale) private var displayScale
    @Environment(\.colorScheme) private var colorScheme
    /// Built out of sight before Start Painting (`PaintScreenWarmup`).
    @Environment(\.paintScreenIsWarmup) private var isWarmup
    #if DEBUG
    @Environment(\.feedbackDemo) private var feedbackDemo
    #endif

    /// Between the bar and the palette on a half-open Duo's book page.
    private static let bookGap: CGFloat = 20
    /// The bars' margins (`PaintingLayout`, whose canvas insets keep the canvas clear of them).
    private static let edge = PaintingLayout.edge
    private static let topGap = PaintingLayout.topGap
    private static let bottomGap = PaintingLayout.bottomGap

    /// How much bigger the bar's buttons and the swatches are (`QuietPainting.scale`), for the
    /// layout's `regularChrome`: a regular width's, but for a phone's on a Duo's book page.
    private func chromeScale(_ regular: Bool) -> CGFloat { PaintingLayout.chromeScale(regularWidth: regular) }
    /// The top bar's height: its round buttons' size, 44 pt on compact widths.
    private func barHeight(_ regular: Bool) -> CGFloat { PaintingLayout.barHeight(regularWidth: regular) }
    private var chromeScheme: ColorScheme { Self.chromeScheme(paper: paperAppearance, system: colorScheme) }

    /// The bars' appearance: dark over dark paper whatever the system's (on a light system the
    /// palette and the completion bar were light slabs on it, and the progress ring's track was
    /// lost in its glass), else the system's.
    static func chromeScheme(paper: PaperAppearance, system: ColorScheme) -> ColorScheme {
        paper.usesDarkPaper(interfaceIsDark: system == .dark) ? .dark : system
    }

    /// `showsPhoto` opens with the photo shown (demo scenarios).
    init(
        session: PaintingSession, title: String = "", onClose: (() -> Void)? = nil, onName: (() -> Void)? = nil,
        isNamed: Bool = true, asksForRating: Bool = false,
        initialCamera: CanvasCamera? = nil, fillDurationScale: Float = 1, showsPhoto: Bool = false,
        onTemplateFrame: ((CGRect) -> Void)? = nil, onFirstFrame: (() -> Void)? = nil, onChange: (() -> Void)? = nil,
        hidesStatusBar: Bool = true
    ) {
        self.onChange = onChange
        self.hidesStatusBar = hidesStatusBar
        self.session = session
        self.title = title
        self.onClose = onClose
        self.onName = onName
        self.isNamed = isNamed
        self.asksForRating = asksForRating
        self.initialCamera = initialCamera
        self.fillDurationScale = fillDurationScale
        self.onTemplateFrame = onTemplateFrame
        self.onFirstFrame = onFirstFrame
        _peek = State(initialValue: PhotoPeek(latched: showsPhoto))
    }

    var body: some View {
        GeometryReader { geo in
            if canvasUnavailable {
                CanvasUnavailableView(onClose: onClose)
            } else {
                canvasAndChrome(geo: geo, layout: layout(in: geo))
            }
        }
        .readsTheFold { foldPlace = $0 }
        // Nothing here takes typing: a keyboard over a sheet (feedback's notes) leaves the
        // canvas where it is.
        .ignoresSafeArea(.keyboard)
        // The canvas runs under the top edge: the clock would sit on the painting.
        .statusBarHidden(hidesStatusBar)
        .background(Color(uiColor: .systemGroupedBackground))
        // Out of sight, the menu bar's commands stay the preview's.
        .focusedSceneValue(\.painting, isWarmup ? nil : PaintingFocus(
            session: session, controller: controller, showsNumbers: $showsNumbers, showsPhoto: photoBinding,
            zenMode: $zenMode, isGivingFeedback: feedback != nil, giveFeedback: startFeedback, replay: replay,
            close: onClose))
        .onAppear {
            guard !isWarmup else { return }
            FeedbackEngine.shared.attach(to: session)
            chrome.undoManager = undoManager
            chrome.hasPhoto = photoLoader != nil
            // A painting just started is opened under the create flow's cover, where a tip's
            // popover can't present: the bench and its tips begin once the cover is gone.
            if startHandoff?.isRunning != true { chrome.observe(session) }
            RenderContext.prewarm()
        }
        .onChange(of: undoManager) { _, manager in chrome.undoManager = manager }
        .onChange(of: startHandoff?.isRunning == true) { _, running in
            guard !running else { return }
            chrome.observe(session)
            // The cover is gone: the color to paint comes in (`PaintCanvas.watchesFirstFrame`).
            controller.revealSelection()
        }
        // Picking the next color follows the palette as it is laid out.
        .onChange(of: colorOrder, initial: true) { _, order in session.colorOrder = order }
        .onChange(of: paletteOrder, initial: true) { _, order in session.advancesToFirstLeft = order.followsProgress }
        .onChange(of: autoAdvance, initial: true) { _, advance in session.autoAdvance = advance }
        .onChange(of: zenMode, initial: true) { was, zen in
            session.flowsToNextArea = zen
            if zen && !isWarmup { PaintTips.used(.benchZen) }
            if zen && !was { sayWhatZenDoes() }
        }
        .onChange(of: reduceMotion, initial: true) { _, reduce in session.reduceMotion = reduce }
        // Choosing a color is something done: the tips' hand has not rested yet.
        .background { SelectionWatch(session: session) { if !isWarmup { chrome.activity() } } }
        // The photo shown, held or kept, is the Photo control used.
        .onChange(of: peek.isShown) { _, shown in
            if shown { PaintTips.used(.benchShowPhoto) }
        }
        .onChange(of: session.isComplete) { was, complete in
            if complete, !was, asksForRating, !countedFinish {
                countedFinish = true
                if RatingPrompt.forLaunch?.paintingFinished() == true { ratingMoment += 1 }
            }
            guard complete, !reduceMotion else { return }
            Task {
                // As the completion bar settles.
                try? await Task.sleep(for: .milliseconds(450))
                sealBounces += 1
            }
        }
        .onDisappear {
            guard !isWarmup else { return }
            undoManager?.removeAllActions(withTarget: session)
            chrome.close()
        }
        .task {
            if let onTemplateFrame { await reportTemplate(to: onTemplateFrame) }
        }
        .task(id: ratingMoment) {
            guard ratingMoment > 0 else { return }
            // After the completion bar, the shine and nightfall have played.
            try? await Task.sleep(for: .seconds(RatingPrompt.delay))
            guard !Task.isCancelled, session.isComplete, !session.isReplaying else { return }
            RatingPrompt.forLaunch?.asked()
            requestReview()
        }
        .task(id: ObjectIdentifier(session)) {
            guard let onFirstFrame else { return }
            for _ in 0..<100 where !Task.isCancelled {
                if controller.isShowingFirstFrame { break }
                try? await Task.sleep(for: .milliseconds(50))
            }
            onFirstFrame()
        }
        .sheet(item: $timelapse) { request in
            TimelapseExportSheet(request: request)
        }
        .sheet(isPresented: reviewsFeedback, onDismiss: thankForFeedback) {
            if let feedback {
                FeedbackSheet(draft: feedback, onSent: feedbackSent)
                    .pageSizedOnPad()
                    .besideTheFold()
            }
        }
        .animation(.snappy, value: thanks)
        .animation(.snappy, value: zenNote)
        #if DEBUG
        .task { await runFeedbackDemo() }
        #endif
    }

    /// The Metal canvas with the floating bars over it.
    private func canvasAndChrome(geo: GeometryProxy, layout: PaintingLayout) -> some View {
        let palette = layout.palette
        // The bars' room within the safe area: all of it, or the controls' page beside a fold.
        let controls = Self.padding(layout.controls, within: geo.safeAreaInsets)
        let controlsWidth = max(0, geo.size.width - controls.leading - controls.trailing)
        return ZStack {
            if layout.mode != .whole {
                // The controls' page, on the painting's own surroundings.
                backdrop.ignoresSafeArea()
            }
            PaintCanvas(
                session: session, controller: controller,
                chromeInsets: layout.canvasInsets,
                showsNumbers: showsNumbers, paperAppearance: paperAppearance,
                lineWeight: lineWeight,
                initialCamera: initialCamera, fillDurationScale: fillDurationScale,
                onPencilAction: { handlePencil($0) }, onUnavailable: { canvasUnavailable = true },
                photoLoader: photoLoader, showsPhoto: peek.isShown,
                onPhotoUnavailable: {
                    photoUnavailable = true
                    peek = PhotoPeek()
                },
                onDismissPhoto: { peek.setLatched(false) },
                onZoomStep: { chrome.tipSignal(.zoomed) },
                onHandChange: { chrome.handChanged($0) },
                isAnnotating: feedback != nil,
                watchesFirstFrame: onTemplateFrame != nil)
                .id(ObjectIdentifier(session))
                .padding(layout.canvasFrame)
                .ignoresSafeArea()

            if let feedback {
                MarkupCanvas(
                    draft: feedback, controller: controller,
                    canvasSize: CGSize(width: session.template.width, height: session.template.height),
                    isMarking: !feedback.isReviewing && !feedback.isSent, tool: feedback.tool, penColor: feedback.penColor)
                    .padding(layout.canvasFrame)
                    .ignoresSafeArea()
            }

            // Tips about the page itself: a card at the top of the page as it first fits, with no
            // arrow (Paul, October 18: "No arrow"; an arrow from the top of the canvas seemed to point
            // at the Photo button on a phone).
            if feedback == nil, PaintTips.desk.pageTip != nil {
                let visiblePadding = layout.visibleCanvasPadding(safe: geo.safeAreaInsets)
                TipView(PaintTips.desk.pageTip, isPresented: nil, arrowEdge: nil)
                    .frame(maxWidth: Self.pageTipWidth)
                    .padding(.horizontal, Self.edge)
                    .padding(.top, pageTipInset(in: CGSize(
                        width: geo.size.width - visiblePadding.leading - visiblePadding.trailing,
                        height: geo.size.height - visiblePadding.top - visiblePadding.bottom)))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(visiblePadding)
                    .environment(\.colorScheme, chromeScheme)
                    .transition(.opacity)
            }

            VStack(spacing: 0) {
                if layout.mode == .book {
                    // The book's controls page: the bar and the palette together in its middle
                    // (the Lamplit Table's Rikyū: "so the controls' page reads as one group").
                    Spacer(minLength: 0)
                }
                Group {
                    if let feedback {
                        FeedbackBar(
                            draft: feedback, width: max(0, controlsWidth - 2 * Self.edge), onDiscard: endFeedback,
                            onNext: {
                                Log.feedback.notice("Next: the review opens")
                                feedback.isReviewing = true
                            })
                    } else {
                        topBar(width: controlsWidth, regular: layout.regularChrome)
                    }
                }
                .padding(.horizontal, Self.edge)
                .padding(.top, Self.topGap)
                .duoProbe("paint-top-bar")
                if layout.mode == .book {
                    Color.clear.frame(height: Self.bookGap)
                } else {
                    Spacer(minLength: 0)
                }
                if let feedback {
                    FeedbackTools(draft: feedback)
                        .padding(.horizontal, Self.edge)
                        .padding(.bottom, Self.bottomGap)
                        .duoProbe("paint-feedback-tools")
                } else if !palette.side || session.isComplete {
                    bottomBar(palette)
                        .padding(.horizontal, Self.edge)
                        .padding(.bottom, Self.bottomGap)
                        .duoProbe("paint-palette")
                }
                if layout.mode != .whole {
                    // The page beside a fold: the palette in the middle of the room below the bar
                    // (with the bar, on a book's page).
                    Spacer(minLength: 0)
                }
            }
            .padding(controls)
            .environment(\.colorScheme, chromeScheme)
            if feedback == nil && palette.side && !session.isComplete {
                HStack {
                    Spacer(minLength: 0)
                    bottomBar(palette)
                        .padding(.trailing, Self.edge)
                        .padding(.top, PaintingLayout.sidePaletteTop(regularWidth: layout.regularChrome))
                        .padding(.bottom, Self.edge)
                        .duoProbe("paint-palette-side")
                }
                .padding(controls)
                .environment(\.colorScheme, chromeScheme)
            }

            if let zenNote {
                Toast(text: zenNote, systemImage: "leaf", edge: .top)
                    .padding(.top, Self.topGap + barHeight(layout.regularChrome) + 12)
                    .padding(.horizontal, 20)
                    .allowsHitTesting(false)
                    .environment(\.colorScheme, chromeScheme)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(layout.mode == .whole ? controls : Self.padding(layout.canvasFrame, within: geo.safeAreaInsets))
                    .accessibilityIdentifier("zen-note")
            }

            if let thanks {
                // Below the top bar, like the painting's other toasts (`ArtworkPaintingView`); beside
                // a fold, at the top of the painting's page, never over the controls' page, whose
                // bar may stand anywhere on it. Taps reach the canvas.
                Toast(text: thanks, systemImage: "checkmark.circle", edge: .top)
                    .padding(.top, Self.topGap + barHeight(layout.regularChrome) + 12)
                    .padding(.horizontal, 20)
                    .allowsHitTesting(false)
                    .environment(\.colorScheme, chromeScheme)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(layout.mode == .whole ? controls : Self.padding(layout.canvasFrame, within: geo.safeAreaInsets))
            }

            if !session.isComplete, !isWarmup {
                // What finishing shows, met once a launch, out of sight. Not in the create flow's
                // own warm-up: its window is never drawn and goes before the seal could bounce.
                FinishWarmup(session: session, share: completionShare)
                    .environment(\.colorScheme, chromeScheme)
            }

            // The capture's flash as feedback starts.
            Color.white
                .opacity(flashes ? 0.5 : 0)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
        // The completion bar slides in for the palette (at the bottom or the side) as the
        // painting is finished; `isComplete` flips inside a fill, with no animation of its own.
        .animation(reduceMotion ? nil : .snappy, value: session.isComplete)
        .animation(.easeInOut(duration: 0.25), value: PaintTips.desk.pageTip != nil)
    }

    /// The controls' page beside a half-open Duo's fold: the canvas's backdrop, as the paper it
    /// lies on (`CanvasPalette.backdropSRGB`).
    private var backdrop: Color {
        let rgb = CanvasPalette.backdropSRGB(paperAppearance, interfaceIsDark: colorScheme == .dark)
        return Color(.sRGB, red: Double(rgb.x), green: Double(rgb.y), blue: Double(rgb.z))
    }

    /// `insets` from the screen's edges as padding within the safe area.
    private static func padding(_ insets: EdgeInsets, within safe: EdgeInsets) -> EdgeInsets {
        EdgeInsets(
            top: max(0, insets.top - safe.top), leading: max(0, insets.leading - safe.leading),
            bottom: max(0, insets.bottom - safe.bottom), trailing: max(0, insets.trailing - safe.trailing))
    }

    /// While the painting is handed over to (`StartHandoff`): once the canvas has its first frame on
    /// screen and its template has stayed where it is for a moment, tells `report` where the
    /// template is, and again whenever it moves (a rotation). In the window's coordinates, as
    /// UIKit has the canvas there at that moment: SwiftUI's global frame of the canvas, read when
    /// it was laid out, put the template a safe area's height too low on CI's simulators.
    private func reportTemplate(to report: (CGRect) -> Void) async {
        var previous: CGRect?
        var announced: CGRect?
        for _ in 0..<600 {
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled, startHandoff?.isRunning == true else { return }
            guard controller.isShowingFirstFrame, let frame = controller.templateFrameInWindow else { continue }
            defer { previous = frame }
            guard frame != announced else { continue }
            // The first time, once two looks agree; after that, as it moves.
            if announced != nil || frame == previous {
                announced = frame
                report(frame)
            }
        }
    }

    // MARK: Layout

    /// The palette's place and the canvas's insets (`PaintingLayout`, which the create flow reads
    /// too, to put its picture where this page will be).
    typealias PaletteLayout = PaintingLayout.Palette

    private func layout(in geo: GeometryProxy) -> PaintingLayout {
        PaintingLayout(PaintingLayout.Inputs(
            size: geo.size, safe: geo.safeAreaInsets, regularWidth: sizeClass == .regular,
            // The painting's colors, not those left: Auto's count of lines went with the colors
            // left, so finishing one re-laid the whole palette (3 rows to 2 on an iPad, the bar
            // wider than the picture and the picture taller; the Mac's QA, November 10). The
            // create flow's hand-off counts them so too.
            dynamicTypeSize: dynamicTypeSize, rows: paletteRows, colors: PaletteBar.visibleColorCount(session.template),
            isComplete: session.isComplete,
            fold: foldPlace == nil
                ? FoldWatch.shared.windowFold(rightToLeft: layoutDirection == .rightToLeft)
                : PaintingLayout.fold(foldPlace, rightToLeft: layoutDirection == .rightToLeft, safe: geo.safeAreaInsets)))
    }


    /// Every color of the palette in its order on screen (finished ones too).
    private var colorOrder: [Int] {
        paletteOrder.arrange(
            Array(0..<session.paletteCount), palette: session.template.palette, remaining: session.remainingByColor)
    }

    /// How far below the top of the visible canvas the page tips lie: just inside the top of the page
    /// as it first fits there, centered within the canvas's margin.
    private func pageTipInset(in visible: CGSize) -> CGFloat {
        let template = session.template
        let room = CGSize(width: visible.width - 2 * CanvasView.margin, height: visible.height - 2 * CanvasView.margin)
        guard template.width > 0, room.width > 0, room.height > 0 else { return 0 }
        let pageHeight = min(room.height, room.width * CGFloat(template.height) / CGFloat(template.width))
        return CanvasView.margin + (room.height - pageHeight) / 2 + min(Self.pageTipDepth, pageHeight / 10)
    }

    /// How far into the page the page tips lie, and how wide they grow.
    private static let pageTipDepth: CGFloat = 32
    private static let pageTipWidth: CGFloat = 420

    // MARK: Top bar

    /// Close, the progress badge, then Photo, Hint, Undo and More, as the first of these that
    /// fits: each badge variant (largest first, down to its ring and percentage) with every
    /// control, then the smallest badge without Hint, which the selected swatch and the `h` key
    /// still offer (the narrowest windows). A finished painting has nothing to hint at, so no
    /// Hint at all. Give Feedback lives in More, so the bar never shows
    /// more than six controls (Paul, October 18: "nested enough, that there isn't a moment where
    /// people are just overwhelmed by a panel of buttons"). Nothing here may grow wider than the
    /// window: the bar's width would widen the whole screen. Quiet (`QuietPainting`), it fades
    /// to `quietRow`.
    private func topBar(width: CGFloat, regular: Bool) -> some View {
        let badges = badgeVariants(regular)
        // ✎ Change stays in the bar with Hint (the board's critic: it mustn't push Hint out); on
        // the narrowest windows Hint goes first, as it did before, and Change keeps its place.
        let rows: [BarVariant] = session.isComplete
            ? badges.map { BarVariant(badge: $0, showsHint: false) }
            : badges.map { BarVariant(badge: $0, showsHint: true) }
                + badges.suffix(1).map { BarVariant(badge: $0, showsHint: false) }
        let quiet = isQuiet
        return GlassEffectContainer(spacing: 10) {
            Group {
                if quiet {
                    quietRow(regular)
                        .transition(.opacity)
                } else {
                    // One `ForEach` of distinct rows: `ViewThatFits` traps on children sharing an id.
                    ViewThatFits(in: .horizontal) {
                        ForEach(rows, id: \.self) { row in
                            topBarRow(badge: row.badge, showsHint: row.showsHint, regular: regular)
                                .preference(key: BadgeTitleKey.self, value: [row.badge.showsTitle])
                                .preference(key: BarHintKey.self, value: [row.showsHint])
                        }
                    }
                    .transition(.opacity)
                }
            }
            .frame(maxWidth: max(0, width - 2 * Self.edge))
        }
        .environment(\.glassButtonDiameter, barHeight(regular))
        .onPreferenceChange(BadgeTitleKey.self) { shown in
            // Only the row that fit is on screen; were any other heard, the bar names the title.
            MainActor.assumeIsolated { badgeShowsTitle = shown == [true] }
        }
        .onPreferenceChange(BarHintKey.self) { shown in
            MainActor.assumeIsolated { barShowsHint = shown != [false] }
        }
        // A fade, never a move, so Reduce Motion needs nothing else.
        .animation(.easeInOut(duration: 0.5), value: quiet)
        // The bar keeps its height (the canvas insets assume it); larger text sizes reach its
        // controls through the Large Content Viewer.
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
    }

    /// The top bar has faded to `quietRow` (`QuietPainting.isQuiet`).
    private var isQuiet: Bool {
        QuietPainting.isQuiet(
            wanted: chrome.wantsQuiet, isStarted: session.isStarted, isComplete: session.isComplete,
            isGivingFeedback: feedback != nil, assistiveTechnology: voiceOverEnabled || switchControlEnabled,
            tipTurn: PaintTips.desk.turn)
    }

    /// The quiet bar: Back, the progress ring, which brings the rest back, and Hint.
    /// Spaced and held to their circles as `topBarRow`'s are, so Back stays where it was.
    private func quietRow(_ regular: Bool) -> some View {
        let barHeight = self.barHeight(regular)
        return HStack(spacing: 12) {
            if let onClose {
                GlassIconButton(systemImage: "chevron.backward", label: "Back", action: onClose)
                    .frame(width: barHeight, height: barHeight)
            }
            QuietRingButton(session: session, title: title) { chrome.wantsQuiet = false }
                .frame(width: barHeight, height: barHeight)
            Spacer(minLength: 0)
            // ✎ Change stays in the quiet bar: it is for any time, half painted too (the Mac's QA).
            if let onChange {
                changeButton(onChange, barHeight: barHeight)
            }
            GlassIconButton(systemImage: "lightbulb", label: "Hint") { controller.showHint() }
                .frame(width: barHeight, height: barHeight)
        }
    }

    /// One way the top bar can be laid out (`topBar`).
    nonisolated private struct BarVariant: Hashable {
        var badge: BadgeVariant
        var showsHint: Bool
    }

    /// Whether the top bar's row on screen names the painting in its badge.
    nonisolated private struct BadgeTitleKey: PreferenceKey {
        static let defaultValue: [Bool] = []
        static func reduce(value: inout [Bool], nextValue: () -> [Bool]) { value += nextValue() }
    }

    /// Whether the top bar's row on screen has Hint.
    nonisolated private struct BarHintKey: PreferenceKey {
        static let defaultValue: [Bool] = []
        static func reduce(value: inout [Bool], nextValue: () -> [Bool]) { value += nextValue() }
    }

    private func topBarRow(badge: BadgeVariant, showsHint: Bool, regular: Bool) -> some View {
        let barHeight = self.barHeight(regular)
        // 12 pt between every two shapes, more than the container's 10, so they don't merge. The
        // system glass buttons lay out about 5 pt wider on each side than their circle, Photo and
        // More exactly as wide: held to their circles, the gaps come out even (they were 13 and
        // 18 pt on a phone). Six controls fit a 402 pt phone.
        return HStack(spacing: 12) {
            if let onClose {
                GlassIconButton(systemImage: "chevron.backward", label: "Back", action: onClose)
                    .frame(width: barHeight, height: barHeight)
            }
            progressBadge(badge, regular: regular)
                .frame(maxWidth: .infinity, alignment: .leading)
            if photoLoader != nil {
                PhotoPeekButton(peek: $peek)
                    .disabled(photoUnavailable)
                    .gentleTip(.benchShowPhoto, arrowEdge: .top)
            }
            if showsHint {
                GlassIconButton(systemImage: "lightbulb", label: "Hint") { controller.showHint() }
                    .frame(width: barHeight, height: barHeight)
            }
            GlassIconButton(systemImage: "arrow.uturn.backward", label: "Undo", action: undo)
                .frame(width: barHeight, height: barHeight)
                .disabled(!session.isStarted || session.isReplaying)
            if let onChange {
                changeButton(onChange, barHeight: barHeight)
            }
            moreMenu(regular)
        }
    }

    /// ✎ Change: the drawing tools on this painting. Before the purchase it carries a lock, so
    /// its tap opening the purchase is no surprise (QA, painting-company row 237).
    private func changeButton(_ action: @escaping () -> Void, barHeight: CGFloat) -> some View {
        let locked = paintings?.locksRefine == true
        return GlassIconButton(systemImage: "pencil", label: "Change", badge: locked ? "lock.fill" : nil, action: action)
            .frame(width: barHeight, height: barHeight)
            .disabled(session.isReplaying)
            .accessibilityHint(Text("Draw or erase lines in this painting"))
            .accessibilityValue(locked ? Text("Comes with Unlimited Paintings") : Text(verbatim: ""))
            .accessibilityIdentifier("change-painting")
    }

    /// What the progress badge shows: the ring, plus any of the title (when it fits whole),
    /// the percentage and, on regular widths, the selected color's name (compact widths show
    /// it above the palette instead). A finished painting has no paint on the brush to name:
    /// the completion bar has taken the palette's place.
    nonisolated private struct BadgeVariant: Hashable {
        var showsTitle = false
        var showsPercent = true
        var showsColor = false
        /// The name may shrink to the room left (its ideal width is kept small so this
        /// variant is chosen before Hint goes).
        var shrinksColor = false
    }

    /// Largest first. The name outranks the percentage: when a long (translated) name doesn't
    /// fit beside the percentage, the last variant keeps the ring and lets the name shrink.
    private func badgeVariants(_ regular: Bool) -> [BadgeVariant] {
        let showsColor = regular && !session.isComplete && session.hasSelectedColor
        var variants: [BadgeVariant] = []
        if !title.isEmpty { variants.append(BadgeVariant(showsTitle: true, showsColor: showsColor)) }
        variants.append(BadgeVariant(showsColor: showsColor))
        if showsColor { variants.append(BadgeVariant(showsPercent: false, showsColor: true, shrinksColor: true)) }
        return variants
    }

    private func progressBadge(_ variant: BadgeVariant, regular: Bool) -> some View {
        HStack(spacing: 10) {
            ProgressGroup(session: session, title: title, showsTitle: variant.showsTitle, showsPercent: variant.showsPercent)
            if variant.showsColor {
                Capsule()
                    .fill(Color.primary.opacity(0.15))
                    .frame(width: 1, height: 18)
                    .accessibilityHidden(true)
                if variant.shrinksColor {
                    CurrentColorLabel(session: session, font: .subheadline.weight(.semibold))
                        .frame(idealWidth: 60, alignment: .leading)
                } else {
                    CurrentColorLabel(session: session, font: .subheadline.weight(.semibold))
                        .fixedSize()
                }
            }
        }
        .padding(.horizontal, 14)
        .frame(height: barHeight(regular))
        .glassEffect(.regular, in: .capsule)
    }

    /// In three groups: how the page looks, the palette (or Replay) and Give Feedback, then Restart.
    private func moreMenu(_ regular: Bool) -> some View {
        let barHeight = self.barHeight(regular)
        return Menu {
            Toggle(isOn: $showsNumbers) { Label("Show Numbers", systemImage: "number") }
            Toggle(isOn: $zenMode) { Label("Zen Mode", systemImage: "leaf") }
            Button { controller.zoomToFit() } label: { Label("Fit to Screen", systemImage: "arrow.down.right.and.arrow.up.left") }
            if !barShowsHint, !session.isComplete {
                Button { controller.showHint() } label: { Label("Show Hint", systemImage: "lightbulb") }
            }
            Divider()
            if session.isReplaying {
                Button(action: controller.stopReplay) { Label("Stop Replay", systemImage: "stop") }
            } else if session.isComplete {
                Button(action: replay) { Label("Replay Painting", systemImage: "play") }
            } else {
                paletteMenu
            }
            Button(action: startFeedback) { Label("Give Feedback…", systemImage: "exclamationmark.bubble") }
            Divider()
            Button(role: .destructive) { confirmRestart = true } label: { Label("Restart", systemImage: "arrow.counterclockwise") }
        } label: {
            Image(systemName: "ellipsis")
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.primary)
                .imageScale(chromeScale(regular) > 1 ? .large : .medium)
                .frame(width: barHeight, height: barHeight)
                .glassEffect(.regular.interactive(), in: .circle)
        }
        .accessibilityLabel(Text("More"))
        .accessibilityShowsLargeContentViewer { Label("More", systemImage: "ellipsis") }
        // Zen Mode and Give Feedback live in this menu.
        .gentleTip(.benchZen, active: true, arrowEdge: .top)
        .gentleTip(.benchFeedback, active: true, arrowEdge: .top)
        // Asked from this menu, so the popover points at its button, not at the whole screen.
        .confirmationDialog("Restart this painting?", isPresented: $confirmRestart, titleVisibility: .visible) {
            Button("Restart", role: .destructive) {
                undoManager?.removeAllActions(withTarget: session)
                session.reset()
            }
        } message: {
            Text("All paint will be cleared.")
        }
    }

    /// More › Palette: its rows and order.
    private var paletteMenu: some View {
        Menu {
            Picker(selection: $paletteRows) {
                ForEach(PaletteRows.allCases) { rows in
                    Text(rows.name).tag(rows)
                }
            } label: {
                Label("Rows", systemImage: "square.grid.3x2")
            }
            .pickerStyle(.menu)
            Picker(selection: $paletteOrder) {
                ForEach(PaletteOrder.allCases) { order in
                    Text(order.name).tag(order)
                }
            } label: {
                Label("Order", systemImage: "arrow.up.arrow.down")
            }
            .pickerStyle(.menu)
        } label: {
            Label("Palette", systemImage: "paintpalette")
        }
        .accessibilityIdentifier("palette-menu")
    }

    // MARK: Bottom

    @ViewBuilder
    private func bottomBar(_ palette: PaletteLayout) -> some View {
        if session.isComplete {
            let transition: AnyTransition = reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity)
            CompletionBar(
                session: session, title: title, showsTitle: !badgeShowsTitle, share: completionShare,
                sealBounces: sealBounces, onReplay: replay, onStopReplay: controller.stopReplay,
                onShareTimelapse: shareTimelapse, onName: onName, isNamed: isNamed, onClose: onClose)
                .transition(transition)
        } else {
            PaletteBar(
                session: session, axis: palette.side ? .vertical : .horizontal, lines: palette.lines,
                shakes: chrome.shakes, metrics: palette.metrics, showsCurrentColor: palette.caption,
                order: colorOrder)
        }
    }

    // MARK: Actions

    /// The photo as a menu toggle (`p`), while there is one to show.
    private var photoBinding: Binding<Bool>? {
        guard photoLoader != nil, !photoUnavailable else { return nil }
        return Binding { peek.isShown } set: { peek.setLatched($0) }
    }

    /// The replay, which the tip about it (Watch It Again) is for.
    private func replay() {
        PaintTips.used(.benchReplay)
        controller.replay()
    }

    /// Undoes through the window's undo manager (so redo works) while it has this session's
    /// fills; older history comes straight from the saved stroke log.
    private func undo() {
        if let undoManager, undoManager.canUndo {
            undoManager.undo()
        } else {
            session.undo()
        }
    }

    /// From the live session: the saved copy may lag behind.
    private func shareTimelapse() {
        let name = title.isEmpty ? String(localized: "Painting") : title
        timelapse = TimelapseRequest(title: name, source: .live(template: session.template, progress: session.progress))
    }

    private func handlePencil(_ action: PencilAction) {
        // Drawing feedback, the Pencil's double tap and squeeze belong to its tools.
        guard feedback == nil else { return }
        action.perform(on: session, showHint: { controller.showHint() }, pencilUsed: { chrome.tipSignal(.pencilUsed) })
    }

    // MARK: Feedback

    /// Read while `body` is, so that the sheet and the markup canvas follow the draft.
    private var reviewsFeedback: Binding<Bool> {
        let isReviewing = feedback?.isReviewing ?? false
        return Binding { isReviewing } set: { feedback?.isReviewing = $0 }
    }

    /// Captures the painting as it is now and switches to feedback mode, with a flash like a
    /// camera's (not under Reduce Motion).
    private func startFeedback() {
        guard feedback == nil, !canvasUnavailable else { return }
        PaintTips.used(.benchFeedback)
        chrome.isGivingFeedback = true
        peek.setLatched(false)
        let capture = FeedbackCapture(
            session: session, title: title, controller: controller, showsNumbers: showsNumbers, paper: paperAppearance,
            darkInterface: colorScheme == .dark, lineWeight: lineWeight,
            displayScale: displayScale, source: feedbackSource)
        FeedbackEngine.shared.selectionChanged()
        Log.feedback.notice("Feedback started")
        // The painting is behind glass meanwhile: no undo of its fills.
        controller.releaseFocus()
        withAnimation(reduceMotion ? nil : .snappy) { feedback = FeedbackDraft(capture: capture) }
        if !reduceMotion {
            flashes = true
            Task {
                try? await Task.sleep(for: .milliseconds(60))
                withAnimation(.easeOut(duration: 0.5)) { flashes = false }
            }
        }
        Announcer.announce(String(
            localized: "feedback.announcement.started",
            defaultValue: "Feedback. Draw on the painting to show what it’s about, then choose Next.",
            comment: "VoiceOver announcement as the painting screen switches to giving feedback; Next is the button that opens the sheet to write and send it"))
    }

    private func endFeedback() {
        Log.feedback.notice("Feedback ends")
        chrome.isGivingFeedback = false
        withAnimation(reduceMotion ? nil : .snappy) { feedback = nil }
        // Back to the window's undo history of fills.
        controller.focus()
        Log.feedback.notice("Feedback ended")
    }

    /// The feedback was sent to the developers or shared: the sheet goes, then feedback mode, and
    /// thanks (sent, or just thanks for a share, which may only have been saved to Files).
    private func feedbackSent(_ delivery: FeedbackSheet.Delivery) {
        feedback?.isSent = true
        pendingThanks = switch delivery {
        case .sent: String(localized: "Feedback sent. Thank you!")
        case .shared: String(localized: "Thanks for the feedback!")
        }
        feedback?.isReviewing = false
    }

    /// Zen Mode just turned on: what it will do to the page, for a few seconds.
    private func sayWhatZenDoes() {
        let message = String(
            localized: "paint.zen.on", defaultValue: "Zen Mode is on: after each fill, the page glides to the next area of your color.",
            comment: "Painting screen: a toast for a few seconds after Zen Mode is turned on in the More menu, saying what it does to the view")
        Announcer.announce(message)
        zenNoteShowing += 1
        let showing = zenNoteShowing
        Task {
            zenNote = message
            try? await Task.sleep(for: .seconds(4))
            // Only this showing's: Zen turned off and on again meanwhile showed it anew.
            if zenNoteShowing == showing { zenNote = nil }
        }
    }

    /// The review sheet is gone. Feedback ends and the thanks show only now, not after a guess at
    /// the sheet's dismissal: on CI's busy simulators the thanks came while the sheet still showed.
    private func thankForFeedback() {
        guard let message = pendingThanks else { return }
        pendingThanks = nil
        endFeedback()
        Announcer.announce(message)
        Task {
            thanks = message
            try? await Task.sleep(for: .seconds(3))
            thanks = nil
        }
    }

    #if DEBUG
    /// Feedback demo scenarios: once the canvas is up, feedback starts with the demo's ink and
    /// note, and the review sheet opens when the demo asks for it.
    private func runFeedbackDemo() async {
        guard let demo = feedbackDemo else { return }
        try? await Task.sleep(for: .seconds(1))
        startFeedback()
        guard let feedback else { return }
        let zoom = controller.pointsPerUnit ?? 1
        feedback.drawingChanged(demo.ink(zoom), zoom: zoom, undoManager: nil)
        feedback.note = demo.note
        demo.draft = feedback
        guard demo.reviews else { return }
        try? await Task.sleep(for: .seconds(1))
        feedback.isReviewing = true
    }
    #endif
}

/// Tells `action` of each change of the selected color, from a view of its own: watched in the
/// painting screen's body, every change of color (each finished color's, in Zen Mode under the
/// fill that finished it) rendered the whole screen.
private struct SelectionWatch: View {
    let session: PaintingSession
    let action: () -> Void

    var body: some View {
        Color.clear
            .onChange(of: session.selectedColor) { action() }
            .accessibilityHidden(true)
    }
}

/// The progress badge's ring and percentage. They change with every fill, so they read the
/// session in a view of their own: a fill re-renders them, not the painting screen around them.
/// They show what is on the canvas, which during a replay is not what the painting holds
/// (`PaintingSession.replayed`).
private struct ProgressGroup: View {
    let session: PaintingSession
    let title: String
    let showsTitle: Bool
    let showsPercent: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let percent = PaintSpeech.percent(painted: session.shownPaintedCount, total: session.progress.regionCount)
        HStack(spacing: 8) {
            PaintedRing(session: session)
                .frame(width: 18, height: 18)
            if showsTitle {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .fixedSize()
            }
            if showsPercent {
                // Formatted here: a `Text` with a format resolves through an attributed string,
                // whose attribute scopes Foundation loads on its first change, under the first fill.
                Text(verbatim: (Double(percent) / 100).formatted(.percent.precision(.fractionLength(0))))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(showsTitle ? Theme.quietInk : Color.primary)
                    .contentTransition(.numericText())
                    .animation(reduceMotion ? nil : .snappy, value: percent)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title.isEmpty
            ? PaintSpeech.percentPainted(percent)
            : PaintSpeech.paintingProgress(title: title, percent: percent))
        .accessibilityShowsLargeContentViewer()
    }
}

/// The quiet bar's progress ring (`QuietPainting`): a glass button whose tap brings the rest of
/// the bar back. VoiceOver never meets it (the bar stays whole then); the Large Content Viewer
/// and Voice Control do.
private struct QuietRingButton: View {
    let session: PaintingSession
    let title: String
    let action: () -> Void
    @Environment(\.glassButtonDiameter) private var diameter

    var body: some View {
        let percent = PaintSpeech.percent(painted: session.shownPaintedCount, total: session.progress.regionCount)
        Button(action: action) {
            PaintedRing(session: session)
                .frame(width: diameter * 0.5, height: diameter * 0.5)
                .frame(width: diameter - 14, height: diameter - 14)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .accessibilityIdentifier("quiet-ring")
        .accessibilityLabel(title.isEmpty
            ? PaintSpeech.percentPainted(percent)
            : PaintSpeech.paintingProgress(title: title, percent: percent))
        .accessibilityHint(Text("Brings back the other controls"))
        .accessibilityInputLabels([Text("Show Controls")])
        .accessibilityShowsLargeContentViewer { Label("Show Controls", systemImage: "circle.dashed") }
    }
}

/// The progress ring, filled in paint: each color's painted share of the areas, in palette order.
private struct PaintedRing: View {
    let session: PaintingSession
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle().stroke(Color.primary.opacity(0.12), lineWidth: 3)
            ForEach(Array(paintedArcs.enumerated()), id: \.offset) { _, arc in
                Circle()
                    .trim(from: arc.start, to: arc.end)
                    .stroke(arc.paint, style: StrokeStyle(lineWidth: 3))
                    .rotationEffect(.degrees(-90))
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.4), value: session.shownFraction)
    }

    private var paintedArcs: [(paint: Color, start: Double, end: Double)] {
        let total = Double(max(session.progress.regionCount, 1))
        let shown = session.shownPaintedByColor
        var start = 0.0
        return (0..<session.paletteCount).compactMap { color -> (paint: Color, start: Double, end: Double)? in
            let painted = shown[color]
            guard painted > 0 else { return nil }
            let end = start + Double(painted) / total
            defer { start = end }
            return (PaletteBar.paint(session.template, color), start, end)
        }
    }
}
