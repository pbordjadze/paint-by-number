import Foundation
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
/// the top bar offers the Photo control (see `PhotoPeek`). First-run tips (`PaintTips`) point
/// at the selected swatch or the middle of the canvas, one at a time.
///
/// Give Feedback (the top bar where it fits, else More; always the Paint menu) captures the
/// painting as it is (`FeedbackCapture`, with the environment's `feedbackSource`) and switches
/// to feedback mode: painting stops, the palette goes, `FeedbackBar` takes the top and
/// `MarkupCanvas` lies over the canvas for drawing; Next opens `FeedbackSheet`.
struct PaintView: View {
    let session: PaintingSession
    var title: String = ""
    var onClose: (() -> Void)?
    /// Where the canvas first looks (demo scenarios); nil = fit.
    var initialCamera: CanvasCamera?
    /// Scales fill animation durations (demo scenarios).
    var fillDurationScale: Float = 1

    @State private var controller = CanvasController()
    @State private var chrome = PaintChromeState()
    @State private var showsNumbers = true
    @State private var confirmRestart = false
    @State private var timelapse: TimelapseRequest?
    @State private var canvasUnavailable = false
    @State private var completionShare = CompletionShare()
    @State private var peek: PhotoPeek
    @State private var photoUnavailable = false
    @State private var tips: TipGroup?
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.undoManager) private var undoManager
    @Environment(\.sourcePhotoLoader) private var photoLoader
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(SettingsKey.paperAppearance) private var paperAppearance = PaperAppearance.default
    @AppStorage(SettingsKey.lineWeight) private var lineWeight = LineWeight.default
    @AppStorage(SettingsKey.paletteRows) private var paletteRows = PaletteRows.default
    @AppStorage(SettingsKey.paletteOrder) private var paletteOrder = PaletteOrder.default
    @AppStorage(SettingsKey.zenMode) private var zenMode = false
    /// Feedback mode while set.
    @State private var feedback: FeedbackDraft?
    /// The white flash of the capture as feedback starts.
    @State private var flashes = false
    @State private var thanks = false
    @Environment(\.feedbackSource) private var feedbackSource
    @Environment(\.displayScale) private var displayScale
    @Environment(\.colorScheme) private var colorScheme
    #if DEBUG
    @Environment(\.feedbackDemo) private var feedbackDemo
    #endif

    private static let barHeight: CGFloat = 44
    private static let edge: CGFloat = 12
    /// The top bar below the safe area, the bottom bar above it, and either bar to the canvas
    /// (`canvasInsets` keeps the canvas clear of the bars by these).
    private static let topGap: CGFloat = 6
    private static let bottomGap: CGFloat = 4
    private static let canvasGap: CGFloat = 6

    /// `showsPhoto` opens with the photo shown (demo scenarios).
    init(
        session: PaintingSession, title: String = "", onClose: (() -> Void)? = nil,
        initialCamera: CanvasCamera? = nil, fillDurationScale: Float = 1, showsPhoto: Bool = false
    ) {
        self.session = session
        self.title = title
        self.onClose = onClose
        self.initialCamera = initialCamera
        self.fillDurationScale = fillDurationScale
        _peek = State(initialValue: PhotoPeek(latched: showsPhoto))
    }

    var body: some View {
        GeometryReader { geo in
            #if DEBUG
            let _ = MainThreadWatchdog.count("PaintView")
            #endif
            if canvasUnavailable {
                CanvasUnavailableView(onClose: onClose)
            } else {
                canvasAndChrome(geo: geo, palette: paletteLayout(in: geo.size))
            }
        }
        // Nothing here takes typing: a keyboard over a sheet (feedback's notes) leaves the
        // canvas where it is.
        .ignoresSafeArea(.keyboard)
        .background(Color(uiColor: .systemGroupedBackground))
        .focusedSceneValue(\.painting, PaintingFocus(
            session: session, controller: controller, showsNumbers: $showsNumbers, showsPhoto: photoBinding,
            isGivingFeedback: feedback != nil, giveFeedback: startFeedback))
        .onAppear {
            if tips == nil { tips = PaintTips.makeGroup() }
            FeedbackEngine.shared.attach(to: session)
            chrome.undoManager = undoManager
            chrome.observe(session, controller: controller)
            RenderContext.prewarm()
        }
        .onChange(of: undoManager) { _, manager in chrome.undoManager = manager }
        // Picking the next color follows the palette as it is laid out.
        .onChange(of: colorOrder, initial: true) { _, order in session.colorOrder = order }
        .onChange(of: zenMode, initial: true) { _, zen in session.flowsToNextArea = zen }
        .onDisappear { undoManager?.removeAllActions(withTarget: session) }
        .confirmationDialog("Restart this painting?", isPresented: $confirmRestart, titleVisibility: .visible) {
            Button("Restart", role: .destructive) {
                undoManager?.removeAllActions(withTarget: session)
                session.reset()
            }
        } message: {
            Text("All paint will be cleared.")
        }
        .sheet(item: $timelapse) { request in
            TimelapseExportSheet(request: request)
        }
        .sheet(isPresented: reviewsFeedback) {
            if let feedback {
                FeedbackSheet(draft: feedback, onSent: feedbackSent)
            }
        }
        .overlay(alignment: .top) {
            if thanks {
                // Below the top bar, like the painting's other toasts; taps reach the canvas.
                Toast(text: String(localized: "Thanks for the feedback!"), systemImage: "checkmark.circle", edge: .top)
                    .padding(.top, 62)
                    .padding(.horizontal, 20)
                    .allowsHitTesting(false)
            }
        }
        .animation(.snappy, value: thanks)
        #if DEBUG
        .task { await runFeedbackDemo() }
        #endif
    }

    /// The Metal canvas with the floating bars over it.
    private func canvasAndChrome(geo: GeometryProxy, palette: PaletteLayout) -> some View {
        ZStack {
            PaintCanvas(
                session: session, controller: controller,
                chromeInsets: canvasInsets(safe: geo.safeAreaInsets, palette: palette),
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
                onZoomStep: { PaintTips.record(.zoomedByDoubleTap) },
                isAnnotating: feedback != nil)
                .id(ObjectIdentifier(session))
                .ignoresSafeArea()

            if let feedback {
                MarkupCanvas(
                    draft: feedback, controller: controller,
                    canvasSize: CGSize(width: session.template.width, height: session.template.height),
                    isMarking: !feedback.isReviewing && !feedback.isSent, tool: feedback.tool, penColor: feedback.penColor)
                    .ignoresSafeArea()
            }

            // Canvas tips point at the middle of the visible canvas.
            Color.clear
                .frame(width: 1, height: 1)
                .popoverTip(canvasTip)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(visibleCanvasPadding(safe: geo.safeAreaInsets, palette: palette))
                .allowsHitTesting(false)

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
                    bottomBar(palette)
                        .padding(.horizontal, Self.edge)
                        .padding(.bottom, Self.bottomGap)
                }
            }
            if feedback == nil && palette.side && !session.isComplete {
                HStack {
                    Spacer(minLength: 0)
                    bottomBar(palette)
                        .padding(.trailing, Self.edge)
                        .padding(.top, Self.sidePaletteTop)
                        .padding(.bottom, Self.edge)
                }
            }

            // The capture's flash as feedback starts.
            Color.white
                .opacity(flashes ? 0.5 : 0)
                .ignoresSafeArea()
                .allowsHitTesting(false)
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

    private var paletteMetrics: PaletteMetrics { PaletteMetrics(dynamicTypeSize: dynamicTypeSize) }

    private static let sidePaletteTop: CGFloat = topGap + barHeight + 12

    private func paletteLayout(in size: CGSize) -> PaletteLayout {
        let count = PaletteBar.visibleColors(session).count
        let metrics = paletteMetrics
        if sizeClass == .regular && size.width > size.height {
            let length = size.height - Self.sidePaletteTop - Self.edge
            return PaletteLayout(
                side: true,
                lines: paletteLines(count: count, length: length, automatic: 2, room: size.width * 0.4, metrics: metrics),
                caption: false, metrics: metrics)
        }
        let length = size.width - 2 * Self.edge
        let caption = sizeClass != .regular
        return PaletteLayout(
            side: false,
            lines: paletteLines(
                count: count, length: length, automatic: sizeClass == .regular ? 3 : 1,
                room: size.height * 0.45 - (caption ? metrics.captionHeight : 0), metrics: metrics),
            caption: caption, metrics: metrics)
    }

    /// The palette's lines for `count` swatches `length` points long, under the Rows setting:
    /// Auto allows `automatic` lines, and no choice makes the bar thicker than `room` points.
    private func paletteLines(count: Int, length: CGFloat, automatic: Int, room: CGFloat, metrics: PaletteMetrics) -> Int {
        let fit = Int((room - 2 * PaletteMetrics.padding + PaletteMetrics.spacing) / metrics.pitch)
        let most = max(1, min(paletteRows.maxLines(automatic: automatic), fit))
        if paletteRows.isFixed { return max(1, min(most, count)) }
        return metrics.lines(count: count, length: length, maxLines: most)
    }

    /// Every color of the palette in its order on screen (finished ones too).
    private var colorOrder: [Int] {
        paletteOrder.arrange(
            Array(0..<session.paletteCount), palette: session.template.palette, remaining: session.remainingByColor)
    }

    /// Canvas insets in full-screen coordinates: safe area plus the floating bars.
    private func canvasInsets(safe: EdgeInsets, palette: PaletteLayout) -> EdgeInsets {
        let top = safe.top + Self.topGap + Self.barHeight + Self.canvasGap
        if session.isComplete {
            return EdgeInsets(
                top: top, leading: safe.leading,
                bottom: safe.bottom + Self.bottomGap + CompletionBar.height + Self.canvasGap, trailing: safe.trailing)
        }
        if palette.side {
            return EdgeInsets(top: top, leading: safe.leading, bottom: safe.bottom + 8,
                              trailing: safe.trailing + Self.edge + palette.thickness + 4)
        }
        return EdgeInsets(
            top: top, leading: safe.leading,
            bottom: safe.bottom + Self.bottomGap + palette.thickness + Self.canvasGap, trailing: safe.trailing)
    }

    /// The canvas's visible area within the safe area (the canvas itself ignores it).
    private func visibleCanvasPadding(safe: EdgeInsets, palette: PaletteLayout) -> EdgeInsets {
        let insets = canvasInsets(safe: safe, palette: palette)
        return EdgeInsets(
            top: max(0, insets.top - safe.top), leading: max(0, insets.leading - safe.leading),
            bottom: max(0, insets.bottom - safe.bottom), trailing: max(0, insets.trailing - safe.trailing))
    }

    // MARK: Tips

    /// Tips about canvas gestures (none while feedback is drawn); the rest belong to the
    /// selected swatch.
    private var canvasTip: (any Tip)? {
        guard feedback == nil, let tip = tips?.currentTip, tip is DragPaintTip || tip is ZoomTip || tip is PencilTip else {
            return nil
        }
        return tip
    }

    private var swatchTip: (any Tip)? {
        guard let tip = tips?.currentTip, tip is FirstPaintTip || tip is HintTip else { return nil }
        return tip
    }

    // MARK: Top bar

    /// Close, the progress badge, then Photo, Hint, Undo, Give Feedback and More, as the first of
    /// these that fits: each badge variant (largest first, down to its ring and percentage) with
    /// every control, then each without Give Feedback (More offers it then), then the smallest
    /// badge without Hint, which the selected swatch and the `h` key still offer (the narrowest
    /// windows). Nothing here may grow wider than the window: the bar's width would widen the
    /// whole screen.
    private func topBar(width: CGFloat) -> some View {
        let badges = badgeVariants
        let rows: [BarVariant] = badges.map { BarVariant(badge: $0, showsHint: true, showsFeedback: true) }
            + badges.map { BarVariant(badge: $0, showsHint: true, showsFeedback: false) }
            + badges.suffix(1).map { BarVariant(badge: $0, showsHint: false, showsFeedback: false) }
        return GlassEffectContainer(spacing: 10) {
            // One `ForEach` of distinct rows: `ViewThatFits` traps on children sharing an id.
            ViewThatFits(in: .horizontal) {
                ForEach(rows, id: \.self) { row in
                    topBarRow(badge: row.badge, showsHint: row.showsHint, showsFeedback: row.showsFeedback)
                }
            }
            .frame(maxWidth: max(0, width - 2 * Self.edge))
        }
        // The bar keeps its 44 pt height (the canvas insets assume it); larger text sizes
        // reach its controls through the Large Content Viewer.
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
    }

    /// One way the top bar can be laid out (`topBar`).
    nonisolated private struct BarVariant: Hashable {
        var badge: BadgeVariant
        var showsHint: Bool
        var showsFeedback: Bool
    }

    private func topBarRow(badge: BadgeVariant, showsHint: Bool, showsFeedback: Bool) -> some View {
        // 8 pt apart: the buttons' glass sits inside their frames, so the shapes stay further
        // apart than the container's 10 pt and don't merge; six controls fit a 402 pt phone.
        HStack(spacing: 8) {
            if let onClose {
                GlassIconButton(systemImage: "xmark", label: "Close", action: onClose)
            }
            progressBadge(badge)
                .frame(maxWidth: .infinity, alignment: .leading)
            if photoLoader != nil {
                PhotoPeekButton(peek: $peek)
                    .disabled(photoUnavailable)
            }
            if showsHint {
                GlassIconButton(systemImage: "lightbulb", label: "Hint") { controller.showHint() }
                    .disabled(session.isComplete)
            }
            GlassIconButton(systemImage: "arrow.uturn.backward", label: "Undo", action: undo)
                .disabled(!session.isStarted)
            if showsFeedback {
                GlassIconButton(systemImage: "exclamationmark.bubble", label: "Give Feedback", action: startFeedback)
            }
            moreMenu(offersFeedback: !showsFeedback)
        }
    }

    /// What the progress badge shows: the ring, plus any of the title (when it fits whole),
    /// the percentage and, on regular widths, the selected color's name (compact widths show
    /// it above the palette instead).
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
        let showsColor = sizeClass == .regular && session.selectedColor != nil
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
        .frame(height: Self.barHeight)
        .glassEffect(.regular, in: .capsule)
    }

    /// `offersFeedback` when the bar has no room for Give Feedback.
    private func moreMenu(offersFeedback: Bool) -> some View {
        Menu {
            Toggle(isOn: $showsNumbers) { Label("Show Numbers", systemImage: "number") }
            Toggle(isOn: $zenMode) { Label("Zen Mode", systemImage: "leaf") }
            Button { controller.zoomToFit() } label: { Label("Fit to Screen", systemImage: "arrow.down.right.and.arrow.up.left") }
            if !session.isComplete { paletteMenu }
            if session.isComplete {
                Button { controller.replay() } label: { Label("Replay Painting", systemImage: "play") }
            }
            if offersFeedback {
                Button(action: startFeedback) { Label("Give Feedback…", systemImage: "exclamationmark.bubble") }
            }
            Divider()
            Button(role: .destructive) { confirmRestart = true } label: { Label("Restart", systemImage: "arrow.counterclockwise") }
        } label: {
            Image(systemName: "ellipsis")
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.primary)
                .frame(width: Self.barHeight, height: Self.barHeight)
                .glassEffect(.regular.interactive(), in: .circle)
        }
        .accessibilityLabel(Text("More"))
        .accessibilityShowsLargeContentViewer { Label("More", systemImage: "ellipsis") }
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
                session: session, title: title, share: completionShare, onReplay: controller.replay,
                onShareTimelapse: shareTimelapse, onClose: onClose)
                .transition(transition)
        } else {
            PaletteBar(
                session: session, axis: palette.side ? .vertical : .horizontal, lines: palette.lines,
                shakes: chrome.shakes, tip: swatchTip, metrics: palette.metrics, showsCurrentColor: palette.caption,
                order: colorOrder)
        }
    }

    // MARK: Actions

    /// The photo as a menu toggle (`p`), while there is one to show.
    private var photoBinding: Binding<Bool>? {
        guard photoLoader != nil, !photoUnavailable else { return nil }
        return Binding { peek.isShown } set: { peek.setLatched($0) }
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
        switch action {
        case .tap:
            if let current = session.selectedColor, let next = session.nextIncompleteColor(after: current) {
                session.select(color: next)
                FeedbackEngine.shared.selectionChanged()
            }
        case .squeeze:
            controller.showHint()
        case .lifted:
            PaintTips.record(.pencilUsed)
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
        withAnimation(reduceMotion ? nil : .snappy) { feedback = nil }
        // Back to the window's undo history of fills.
        controller.focus()
        Log.feedback.notice("Feedback ended")
    }

    /// The feedback was shared: the sheet goes, then feedback mode, and thanks.
    private func feedbackSent() {
        feedback?.isSent = true
        feedback?.isReviewing = false
        Task {
            try? await Task.sleep(for: .milliseconds(400))
            endFeedback()
            Announcer.announce(String(localized: "Thanks for the feedback!"))
            thanks = true
            try? await Task.sleep(for: .seconds(3))
            thanks = false
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

/// The progress badge's ring and percentage. They change with every fill, so they read the
/// session in a view of their own: a fill re-renders them, not the painting screen around them.
private struct ProgressGroup: View {
    let session: PaintingSession
    let title: String
    let showsTitle: Bool
    let showsPercent: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        #if DEBUG
        let _ = MainThreadWatchdog.count("ProgressGroup")
        #endif
        let fraction = session.fractionComplete
        // Whole percent, rounded down: 100 only once the last area is painted.
        let percent = Int(fraction * 100)
        HStack(spacing: 8) {
            ZStack {
                Circle().stroke(Color.primary.opacity(0.12), lineWidth: 3)
                ForEach(Array(paintedArcs.enumerated()), id: \.offset) { _, arc in
                    Circle()
                        .trim(from: arc.start, to: arc.end)
                        .stroke(arc.paint, style: StrokeStyle(lineWidth: 3))
                        .rotationEffect(.degrees(-90))
                }
            }
            .frame(width: 18, height: 18)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.4), value: fraction)
            if showsTitle {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .fixedSize()
            }
            if showsPercent {
                Text(Double(percent) / 100, format: .percent.precision(.fractionLength(0)))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(showsTitle ? Color.secondary : Color.primary)
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

    /// The ring fills in paint: each color's painted share of the areas, in palette order.
    private var paintedArcs: [(paint: Color, start: Double, end: Double)] {
        let total = Double(max(session.progress.regionCount, 1))
        var start = 0.0
        return (0..<session.paletteCount).compactMap { color -> (paint: Color, start: Double, end: Double)? in
            let painted = session.totalByColor[color] - session.remainingByColor[color]
            guard painted > 0 else { return nil }
            let end = start + Double(painted) / total
            defer { start = end }
            return (PaletteBar.paint(session.template, color), start, end)
        }
    }
}
