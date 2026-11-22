import CoreGraphics
import Foundation
import MosaicKit
import Observation
import os
import PaintCore
import SwiftUI
import TipKit
import UIKit

/// The painting screen: full-bleed Metal canvas, floating Liquid Glass controls on top and
/// the palette at the bottom (trailing edge on a landscape iPad, see `PaletteLayout`).
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
    /// Names the mosaic from the Finished bar (`CompletionBar.onName`; SideStore and Debug builds).
    var onName: (() -> Void)?
    /// False while the mosaic has only the name the app gave it (`Artwork.isNamed`).
    var isNamed = true
    /// Where the canvas first looks (demo scenarios); nil = fit.
    var initialCamera: CanvasCamera?
    /// Scales fill animation durations (demo scenarios).
    var fillDurationScale: Float = 1
    /// Told where the template is (the window's coordinates) once the canvas's first frame is on screen,
    /// and again when a layout moves it: the create flow's picture moves there (`StartHandoff`).
    /// Read when the canvas is made.
    var onTemplateFrame: ((CGRect) -> Void)?
    /// False as the screen is left: `ArtworkPaintingView.close`.
    var hidesStatusBar = true

    @State private var controller = CanvasController()
    @Environment(\.startHandoff) private var startHandoff
    @State private var chrome = PaintChromeState()
    @State private var showsNumbers = true
    @State private var confirmRestart = false
    @State private var timelapse: TimelapseRequest?
    /// The finished mosaic shows the sheet's lines over its tiles (More › Show Lines,
    /// `CanvasView.showsLines`), for as long as the screen is up.
    @State private var linesShown: Bool
    /// Print's preview, up for More › Print… (painting-company row 330).
    @State private var printPreview: PrintPreviewRequest?
    @State private var canvasUnavailable = false
    @State private var completionShare = CompletionShare()
    /// Bumped once the completion bar is up after the painting was finished on this screen (not
    /// for a painting opened finished): its seal bounces.
    @State private var sealBounces = 0
    /// The progress badge names the painting (the top bar's layout that fits has room for it):
    /// the completion bar doesn't name it twice.
    @State private var badgeShowsTitle = false
    @State private var peek: PhotoPeek
    @State private var photoUnavailable = false
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.undoManager) private var undoManager
    @Environment(\.sourcePhotoLoader) private var photoLoader
    /// Ravenna's seam: the open mosaic's making-of and record, for the More menu.
    @Environment(\.paintingWork) private var work
    /// The show playing, kept until its cover has gone so the cover never empties as it leaves.
    @State private var makingOf: MakingOfSource?
    @State private var showsMakingOf = false
    @State private var aboutSample: Sample?
    /// Set in Stone's book, opened by the In Stone door after Finished (`FinishedDoors`).
    @State private var settingInStone: SetInStoneRequest?
    @Environment(\.verticalSizeClass) private var verticalSizeClass
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
    @Environment(\.displayScale) private var displayScale
    @Environment(\.colorScheme) private var colorScheme
    #if DEBUG
    @Environment(\.feedbackDemo) private var feedbackDemo
    #endif

    private static let edge: CGFloat = 12
    /// The top bar below the safe area, the bottom bar above it, and either bar to the canvas
    /// (`canvasInsets` keeps the canvas clear of the bars by these).
    private static let topGap: CGFloat = 6
    private static let bottomGap: CGFloat = 4
    private static let canvasGap: CGFloat = 6

    /// How much bigger the bar's buttons and the swatches are here (`QuietPainting.scale`).
    private var chromeScale: CGFloat { QuietPainting.scale(regularWidth: sizeClass == .regular) }
    /// The top bar's height: its round buttons' size, 44 pt on compact widths.
    private var barHeight: CGFloat { 44 * chromeScale }
    private var chromeScheme: ColorScheme { Self.chromeScheme(paper: paperAppearance, system: colorScheme) }

    /// The bars' appearance: dark over dark paper whatever the system's (on a light system the
    /// palette and the completion bar were light slabs on it, and the progress ring's track was
    /// lost in its glass), else the system's.
    static func chromeScheme(paper: PaperAppearance, system: ColorScheme) -> ColorScheme {
        paper.usesDarkPaper(interfaceIsDark: system == .dark) ? .dark : system
    }

    /// `showsPhoto` opens with the photo shown, `showsLines` with More › Show Lines on (demo
    /// scenarios).
    init(
        session: PaintingSession, title: String = "", onClose: (() -> Void)? = nil,
        onName: (() -> Void)? = nil, isNamed: Bool = true,
        initialCamera: CanvasCamera? = nil, fillDurationScale: Float = 1, showsPhoto: Bool = false,
        showsLines: Bool = false, onTemplateFrame: ((CGRect) -> Void)? = nil, hidesStatusBar: Bool = true
    ) {
        self.session = session
        self.title = title
        self.onClose = onClose
        self.onName = onName
        self.isNamed = isNamed
        self.initialCamera = initialCamera
        self.fillDurationScale = fillDurationScale
        self.onTemplateFrame = onTemplateFrame
        self.hidesStatusBar = hidesStatusBar
        _peek = State(initialValue: PhotoPeek(latched: showsPhoto))
        _linesShown = State(initialValue: showsLines)
    }

    var body: some View {
        GeometryReader { geo in
            if canvasUnavailable {
                CanvasUnavailableView(onClose: onClose)
            } else {
                canvasAndChrome(geo: geo, palette: paletteLayout(in: geo.size))
                    // The safe area's size, whatever a bar or a card asks: wider, the stack grew
                    // to the right of the reader's leading edge, and the canvas, ignoring the safe
                    // area within it, stopped short of the left one (an iPhone on its side; Paint
                    // by Moonlight's fix, painting-company row 263, ported for row 330).
                    .frame(width: geo.size.width, height: geo.size.height)
            }
        }
        // Nothing here takes typing: a keyboard over a sheet (feedback's notes) leaves the
        // canvas where it is.
        .ignoresSafeArea(.keyboard)
        // The canvas runs under the top edge: the clock would sit on the painting.
        .statusBarHidden(hidesStatusBar)
        .background(Color(uiColor: .systemGroupedBackground))
        .focusedSceneValue(\.painting, PaintingFocus(
            session: session, controller: controller, showsNumbers: $showsNumbers, showsPhoto: photoBinding,
            isGivingFeedback: feedback != nil, giveFeedback: startFeedback))
        .onAppear {
            FeedbackEngine.shared.attach(to: session)
            chrome.undoManager = undoManager
            // A painting just started is opened under the create flow's cover, where a tip's
            // popover can't present: the bench and its tips begin once the cover is gone.
            if startHandoff?.isRunning != true { chrome.observe(session) }
            RenderContext.prewarm()
        }
        .onChange(of: undoManager) { _, manager in chrome.undoManager = manager }
        .onChange(of: startHandoff?.isRunning == true) { _, running in
            if !running { chrome.observe(session) }
        }
        // Picking the next color follows the palette as it is laid out.
        .onChange(of: colorOrder, initial: true) { _, order in session.colorOrder = order }
        .onChange(of: paletteOrder, initial: true) { _, order in session.advancesToFirstLeft = order.followsProgress }
        .onChange(of: autoAdvance, initial: true) { _, advance in session.autoAdvance = advance }
        .onChange(of: zenMode, initial: true) { was, zen in
            session.flowsToNextArea = zen
            if zen { PaintTips.used(.benchZen) }
            if zen && !was { sayWhatZenDoes() }
        }
        .onChange(of: reduceMotion, initial: true) { _, reduce in session.reduceMotion = reduce }
        // Choosing a color is something done: the tips' hand has not rested yet.
        .background { SelectionWatch(session: session) { chrome.activity() } }
        // The photo shown, held or kept, is the Photo control used.
        .onChange(of: peek.isShown) { _, shown in
            if shown { PaintTips.used(.benchShowPhoto) }
        }
        .onChange(of: session.isComplete) { _, complete in
            guard complete, !reduceMotion else { return }
            Task {
                // As the completion bar settles.
                try? await Task.sleep(for: .milliseconds(450))
                sealBounces += 1
            }
        }
        .onDisappear {
            undoManager?.removeAllActions(withTarget: session)
            chrome.close()
        }
        .task {
            if let onTemplateFrame { await reportTemplate(to: onTemplateFrame) }
        }
        .sheet(item: $timelapse) { request in
            TimelapseExportSheet(request: request)
        }
        .sheet(item: $aboutSample) { sample in
            SampleAboutView(sample: sample)
        }
        .sheet(item: $settingInStone) { request in
            SetInStoneSheet(request: request)
                .pageSizedOnPad()
        }
        .sheet(item: $printPreview) { request in
            PrintPreviewSheet(request: request)
                .pageSizedOnPad()
        }
        .fullScreenCover(isPresented: $showsMakingOf, onDismiss: {
            makingOf = nil
            chrome.isShowingMakingOf = false
            chrome.activity()
        }) {
            if let makingOf {
                MakingOfView(source: makingOf, onFinish: { showsMakingOf = false })
            }
        }
        .sheet(isPresented: reviewsFeedback, onDismiss: thankForFeedback) {
            if let feedback {
                FeedbackSheet(draft: feedback, onSent: feedbackSent)
                    .pageSizedOnPad()
            }
        }
        .overlay(alignment: .top) {
            if let zenNote {
                Toast(text: zenNote, systemImage: "leaf", edge: .top)
                    .padding(.top, Self.topGap + barHeight + 12)
                    .padding(.horizontal, 20)
                    .allowsHitTesting(false)
                    .environment(\.colorScheme, chromeScheme)
                    .accessibilityIdentifier("zen-note")
            }

            if let thanks {
                // Below the top bar, like the painting's other toasts; taps reach the canvas.
                Toast(text: thanks, systemImage: "checkmark.circle", edge: .top)
                    .padding(.top, Self.topGap + barHeight + 12)
                    .padding(.horizontal, 20)
                    .allowsHitTesting(false)
                    .environment(\.colorScheme, chromeScheme)
            }
        }
        .animation(.snappy, value: thanks)
        .animation(.snappy, value: zenNote)
        #if DEBUG
        .task { await runFeedbackDemo() }
        #endif
    }

    /// The Metal canvas with the floating bars over it.
    private func canvasAndChrome(geo: GeometryProxy, palette: PaletteLayout) -> some View {
        // The doors after Finished under the completion bar, where they fit (`FinishedDoors`).
        let doors = session.isComplete
            ? Self.doorMetrics(
                count: finishedDoors.count, size: geo.size, compactHeight: verticalSizeClass == .compact,
                dynamicTypeSize: dynamicTypeSize)
            : nil
        return ZStack {
            PaintCanvas(
                session: session, controller: controller,
                chromeInsets: canvasInsets(safe: geo.safeAreaInsets, palette: palette, doors: doors),
                showsNumbers: showsNumbers, showsLines: linesShown, paperAppearance: paperAppearance,
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
                .ignoresSafeArea()

            if let feedback {
                MarkupCanvas(
                    draft: feedback, controller: controller,
                    canvasSize: CGSize(width: session.template.width, height: session.template.height),
                    isMarking: !feedback.isReviewing && !feedback.isSent, tool: feedback.tool, penColor: feedback.penColor)
                    .ignoresSafeArea()
            }

            // Tips about the page itself: a card at the top of the page as it first fits, with no
            // arrow (Paul, October 18: "No arrow"; an arrow from the top of the canvas seemed to point
            // at the Photo button on a phone).
            if feedback == nil, PaintTips.desk.pageTip != nil {
                let visiblePadding = visibleCanvasPadding(safe: geo.safeAreaInsets, palette: palette, doors: doors)
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
                Group {
                    if let feedback {
                        FeedbackBar(
                            draft: feedback, width: max(0, geo.size.width - 2 * Self.edge), onDiscard: endFeedback,
                            onNext: {
                                Log.feedback.notice("Next: the review opens")
                                feedback.isReviewing = true
                            })
                    } else {
                        topBar(width: geo.size.width)
                    }
                }
                .padding(.horizontal, Self.edge)
                .padding(.top, Self.topGap)
                Spacer(minLength: 0)
                if let feedback {
                    FeedbackTools(draft: feedback)
                        .padding(.horizontal, Self.edge)
                        .padding(.bottom, Self.bottomGap)
                } else if !palette.side || session.isComplete {
                    bottomBar(palette, doors: doors)
                        .padding(.horizontal, Self.edge)
                        .padding(.bottom, Self.bottomGap)
                }
            }
            .environment(\.colorScheme, chromeScheme)
            if feedback == nil && palette.side && !session.isComplete {
                HStack {
                    Spacer(minLength: 0)
                    bottomBar(palette, doors: nil)
                        .padding(.trailing, Self.edge)
                        .padding(.top, sidePaletteTop)
                        .padding(.bottom, Self.edge)
                }
                .environment(\.colorScheme, chromeScheme)
            }

            if !session.isComplete {
                // What finishing shows, met once a launch, out of sight.
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

    /// While the painting is handed over to (`StartHandoff`): once the canvas has its first frame on
    /// screen and its template has stayed where it is for a moment, tells `report` where the
    /// template is (the window's coordinates, as UIKit has the canvas: SwiftUI's global frame of the
    /// pushed canvas put it a safe area's height too low in Paint by Moonlight), and again whenever it moves. A painting's first layout is
    /// not its last: its size class, palette and status bar settle after it (the status bar goes
    /// with the create flow's cover), and polling sees whichever of them moved it.
    private func reportTemplate(to report: (CGRect) -> Void) async {
        var previous: CGRect?
        var announced: CGRect?
        // Every refresh or so until the first report, every tenth of a second after it: the
        // cover waits for that first one (painting-company row 361), a rotation can wait.
        var steady = 0
        let deadline = ContinuousClock.now + .seconds(60)
        while ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(announced == nil ? 16 : 100))
            guard !Task.isCancelled, startHandoff?.isRunning == true else { return }
            guard controller.isShowingFirstFrame, let frame = controller.templateFrameInWindow else { continue }
            steady = frame == previous ? steady + 1 : 0
            defer { previous = frame }
            guard frame != announced else { continue }
            // The first time, once it has stayed put for three refreshes (the tenth of a second
            // two looks used to span); after that, as it moves.
            if announced != nil || steady >= 3 {
                announced = frame
                report(frame)
            }
        }
    }

    // MARK: Layout

    /// Where the palette goes and how many lines it wraps into: along the trailing edge of a
    /// wide window (landscape iPad), otherwise at the bottom. Roomy windows show every color
    /// at once in a few lines; compact ones scroll a single line and name the selected color
    /// in a caption above it (regular widths name it in the progress badge).
    struct PaletteLayout: Equatable {
        var side: Bool
        var lines: Int
        var caption: Bool
        var metrics: PaletteMetrics
        var thickness: CGFloat { metrics.thickness(lines: lines, caption: caption) }
    }

    private var sidePaletteTop: CGFloat { Self.topGap + barHeight + 12 }

    /// The palette as laid out in a view of `size`. It counts the painting's colors, not those
    /// left (`PaletteBar.visibleColorCount`): counting those left, finishing one could re-lay the
    /// whole palette, and the picture with it, as Paint by Moonlight's did until November 10.
    private func paletteLayout(in size: CGSize) -> PaletteLayout {
        Self.paletteLayout(
            in: size, colors: PaletteBar.visibleColorCount(session.template), regularWidth: sizeClass == .regular,
            dynamicTypeSize: dynamicTypeSize, rows: paletteRows)
    }

    private static func paletteLayout(
        in size: CGSize, colors count: Int, regularWidth: Bool, dynamicTypeSize: DynamicTypeSize, rows: PaletteRows
    ) -> PaletteLayout {
        let scale = QuietPainting.scale(regularWidth: regularWidth)
        let metrics = PaletteMetrics(dynamicTypeSize: dynamicTypeSize).scaled(by: scale)
        if regularWidth && size.width > size.height {
            let length = size.height - (topGap + 44 * scale + 12) - edge
            return PaletteLayout(
                side: true,
                lines: paletteLines(
                    count: count, length: length, automatic: 2, room: size.width * 0.4, metrics: metrics, rows: rows),
                caption: false, metrics: metrics)
        }
        let length = size.width - 2 * edge
        let caption = !regularWidth
        return PaletteLayout(
            side: false,
            lines: paletteLines(
                count: count, length: length, automatic: regularWidth ? 3 : 1,
                room: size.height * 0.45 - (caption ? metrics.captionHeight : 0), metrics: metrics, rows: rows),
            caption: caption, metrics: metrics)
    }

    /// The palette's lines for `count` swatches `length` points long, under the Rows setting:
    /// Auto allows `automatic` lines, and no choice makes the bar thicker than `room` points.
    private static func paletteLines(
        count: Int, length: CGFloat, automatic: Int, room: CGFloat, metrics: PaletteMetrics, rows: PaletteRows
    ) -> Int {
        let lines = (room - 2 * PaletteMetrics.padding + PaletteMetrics.spacing) / metrics.pitch
        // `Int(_:)` traps on a non-finite size (a zero-sized layout pass).
        let fit = lines.isFinite ? Int(max(lines, 0)) : 1
        let most = max(1, min(rows.maxLines(automatic: automatic), fit))
        if rows.isFixed { return max(1, min(most, count)) }
        return metrics.lines(count: count, length: length, maxLines: most)
    }

    /// Where the canvas first shows the page of a template `templateSize` big (canvas units), with
    /// `colors` paints, in a painting screen of `size` inside the safe area `safe` (its
    /// `GeometryProxy`'s, leading and trailing in the painting's direction): the whole screen's
    /// coordinates, x from the leading edge. One recipe for this screen's layout and for the
    /// thumbnail a mosaic opens on (`ArtworkPaintingView`), so the thumbnail lands where the canvas
    /// puts the page and nothing moves as the mosaic takes its place (painting-company row 364).
    /// A finished mosaic's `doors` after Finished (`FinishedDoor.shown`) are counted in, their
    /// panel at the height it is laid out to have.
    static func openingPage(
        of templateSize: CGSize, colors: Int, isComplete: Bool, doors: Int = 0, compactHeight: Bool = false,
        size: CGSize, safe: EdgeInsets, regularWidth: Bool, dynamicTypeSize: DynamicTypeSize, rows: PaletteRows
    ) -> CGRect {
        let palette = paletteLayout(
            in: size, colors: colors, regularWidth: regularWidth, dynamicTypeSize: dynamicTypeSize, rows: rows)
        let metrics = isComplete
            ? doorMetrics(count: doors, size: size, compactHeight: compactHeight, dynamicTypeSize: dynamicTypeSize)
            : nil
        let insets = canvasInsets(
            safe: safe, palette: palette, isComplete: isComplete,
            completionHeight: completionHeight(metrics, dynamicTypeSize: dynamicTypeSize),
            barHeight: 44 * QuietPainting.scale(regularWidth: regularWidth))
        // As `CanvasView` fits the template at its least zoom and centres it.
        let screen = CGSize(width: size.width + safe.leading + safe.trailing, height: size.height + safe.top + safe.bottom)
        let room = CGRect(
            x: insets.leading + CanvasView.margin, y: insets.top + CanvasView.margin,
            width: screen.width - insets.leading - insets.trailing - 2 * CanvasView.margin,
            height: screen.height - insets.top - insets.bottom - 2 * CanvasView.margin)
        guard templateSize.width > 0, templateSize.height > 0, room.width > 0, room.height > 0 else { return room }
        let fit = min(room.width / templateSize.width, room.height / templateSize.height)
        let page = CGSize(width: templateSize.width * fit, height: templateSize.height * fit)
        return CGRect(
            x: room.midX - page.width / 2, y: room.midY - page.height / 2, width: page.width, height: page.height)
    }

    /// Every color of the palette in its order on screen (finished ones too).
    private var colorOrder: [Int] {
        paletteOrder.arrange(
            Array(0..<session.paletteCount), palette: session.template.palette, remaining: session.remainingByColor)
    }

    /// Canvas insets in full-screen coordinates: safe area plus the floating bars.
    private func canvasInsets(safe: EdgeInsets, palette: PaletteLayout, doors: DoorMetrics?) -> EdgeInsets {
        Self.canvasInsets(
            safe: safe, palette: palette, isComplete: session.isComplete,
            completionHeight: Self.completionHeight(doors, dynamicTypeSize: dynamicTypeSize), barHeight: barHeight)
    }

    private static func canvasInsets(
        safe: EdgeInsets, palette: PaletteLayout, isComplete: Bool, completionHeight: CGFloat, barHeight: CGFloat
    ) -> EdgeInsets {
        let top = safe.top + topGap + barHeight + canvasGap
        if isComplete {
            return EdgeInsets(
                top: top, leading: safe.leading,
                bottom: safe.bottom + bottomGap + completionHeight + canvasGap, trailing: safe.trailing)
        }
        if palette.side {
            return EdgeInsets(top: top, leading: safe.leading, bottom: safe.bottom + 8,
                              trailing: safe.trailing + edge + palette.thickness + 4)
        }
        return EdgeInsets(
            top: top, leading: safe.leading,
            bottom: safe.bottom + bottomGap + palette.thickness + canvasGap, trailing: safe.trailing)
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

    /// The completion bar's height: with its doors, the panel's as counted
    /// (`CompletionBar.panelHeight`), never measured.
    private static func completionHeight(_ doors: DoorMetrics?, dynamicTypeSize: DynamicTypeSize) -> CGFloat {
        doors.map { CompletionBar.panelHeight($0, dynamicTypeSize: dynamicTypeSize) } ?? CompletionBar.height
    }

    /// The doors after Finished this mosaic shows (none in the release: `FinishedDoor.isOffered`).
    private var finishedDoors: [FinishedDoor] {
        FinishedDoor.shown(original: work?.sample != nil, stone: session.wall != nil)
    }

    /// The doors after Finished, `count` of them, in a painting screen of `size` (the safe area's):
    /// at most `FinishedDoor.doorsShare` of its height for the panel, as wide as the panel may be.
    /// Nil where there are none or they don't fit: the bar alone.
    static func doorMetrics(
        count: Int, size: CGSize, compactHeight: Bool, dynamicTypeSize: DynamicTypeSize
    ) -> DoorMetrics? {
        guard count > 0 else { return nil }
        let room = size.height * FinishedDoor.doorsShare(compactHeight: compactHeight)
        let width = CompletionBar.doorsWidth(count: count, available: size.width - 2 * edge)
        return DoorMetrics.fitting(
            count: count, width: width, height: room - CompletionBar.height - CompletionBar.doorsInset,
            dynamicTypeSize: min(dynamicTypeSize, .xxLarge))
    }

    /// The canvas's visible area within the safe area (the canvas itself ignores it).
    private func visibleCanvasPadding(safe: EdgeInsets, palette: PaletteLayout, doors: DoorMetrics?) -> EdgeInsets {
        let insets = canvasInsets(safe: safe, palette: palette, doors: doors)
        return EdgeInsets(
            top: max(0, insets.top - safe.top), leading: max(0, insets.leading - safe.leading),
            bottom: max(0, insets.bottom - safe.bottom), trailing: max(0, insets.trailing - safe.trailing))
    }

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
    private func topBar(width: CGFloat) -> some View {
        let badges = badgeVariants
        let rows: [BarVariant] = session.isComplete
            ? badges.map { BarVariant(badge: $0, showsHint: false) }
            : badges.map { BarVariant(badge: $0, showsHint: true) }
                + badges.suffix(1).map { BarVariant(badge: $0, showsHint: false) }
        let quiet = isQuiet
        return GlassEffectContainer(spacing: 10) {
            Group {
                if quiet {
                    quietRow
                        .transition(.opacity)
                } else {
                    // One `ForEach` of distinct rows: `ViewThatFits` traps on children sharing an id.
                    ViewThatFits(in: .horizontal) {
                        ForEach(rows, id: \.self) { row in
                            topBarRow(badge: row.badge, showsHint: row.showsHint)
                                .preference(key: BadgeTitleKey.self, value: [row.badge.showsTitle])
                        }
                    }
                    .transition(.opacity)
                }
            }
            .frame(maxWidth: max(0, width - 2 * Self.edge))
        }
        .environment(\.glassButtonDiameter, barHeight)
        .onPreferenceChange(BadgeTitleKey.self) { shown in
            // Only the row that fit is on screen; were any other heard, the bar names the title.
            MainActor.assumeIsolated { badgeShowsTitle = shown == [true] }
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
    private var quietRow: some View {
        HStack(spacing: 12) {
            if let onClose {
                GlassIconButton(systemImage: "chevron.backward", label: "Back", action: onClose)
                    .frame(width: barHeight, height: barHeight)
            }
            QuietRingButton(session: session, title: title) { chrome.wantsQuiet = false }
                .frame(width: barHeight, height: barHeight)
            Spacer(minLength: 0)
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

    private func topBarRow(badge: BadgeVariant, showsHint: Bool) -> some View {
        // 12 pt between every two shapes, more than the container's 10, so they don't merge. The
        // system glass buttons lay out about 5 pt wider on each side than their circle, Photo and
        // More exactly as wide: held to their circles, the gaps come out even (they were 13 and
        // 18 pt on a phone). Six controls fit a 402 pt phone.
        HStack(spacing: 12) {
            if let onClose {
                GlassIconButton(systemImage: "chevron.backward", label: "Back", action: onClose)
                    .frame(width: barHeight, height: barHeight)
            }
            progressBadge(badge)
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
            moreMenu
        }
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
    private var badgeVariants: [BadgeVariant] {
        let showsColor = sizeClass == .regular && !session.isComplete && session.hasSelectedColor
        var variants: [BadgeVariant] = []
        if !title.isEmpty { variants.append(BadgeVariant(showsTitle: true, showsColor: showsColor)) }
        variants.append(BadgeVariant(showsColor: showsColor))
        if showsColor { variants.append(BadgeVariant(showsPercent: false, showsColor: true, shrinksColor: true)) }
        return variants
    }

    private func progressBadge(_ variant: BadgeVariant) -> some View {
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
        .frame(height: barHeight)
        .glassEffect(.regular, in: .capsule)
    }

    /// In three groups: how the page looks, the palette (or Replay), Print and Give Feedback, then
    /// Restart.
    private var moreMenu: some View {
        Menu {
            Toggle(isOn: $showsNumbers) { Label("Show Numbers", systemImage: "number") }
            #if UNRELEASED
            // Paint by Moonlight's Show Lines, for tiles: a finished mosaic has no ink to take
            // away (its joints are grout, the mosaic itself), so here it brings back the lines
            // the tiles were set by, the sheet's drawing over them. A replay shows the mosaic
            // being set, without.
            if session.isComplete, !session.isReplaying {
                Toggle(isOn: $linesShown) { Label("Show Lines", systemImage: "scribble") }
            }
            #endif
            Toggle(isOn: $zenMode) { Label("Zen Mode", systemImage: "leaf") }
            Button { controller.zoomToFit() } label: { Label("Fit to Screen", systemImage: "arrow.down.right.and.arrow.up.left") }
            Divider()
            if session.isReplaying {
                Button(action: controller.stopReplay) { Label("Stop Replay", systemImage: "stop") }
            } else if session.isComplete {
                Button(action: replay) { Label("Replay Mosaic", systemImage: "play") }
            } else {
                paletteMenu
            }
            #if UNRELEASED
            if PrintSheet.isAvailable {
                Button(action: printTemplate) { Label("Print…", systemImage: "printer") }
                    .accessibilityIdentifier("print-template")
            }
            #endif
            Button(action: startFeedback) { Label("Give Feedback…", systemImage: "exclamationmark.bubble") }
            workItems
            Divider()
            Button(role: .destructive) { confirmRestart = true } label: { Label("Restart", systemImage: "arrow.counterclockwise") }
        } label: {
            Image(systemName: "ellipsis")
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.primary)
                .imageScale(chromeScale > 1 ? .large : .medium)
                .frame(width: barHeight, height: barHeight)
                .glassEffect(.regular.interactive(), in: .circle)
        }
        .accessibilityLabel(Text("More"))
        .accessibilityShowsLargeContentViewer { Label("More", systemImage: "ellipsis") }
        // Zen Mode and Give Feedback live in this menu.
        .gentleTip(.benchZen, active: true, arrowEdge: .top)
        .gentleTip(.benchFeedback, active: true, arrowEdge: .top)
        // Asked from this menu, so the popover points at its button, not at the whole screen.
        .confirmationDialog("Restart this mosaic?", isPresented: $confirmRestart, titleVisibility: .visible) {
            Button("Restart", role: .destructive) {
                undoManager?.removeAllActions(withTarget: session)
                session.reset()
                linesShown = false
            }
        } message: {
            Text("Every tile will be lifted.")
        }
    }

    /// More › The Making-of and About This Work (`PaintingWork`), as v0's menu had them. Ravenna's
    /// seam.
    @ViewBuilder
    private var workItems: some View {
        if let show = work?.makingOf {
            Button {
                guard !chrome.isShowingMakingOf else { return }
                chrome.isShowingMakingOf = true
                Task {
                    let source = await show()
                    // Not over another sheet (About This Work, opened meanwhile): the cover wouldn't
                    // present, and its dismissal, which ends the quiet, would never come.
                    if let source, aboutSample == nil, timelapse == nil {
                        makingOf = source
                        showsMakingOf = true
                    } else {
                        chrome.isShowingMakingOf = false
                    }
                }
            } label: {
                Label(String(localized: "paint.more.makingOf", defaultValue: "The Making-of", bundle: .ravenna,
                             comment: "Item of the mosaic's More menu: plays the show of how the mosaic was made again"),
                      systemImage: "film")
            }
        }
        if let sample = work?.sample {
            Button {
                aboutSample = sample
            } label: {
                Label(String(localized: "paint.more.about", defaultValue: "About This Work", bundle: .ravenna,
                             comment: "Item of the mosaic's More menu: who made the ancient work it was laid from, when and where"),
                      systemImage: "info.circle")
            }
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
    private func bottomBar(_ palette: PaletteLayout, doors: DoorMetrics?) -> some View {
        if session.isComplete {
            let transition: AnyTransition = reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity)
            CompletionBar(
                session: session, title: title, showsTitle: !badgeShowsTitle, share: completionShare,
                sealBounces: sealBounces, onReplay: replay, onStopReplay: controller.stopReplay,
                onShareTimelapse: shareTimelapse, onName: FinishedDoor.isOffered ? onName : nil, isNamed: isNamed,
                onClose: onClose, doors: doors, doorList: finishedDoors, original: work?.sample,
                onOriginal: { aboutSample = $0 }, onStone: setInStone)
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

    /// In Stone, a door after Finished: Set in Stone's book of the mosaic as it is on screen.
    private func setInStone() {
        guard let mosaic = session.wall?.mosaic, !mosaic.tiles.isEmpty else { return }
        let names = session.colorNicknames
        settingInStone = SetInStoneRequest(
            mosaic: mosaic, title: title.isEmpty ? String(localized: "Mosaic", bundle: .ravenna) : title,
            names: (0..<mosaic.palette.count).map { $0 < names.count ? names[$0] : nil })
    }

    /// From the live session: the saved copy may lag behind.
    private func shareTimelapse() {
        let name = title.isEmpty ? String(localized: "Mosaic", bundle: .ravenna) : title
        timelapse = TimelapseRequest(title: name, source: .live(template: session.template, progress: session.progress, mosaic: session.wall?.mosaic))
    }

    /// More › Print… (SideStore and Debug builds): Print's preview on the mosaic's sheet (its
    /// tiles as areas to paint, the numbers and the color key), whatever is set, from the live
    /// session.
    private func printTemplate() {
        let name = title.isEmpty ? String(localized: "Mosaic", bundle: .ravenna) : title
        printPreview = PrintPreviewRequest(template: session.template, title: name, nicknames: session.colorNicknames)
    }

    private func handlePencil(_ action: PencilAction) {
        // Drawing feedback, the Pencil's double tap and squeeze belong to its tools.
        guard feedback == nil else { return }
        switch action {
        case .tap:
            // With nothing in hand (a finished color put down) it takes the first color left.
            if let next = session.nextIncompleteColor(after: session.selectedColor) {
                session.select(color: next)
                FeedbackEngine.shared.selectionChanged()
            }
        case .squeeze:
            controller.showHint()
        case .lifted:
            chrome.tipSignal(.pencilUsed)
        }
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
        case .sent: String(localized: "Feedback sent. Thank you!", bundle: .ravenna)
        case .shared: String(localized: "Thanks for the feedback!", bundle: .ravenna)
        }
        feedback?.isReviewing = false
    }

    /// Zen Mode just turned on: what it will do to the page, for a few seconds.
    private func sayWhatZenDoes() {
        let message = String(
            localized: "paint.zen.on", defaultValue: "Zen Mode is on: after each tile you set, the mosaic glides to the next tile of your color.",
            bundle: .ravenna,
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
        let percent = PaintSpeech.percent(painted: session.shownPaintedCount, total: session.areaCount)
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
        let percent = PaintSpeech.percent(painted: session.shownPaintedCount, total: session.areaCount)
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
        let total = Double(max(session.areaCount, 1))
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
