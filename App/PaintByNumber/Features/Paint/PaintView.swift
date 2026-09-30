import Observation
import PaintCore
import SwiftUI
import UIKit

/// The painting screen: full-bleed Metal canvas, floating Liquid Glass controls on top and
/// the palette at the bottom (trailing edge on a landscape iPad, see `PaletteLayout`).
///
/// Contract used by the rest of the app: `PaintView(session:title:onClose:)`. Persistence
/// lives outside (observe `session.revision`).
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
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.undoManager) private var undoManager

    private static let barHeight: CGFloat = 44
    private static let edge: CGFloat = 12

    init(
        session: PaintingSession, title: String = "", onClose: (() -> Void)? = nil,
        initialCamera: CanvasCamera? = nil, fillDurationScale: Float = 1
    ) {
        self.session = session
        self.title = title
        self.onClose = onClose
        self.initialCamera = initialCamera
        self.fillDurationScale = fillDurationScale
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
        .focusedSceneValue(\.painting, PaintingFocus(session: session, controller: controller, showsNumbers: $showsNumbers))
        .onAppear {
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
                showsNumbers: showsNumbers, initialCamera: initialCamera, fillDurationScale: fillDurationScale,
                onPencilAction: { handlePencil($0) }, onUnavailable: { canvasUnavailable = true })
                .id(ObjectIdentifier(session))
                .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
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
    /// at once in a few lines; compact ones scroll a single line.
    struct PaletteLayout: Equatable {
        var side: Bool
        var lines: Int
        var thickness: CGFloat { PaletteBar.thickness(lines: lines) }
    }

    private static let sidePaletteTop: CGFloat = 6 + barHeight + 12

    private func paletteLayout(in size: CGSize) -> PaletteLayout {
        let count = PaletteBar.visibleColors(session).count
        if sizeClass == .regular && size.width > size.height {
            let length = size.height - Self.sidePaletteTop - Self.edge
            return PaletteLayout(side: true, lines: PaletteBar.lines(count: count, length: length, maxLines: 2))
        }
        let length = size.width - 2 * Self.edge
        return PaletteLayout(
            side: false, lines: PaletteBar.lines(count: count, length: length, maxLines: sizeClass == .regular ? 3 : 1))
    }

    /// Canvas insets in full-screen coordinates: safe area plus the floating bars.
    private func canvasInsets(safe: EdgeInsets, palette: PaletteLayout) -> EdgeInsets {
        let top = safe.top + 6 + Self.barHeight + 6
        if session.isComplete {
            return EdgeInsets(top: top, leading: safe.leading, bottom: safe.bottom + 4 + PaletteBar.thickness + 6,
                              trailing: safe.trailing)
        }
        if palette.side {
            return EdgeInsets(top: top, leading: safe.leading, bottom: safe.bottom + 8,
                              trailing: safe.trailing + Self.edge + palette.thickness + 4)
        }
        return EdgeInsets(top: top, leading: safe.leading, bottom: safe.bottom + 4 + palette.thickness + 6,
                          trailing: safe.trailing)
    }

    // MARK: Top bar

    private var topBar: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                if let onClose {
                    GlassIconButton(systemImage: "xmark", label: "Close", action: onClose)
                }
                progressBadge
                Spacer(minLength: 0)
                GlassIconButton(systemImage: "lightbulb", label: "Hint") { controller.showHint() }
                    .disabled(session.isComplete)
                GlassIconButton(systemImage: "arrow.uturn.backward", label: "Undo", action: undo)
                    .disabled(session.progress.paintedCount == 0)
                moreMenu
            }
        }
    }

    private var progressBadge: some View {
        let fraction = session.fractionComplete
        // The title shows only when it fits whole (compact widths drop it).
        return ViewThatFits(in: .horizontal) {
            if !title.isEmpty { badgeContent(fraction: fraction, showsTitle: true) }
            badgeContent(fraction: fraction, showsTitle: false)
        }
        .frame(height: Self.barHeight)
        .glassEffect(.regular, in: .capsule)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title.isEmpty
            ? Text("\(Int(fraction * 100)) percent painted")
            : Text("\(title), \(Int(fraction * 100)) percent painted"))
    }

    private func badgeContent(fraction: Double, showsTitle: Bool) -> some View {
        HStack(spacing: 8) {
            ZStack {
                Circle().stroke(Color.primary.opacity(0.12), lineWidth: 3)
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 18, height: 18)
            .animation(.easeOut(duration: 0.4), value: fraction)
            if showsTitle {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .fixedSize()
            }
            Text(verbatim: "\(Int(fraction * 100))%")
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(showsTitle ? Color.secondary : Color.primary)
                .contentTransition(.numericText())
                .animation(.snappy, value: Int(fraction * 100))
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.horizontal, 14)
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
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.primary)
                .frame(width: Self.barHeight, height: Self.barHeight)
                .glassEffect(.regular.interactive(), in: .circle)
        }
        .accessibilityLabel(Text("More"))
    }

    // MARK: Bottom

    @ViewBuilder
    private func bottomBar(_ palette: PaletteLayout) -> some View {
        if session.isComplete {
            CompletionBar(
                session: session, title: title, onReplay: controller.replay, onShareTimelapse: shareTimelapse,
                onClose: onClose)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        } else {
            PaletteBar(
                session: session, axis: palette.side ? .vertical : .horizontal, lines: palette.lines,
                shakes: chrome.shakes)
        }
    }

    // MARK: Actions

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
    }
}

