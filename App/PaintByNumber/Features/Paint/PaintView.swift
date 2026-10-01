import Foundation
import Observation
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
struct PaintView: View {
    let session: PaintingSession
    var title: String = ""
    var onClose: (() -> Void)?
    /// Where the canvas first looks (demos, restored sessions); nil = fit.
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

    private static let barHeight: CGFloat = 44
    private static let edge: CGFloat = 12

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
            if canvasUnavailable {
                CanvasUnavailableView(onClose: onClose)
            } else {
                canvasAndChrome(geo: geo, palette: paletteLayout(in: geo.size))
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .focusedSceneValue(\.painting, PaintingFocus(
            session: session, controller: controller, showsNumbers: $showsNumbers, showsPhoto: photoBinding))
        .onAppear {
            if tips == nil { tips = PaintTips.makeGroup() }
            FeedbackAttachment.attach(session)
            chrome.undoManager = undoManager
            chrome.observe(session, controller: controller)
            RenderContext.prewarm()
        }
        .onChange(of: undoManager) { _, manager in chrome.undoManager = manager }
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
    }

    /// The Metal canvas with the floating bars over it.
    private func canvasAndChrome(geo: GeometryProxy, palette: PaletteLayout) -> some View {
        ZStack {
            PaintCanvas(
                session: session, controller: controller,
                chromeInsets: canvasInsets(safe: geo.safeAreaInsets, palette: palette),
                showsNumbers: showsNumbers, paperAppearance: paperAppearance,
                initialCamera: initialCamera, fillDurationScale: fillDurationScale,
                onPencilAction: { handlePencil($0) }, onUnavailable: { canvasUnavailable = true },
                photoLoader: photoLoader, showsPhoto: peek.isShown,
                onPhotoUnavailable: {
                    photoUnavailable = true
                    peek = PhotoPeek()
                },
                onDismissPhoto: { peek.setLatched(false) },
                onZoomStep: { PaintTips.record(.zoomedByDoubleTap) })
                .id(ObjectIdentifier(session))
                .ignoresSafeArea()

            // Canvas tips point at the middle of the visible canvas.
            Color.clear
                .frame(width: 1, height: 1)
                .popoverTip(canvasTip)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(visibleCanvasPadding(safe: geo.safeAreaInsets, palette: palette))
                .allowsHitTesting(false)

            VStack(spacing: 0) {
                topBar(width: geo.size.width)
                    .padding(.horizontal, Self.edge)
                    .padding(.top, 6)
                Spacer(minLength: 0)
                if !palette.side || session.isComplete {
                    bottomBar(palette)
                        .padding(.horizontal, Self.edge)
                        .padding(.bottom, 4)
                }
            }
            if palette.side && !session.isComplete {
                HStack {
                    Spacer(minLength: 0)
                    bottomBar(palette)
                        .padding(.trailing, Self.edge)
                        .padding(.top, Self.sidePaletteTop)
                        .padding(.bottom, Self.edge)
                }
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

    private var paletteMetrics: PaletteMetrics { PaletteMetrics(dynamicTypeSize: dynamicTypeSize) }

    private static let sidePaletteTop: CGFloat = 6 + barHeight + 12

    private func paletteLayout(in size: CGSize) -> PaletteLayout {
        let count = PaletteBar.visibleColors(session).count
        let metrics = paletteMetrics
        if sizeClass == .regular && size.width > size.height {
            let length = size.height - Self.sidePaletteTop - Self.edge
            return PaletteLayout(
                side: true, lines: metrics.lines(count: count, length: length, maxLines: 2), caption: false,
                metrics: metrics)
        }
        let length = size.width - 2 * Self.edge
        return PaletteLayout(
            side: false, lines: metrics.lines(count: count, length: length, maxLines: sizeClass == .regular ? 3 : 1),
            caption: sizeClass != .regular, metrics: metrics)
    }

    /// Canvas insets in full-screen coordinates: safe area plus the floating bars.
    private func canvasInsets(safe: EdgeInsets, palette: PaletteLayout) -> EdgeInsets {
        let top = safe.top + 6 + Self.barHeight + 6
        if session.isComplete {
            return EdgeInsets(top: top, leading: safe.leading, bottom: safe.bottom + 4 + CompletionBar.height + 6,
                              trailing: safe.trailing)
        }
        if palette.side {
            return EdgeInsets(top: top, leading: safe.leading, bottom: safe.bottom + 8,
                              trailing: safe.trailing + Self.edge + palette.thickness + 4)
        }
        return EdgeInsets(top: top, leading: safe.leading, bottom: safe.bottom + 4 + palette.thickness + 6,
                          trailing: safe.trailing)
    }

    /// The canvas's visible area within the safe area (the canvas itself ignores it).
    private func visibleCanvasPadding(safe: EdgeInsets, palette: PaletteLayout) -> EdgeInsets {
        let insets = canvasInsets(safe: safe, palette: palette)
        return EdgeInsets(
            top: max(0, insets.top - safe.top), leading: max(0, insets.leading - safe.leading),
            bottom: max(0, insets.bottom - safe.bottom), trailing: max(0, insets.trailing - safe.trailing))
    }

    // MARK: Tips

    /// Tips about canvas gestures; the rest belong to the selected swatch.
    private var canvasTip: (any Tip)? {
        guard let tip = tips?.currentTip, tip is DragPaintTip || tip is ZoomTip || tip is PencilTip else { return nil }
        return tip
    }

    private var swatchTip: (any Tip)? {
        guard let tip = tips?.currentTip, tip is FirstPaintTip || tip is HintTip else { return nil }
        return tip
    }

    // MARK: Top bar

    /// Close, the progress badge, then Photo, Hint, Undo and More, as the first of these that
    /// fits: each badge variant (largest first, down to its ring and percentage) with every
    /// control, then the smallest badge without Hint, which the selected swatch and the `h` key
    /// still offer (the narrowest windows). Nothing here may grow wider than the window: the
    /// bar's width would widen the whole screen.
    private func topBar(width: CGFloat) -> some View {
        let badges = badgeVariants
        return GlassEffectContainer(spacing: 10) {
            ViewThatFits(in: .horizontal) {
                ForEach(badges, id: \.self) { badge in
                    topBarRow(badge: badge, showsHint: true)
                }
                if let smallest = badges.last {
                    topBarRow(badge: smallest, showsHint: false)
                }
            }
            .frame(maxWidth: max(0, width - 2 * Self.edge))
        }
        // The bar keeps its 44 pt height (the canvas insets assume it); larger text sizes
        // reach its controls through the Large Content Viewer.
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
    }

    private func topBarRow(badge: BadgeVariant, showsHint: Bool) -> some View {
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
                .disabled(session.progress.paintedCount == 0)
            moreMenu
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
        badgeVariant(
            fraction: session.fractionComplete, showsTitle: variant.showsTitle, showsPercent: variant.showsPercent,
            showsColor: variant.showsColor, shrinksColor: variant.shrinksColor)
            .frame(height: Self.barHeight)
            .glassEffect(.regular, in: .capsule)
    }

    private func badgeVariant(
        fraction: Double, showsTitle: Bool, showsPercent: Bool, showsColor: Bool, shrinksColor: Bool = false
    ) -> some View {
        HStack(spacing: 10) {
            progressGroup(fraction: fraction, showsTitle: showsTitle, showsPercent: showsPercent)
            if showsColor {
                Capsule()
                    .fill(Color.primary.opacity(0.15))
                    .frame(width: 1, height: 18)
                    .accessibilityHidden(true)
                if shrinksColor {
                    CurrentColorLabel(session: session, font: .subheadline.weight(.semibold))
                        .frame(idealWidth: 60, alignment: .leading)
                } else {
                    CurrentColorLabel(session: session, font: .subheadline.weight(.semibold))
                        .fixedSize()
                }
            }
        }
        .padding(.horizontal, 14)
    }

    private func progressGroup(fraction: Double, showsTitle: Bool, showsPercent: Bool) -> some View {
        // Whole percent, rounded down: 100 only once the last area is painted.
        let percent = Int(fraction * 100)
        return HStack(spacing: 8) {
            ZStack {
                Circle().stroke(Color.primary.opacity(0.12), lineWidth: 3)
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
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

    private var moreMenu: some View {
        Menu {
            Toggle(isOn: $showsNumbers) { Label("Show Numbers", systemImage: "number") }
            Button { controller.zoomToFit() } label: { Label("Fit to Screen", systemImage: "arrow.down.right.and.arrow.up.left") }
            if session.isComplete {
                Button { controller.replay() } label: { Label("Replay Painting", systemImage: "play") }
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
                shakes: chrome.shakes, tip: swatchTip, metrics: palette.metrics, showsCurrentColor: palette.caption)
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
}

/// A 44 pt circular Liquid Glass button with an SF Symbol. Uses the system glass button style:
/// interactive glass on a plain button's label swallows the tap, so the action never ran.
struct GlassIconButton: View {
    let systemImage: String
    let label: LocalizedStringKey
    let action: () -> Void

    init(systemImage: String, label: LocalizedStringKey, action: @escaping () -> Void) {
        self.systemImage = systemImage
        self.label = label
        self.action = action
    }

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            GlassIconLabel(systemImage: systemImage)
                .opacity(isEnabled ? 1 : 0.35)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .accessibilityLabel(Text(label))
        .accessibilityShowsLargeContentViewer { Label(label, systemImage: systemImage) }
    }
}

/// The symbol inside a circular glass button; the style's padding brings it to 44 pt.
struct GlassIconLabel: View {
    let systemImage: String

    var body: some View {
        Image(systemName: systemImage)
            .font(.body.weight(.semibold))
            .foregroundStyle(Color.primary)
            .frame(width: 30, height: 30)
    }
}

/// Replaces the palette once the painting is finished.
private struct CompletionBar: View {
    /// As tall as a one-line palette, so the canvas keeps its place when the painting finishes.
    static let height = PaletteMetrics.standard.thickness(lines: 1, caption: false)

    let session: PaintingSession
    let title: String
    let share: CompletionShare
    let onReplay: () -> Void
    let onShareTimelapse: () -> Void
    let onClose: (() -> Void)?

    init(
        session: PaintingSession, title: String, share: CompletionShare, onReplay: @escaping () -> Void,
        onShareTimelapse: @escaping () -> Void, onClose: (() -> Void)?
    ) {
        self.session = session
        self.title = title
        self.share = share
        self.onReplay = onReplay
        self.onShareTimelapse = onShareTimelapse
        self.onClose = onClose
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 28))
                .foregroundStyle(.tint)
                .symbolEffect(.bounce, value: session.isComplete)
            VStack(alignment: .leading, spacing: 2) {
                Text("Finished!").font(.headline)
                Group {
                    if title.isEmpty {
                        Text("Every region is painted.")
                    } else {
                        Text(title)
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            // The buttons keep their size on a phone; the caption shrinks, then truncates.
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            Spacer(minLength: 0)
            Button(action: onReplay) {
                GlassIconLabel(systemImage: "play.fill")
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .accessibilityLabel(Text("Replay"))
            .accessibilityShowsLargeContentViewer { Label("Replay", systemImage: "play.fill") }
            if let picture = share.picture {
                let name = title.isEmpty ? String(localized: "Painting") : title
                // UIImage keeps the picture's Display P3 colors.
                let shareImage = Image(uiImage: UIImage(cgImage: picture))
                Menu {
                    ShareLink(item: shareImage, preview: SharePreview(name, image: shareImage)) {
                        Label("Share Picture", systemImage: "photo")
                    }
                    Button { onShareTimelapse() } label: {
                        Label("Share Time-lapse", systemImage: "timelapse")
                    }
                } label: {
                    GlassIconLabel(systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .accessibilityLabel(Text("Share"))
                .accessibilityShowsLargeContentViewer { Label("Share", systemImage: "square.and.arrow.up") }
            }
            if let onClose {
                Button(action: onClose) {
                    Text("Done").lineLimit(1).fixedSize()
                }
                .buttonStyle(.glassProminent)
                .fixedSize()
                .accessibilityShowsLargeContentViewer()
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
        .frame(minHeight: Self.height)
        .frame(maxWidth: 560)
        // One compact row even at the largest text sizes: the canvas insets assume its height,
        // and the Large Content Viewer shows its buttons enlarged.
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .glassEffect(.regular, in: .capsule)
        .task(id: session.revision) { await share.prepare(for: session) }
    }
}

/// The finished painting as a picture to share, rendered once per completion (the bar
/// showing it is rebuilt far more often: layout changes, the palette moving aside).
@Observable
final class CompletionShare {
    private(set) var picture: CGImage?
    /// The session revision `picture` shows (or is being rendered for).
    @ObservationIgnored private var revision: Int?

    func prepare(for session: PaintingSession) async {
        guard session.isComplete, revision != session.revision else { return }
        let target = session.revision
        revision = target
        picture = nil
        let image = await Self.render(template: session.template, progress: session.progress)
        // Undone and finished again meanwhile: that completion renders its own.
        guard revision == target else { return }
        picture = image
        // A failed render may succeed next time the bar appears.
        if image == nil { revision = nil }
    }

    @concurrent
    private static func render(template: Template, progress: PaintProgress) async -> CGImage? {
        let size = CanvasSnapshot.fittedSize(for: template, longSide: 2048)
        return CanvasSnapshot.render(template: template, progress: progress, size: size, options: .painting)
    }
}

/// Transient chrome reactions to painting events, undo registration, and the tips they feed.
@Observable
final class PaintChromeState {
    /// Per color: bumped to shake its swatch.
    var shakes: [Int: Int] = [:]
    /// The window's undo manager: every fill is registered with it (⌘Z, the Edit menu,
    /// three-finger undo and redo).
    @ObservationIgnored weak var undoManager: UndoManager?
    @ObservationIgnored private var observed: ObjectIdentifier?

    func observe(_ session: PaintingSession, controller: CanvasController) {
        guard observed != ObjectIdentifier(session) else { return }
        observed = ObjectIdentifier(session)
        PaintTips.paintingOpened(hasProgress: session.progress.paintedCount > 0)
        session.onEvent { [weak self, weak controller, weak session] event in
            if let session, let signal = PaintTips.signal(for: event, isStroking: session.isStroking) {
                PaintTips.record(signal)
            }
            switch event {
            case let .painted(regions, _):
                if let session, !session.isStroking { self?.registerUndo(of: regions.count, in: session) }
            case let .strokeEnded(regions):
                if let session { self?.registerUndo(of: regions.count, in: session) }
            case let .rejected(_, expected):
                // Without animation the shake's whole-number step leaves the swatch in place.
                withAnimation(UIAccessibility.isReduceMotionEnabled ? nil : .linear(duration: 0.45)) {
                    self?.shakes[expected, default: 0] += 1
                }
            case let .colorCompleted(color):
                if let session {
                    Announcer.announce(PaintSpeech.colorFinished(number: color + 1, name: session.colorNames[color], nickname: session.nickname(of: color)))
                }
            case .artworkCompleted:
                Announcer.announce(PaintSpeech.paintingFinished)
                controller?.zoomToFit()
            default:
                break
            }
        }
    }

    /// Undo takes back the fills of one tap or one whole stroke. Redoing paints them again,
    /// which registers the next undo through the same event.
    private func registerUndo(of count: Int, in session: PaintingSession) {
        guard let undoManager else { return }
        // UndoManager calls back on the thread that undoes: the main thread.
        undoManager.registerUndo(withTarget: session) { [weak self] session in
            MainActor.assumeIsolated { self?.undoFills(count, in: session) }
        }
        undoManager.setActionName(String(localized: "Paint"))
    }

    private func undoFills(_ count: Int, in session: PaintingSession) {
        let undone = (0..<count).compactMap { _ in session.undo() }
        guard let undoManager, let first = undone.first else { return }
        undoManager.registerUndo(withTarget: session) { session in
            MainActor.assumeIsolated {
                let origin = session.template.labels(ofRegion: first).first?.position ?? .zero
                session.paint(undone.reversed(), from: origin, animated: true)
            }
        }
        undoManager.setActionName(String(localized: "Paint"))
    }
}

/// Attaches haptics and sound to a session exactly once, however often its screen appears.
@MainActor
enum FeedbackAttachment {
    private final class Box {
        weak var session: PaintingSession?
        init(_ session: PaintingSession) { self.session = session }
    }

    private static var attached: [Box] = []

    static func attach(_ session: PaintingSession) {
        attached.removeAll { $0.session == nil }
        guard !attached.contains(where: { $0.session === session }) else { return }
        attached.append(Box(session))
        FeedbackEngine.shared.attach(to: session)
        FeedbackEngine.shared.prepare()
    }
}
