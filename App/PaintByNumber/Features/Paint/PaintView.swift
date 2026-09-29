import Observation
import PaintCore
import SwiftUI
import UIKit

/// The painting screen: full-bleed Metal canvas, floating Liquid Glass controls on top and
/// the palette at the bottom (trailing edge on a landscape iPad).
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
    @Environment(\.horizontalSizeClass) private var sizeClass

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
            let sidePalette = sizeClass == .regular && geo.size.width > geo.size.height
            ZStack {
                PaintCanvas(
                    session: session, controller: controller,
                    chromeInsets: canvasInsets(safe: geo.safeAreaInsets, sidePalette: sidePalette),
                    showsNumbers: showsNumbers, initialCamera: initialCamera, fillDurationScale: fillDurationScale,
                    onPencilAction: { handlePencil($0) })
                    .id(ObjectIdentifier(session))
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    topBar
                        .padding(.horizontal, Self.edge)
                        .padding(.top, 6)
                    Spacer(minLength: 0)
                    if !sidePalette || session.isComplete {
                        bottomBar(side: false)
                            .padding(.horizontal, Self.edge)
                            .padding(.bottom, 4)
                    }
                }
                if sidePalette && !session.isComplete {
                    HStack {
                        Spacer(minLength: 0)
                        bottomBar(side: true)
                            .padding(.trailing, Self.edge)
                            .padding(.vertical, Self.barHeight + 24)
                    }
                }
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .onAppear {
            FeedbackAttachment.attach(session)
            chrome.observe(session, controller: controller)
            RenderContext.prewarm()
        }
        .confirmationDialog("Restart this painting?", isPresented: $confirmRestart, titleVisibility: .visible) {
            Button("Restart", role: .destructive) { session.reset() }
        } message: {
            Text("All paint will be cleared.")
        }
    }

    // MARK: Layout

    /// Canvas insets in full-screen coordinates: safe area plus the floating bars.
    private func canvasInsets(safe: EdgeInsets, sidePalette: Bool) -> EdgeInsets {
        let top = safe.top + 6 + Self.barHeight + 6
        if sidePalette && !session.isComplete {
            return EdgeInsets(top: top, leading: safe.leading, bottom: safe.bottom + 8,
                              trailing: safe.trailing + Self.edge + PaletteBar.thickness + 4)
        }
        return EdgeInsets(top: top, leading: safe.leading, bottom: safe.bottom + 4 + PaletteBar.thickness + 6,
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
                GlassIconButton(systemImage: "arrow.uturn.backward", label: "Undo") { session.undo() }
                    .disabled(session.progress.paintedCount == 0)
                moreMenu
            }
        }
    }

    private var progressBadge: some View {
        let fraction = session.fractionComplete
        return HStack(spacing: 8) {
            ZStack {
                Circle().stroke(Color.primary.opacity(0.12), lineWidth: 3)
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 18, height: 18)
            .animation(.easeOut(duration: 0.4), value: fraction)
            if !title.isEmpty {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
            }
            Text(verbatim: "\(Int(fraction * 100))%")
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(title.isEmpty ? Color.primary : Color.secondary)
                .contentTransition(.numericText())
                .animation(.snappy, value: Int(fraction * 100))
        }
        .padding(.horizontal, 14)
        .frame(height: Self.barHeight)
        .glassEffect(.regular, in: .capsule)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(Int(fraction * 100)) percent painted"))
    }

    private var moreMenu: some View {
        Menu {
            Toggle(isOn: $showsNumbers) { Label("Show Numbers", systemImage: "number") }
            Button { controller.zoomToFit() } label: { Label("Fit to Screen", systemImage: "arrow.down.right.and.arrow.up.left") }
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
    private func bottomBar(side: Bool) -> some View {
        if session.isComplete && !side {
            CompletionBar(session: session, title: title, onClose: onClose)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        } else {
            PaletteBar(session: session, axis: side ? .vertical : .horizontal, shakes: chrome.shakes)
        }
    }

    // MARK: Actions

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

/// A 44 pt circular Liquid Glass button with an SF Symbol.
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
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 44, height: 44)
                .opacity(isEnabled ? 1 : 0.35)
                .glassEffect(.regular.interactive(), in: .circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
    }
}

/// Replaces the palette once the painting is finished.
private struct CompletionBar: View {
    let session: PaintingSession
    let title: String
    let onClose: (() -> Void)?
    @State private var shareImage: Image?

    init(session: PaintingSession, title: String, onClose: (() -> Void)?) {
        self.session = session
        self.title = title
        self.onClose = onClose
    }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 28))
                .foregroundStyle(.tint)
                .symbolEffect(.bounce, value: session.isComplete)
            VStack(alignment: .leading, spacing: 2) {
                Text("Finished!").font(.headline)
                Text(title.isEmpty ? "Every region is painted." : title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if let shareImage {
                ShareLink(item: shareImage, preview: SharePreview(title.isEmpty ? "Painting" : title, image: shareImage)) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .glassEffect(.regular.interactive(), in: .circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Share"))
            }
            if let onClose {
                Button("Done", action: onClose)
                    .buttonStyle(.glassProminent)
            }
        }
        .padding(.horizontal, 18)
        .frame(height: PaletteBar.thickness)
        .frame(maxWidth: 560)
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

/// Transient chrome reactions to painting events.
@Observable
final class PaintChromeState {
    /// Per color: bumped to shake its swatch.
    var shakes: [Int: Int] = [:]
    @ObservationIgnored private var observed: ObjectIdentifier?

    func observe(_ session: PaintingSession, controller: CanvasController) {
        guard observed != ObjectIdentifier(session) else { return }
        observed = ObjectIdentifier(session)
        session.onEvent { [weak self, weak controller] event in
            switch event {
            case let .rejected(_, expected):
                withAnimation(.linear(duration: 0.45)) { self?.shakes[expected, default: 0] += 1 }
            case .artworkCompleted:
                controller?.zoomToFit()
            default:
                break
            }
        }
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