/// The symbol inside a circular glass button; the style's padding brings it to 44 pt.
struct GlassIconLabel: View {
    let systemImage: String

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(Color.primary)
            .frame(width: 30, height: 30)
    }
}

/// Replaces the palette once the painting is finished.
private struct CompletionBar: View {
    let session: PaintingSession
    let title: String
    let onReplay: () -> Void
    let onShareTimelapse: () -> Void
    let onClose: (() -> Void)?
    @State private var shareImage: Image?

    init(
        session: PaintingSession, title: String, onReplay: @escaping () -> Void,
        onShareTimelapse: @escaping () -> Void, onClose: (() -> Void)?
    ) {
        self.session = session
        self.title = title
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
                Text(title.isEmpty ? "Every region is painted." : title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            // The buttons keep their size on a phone; the caption truncates instead.
            .lineLimit(1)
            Spacer(minLength: 0)
            Button(action: onReplay) {
                GlassIconLabel(systemImage: "play.fill")
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .accessibilityLabel(Text("Replay"))
            if let shareImage {
                let name = title.isEmpty ? String(localized: "Painting") : title
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
            }
            if let onClose {
                Button(action: onClose) {
                    Text("Done").lineLimit(1).fixedSize()
                }
                .buttonStyle(.glassProminent)
                .fixedSize()
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
        .frame(minHeight: PaletteBar.thickness)
        .frame(maxWidth: 560)
        // One compact row even at the largest text sizes.
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .glassEffect(.regular, in: .capsule)
        .task(id: session.revision) {
            let data = await Self.renderShareImage(template: session.template, progress: session.progress)
            if let data, let image = UIImage(data: data) { shareImage = Image(uiImage: image) }
        }
    }

    @concurrent
    private static func renderShareImage(template: Template, progress: PaintProgress) async -> Data? {
        let size = CanvasSnapshot.fittedSize(for: template, longSide: 2048)
        guard let image = CanvasSnapshot.render(template: template, progress: progress, size: size, options: .painting) else { return nil }
        return CanvasSnapshot.pngData(image)
    }
}

/// Transient chrome reactions to painting events, and undo registration.
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
        session.onEvent { [weak self, weak controller, weak session] event in
            switch event {
            case let .painted(regions, _):
                if let session, !session.isStroking { self?.registerUndo(of: regions.count, in: session) }
            case let .strokeEnded(regions):
                if let session { self?.registerUndo(of: regions.count, in: session) }
            case let .rejected(_, expected):
                withAnimation(.linear(duration: 0.45)) { self?.shakes[expected, default: 0] += 1 }
            case .artworkCompleted:
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
