#if UNRELEASED
import CoreGraphics
import Observation
import PaintCore
import SwiftUI
import UIKit

/// Glazing a window (painting-company row 366; Paul's free glazing, November 20, 2026): the room
/// dark, the window's glass unlit, each piece keeping a faint tint of the glass the photo
/// suggests, and below it the glasses as beads, the window's own then the glazier's classics
/// (`GlassPalette.offered`). Any glass goes in any piece: a touch, or a drag across pieces, pours
/// the bead's glass in from the finger, lit. Glazed whole, the sun passes behind the window once.
/// The window is on the painting screen's own canvas (`GlassCanvas`), in Stained Glass's mode
/// (`GlassMode`).
@MainActor
@Observable
final class GlassGlazeModel: CanvasTouches {
    let id: UUID
    let template: Template
    let offered: [PaletteColor]
    /// How the canvas draws the window (`CanvasMode`), made off the main actor.
    @ObservationIgnored let mode: GlassMode
    /// The canvas's session: the window's template; its rules never paint, since the window's
    /// touches come here (`CanvasView.touches`).
    @ObservationIgnored let session: PaintingSession
    /// The canvas glazing shows on, once it is made.
    @ObservationIgnored weak var canvas: CanvasView? {
        didSet { if canvas !== oldValue { showAll() } }
    }
    private(set) var glazing: Glazing
    /// The bead in hand: a place in `offered`.
    var selected = 0
    /// When the window was glazed whole on screen, for the sun's pass.
    private(set) var finishedAt: Date?
    /// The glasses are put away (a finished window stands alone): a touch brings them back and
    /// pours nothing (`beadsAsked`).
    var beadsHidden = false
    /// A touch asked for the glasses back.
    private(set) var beadsAsked = 0
    @ObservationIgnored var reduceMotion = false
    /// Where a demo holds the sun's pass (0…1), or nil.
    @ObservationIgnored var sunHold: Float?
    @ObservationIgnored private var undoStack: [[(region: Int, glass: Int16)]] = []
    @ObservationIgnored private var stroke: [(region: Int, glass: Int16)]?
    /// The touch under way only brought the glasses back.
    @ObservationIgnored private var touchShowedBeads = false
    @ObservationIgnored private var saving: Task<Void, Never>?
    private(set) var canUndo = false
    @ObservationIgnored var onChange: @MainActor (Glazing) -> Void = { _ in }

    init(id: UUID, template: Template, glazing: Glazing, offered: [PaletteColor], mode: GlassMode) {
        self.id = id
        self.template = template
        self.glazing = glazing
        self.offered = offered
        self.mode = mode
        session = PaintingSession(template: template)
        // The bead in hand at first: the glass suggested for the largest piece left unglazed.
        let largest = template.regions.indices.filter { glazing.glass[$0] == Glazing.none }
            .max { template.regions[$0].area < template.regions[$1].area }
        selected = min(largest.map { Int(template.regions[$0].colorIndex) } ?? 0, max(0, offered.count - 1))
    }

    var pieces: Int { template.regions.count }
    var glazedCount: Int { glazing.glazedCount }
    var isComplete: Bool { glazedCount == pieces }

    /// The piece under `p` (canvas units), if any.
    func piece(at p: SIMD2<Float>) -> Int? {
        let x = Int(p.x.rounded(.down)), y = Int(p.y.rounded(.down))
        guard x >= 0, y >= 0, x < template.width, y < template.height else { return nil }
        let r = Int(template.regionMap[x, y])
        return r < pieces ? r : nil
    }

    /// A touch on the canvas: a tap pours into one piece, a stroke into each it crosses.
    func canvas(_ canvas: CanvasView, touched point: SIMD2<Float>, phase: CanvasTouchPhase) {
        if phase == .tap || phase == .began {
            touchShowedBeads = beadsHidden
            if beadsHidden { beadsAsked += 1 }
        }
        if !touchShowedBeads, phase != .ended, let r = piece(at: point) {
            glaze(r, from: point, animated: true)
        }
        if phase == .tap || phase == .ended {
            touchShowedBeads = false
            endStroke()
        }
    }

    /// Pours the bead in hand into piece `r` from `p` (none: VoiceOver's activation, a stroke of
    /// its own).
    func glaze(_ r: Int, from p: SIMD2<Float>? = nil, animated: Bool) {
        let glass = Int16(selected)
        guard r < pieces, selected < offered.count, glazing.glass[r] != glass else { return }
        let wasComplete = isComplete
        let before = glazing.glass[r]
        if stroke == nil { stroke = [] }
        stroke?.append((r, before))
        glazing.glass[r] = glass
        canvas?.showMode(r, value: GlassMode.code(glass: Int(glass), replacing: Self.glass(before)), painted: true,
                         from: p, animated: animated)
        if isComplete && !wasComplete { finished() }
        if p == nil { endStroke() }
        changed()
    }

    func endStroke() {
        guard let stroke, !stroke.isEmpty else { self.stroke = nil; return }
        undoStack.append(stroke)
        self.stroke = nil
        canUndo = true
    }

    func undo() {
        endStroke()
        guard let last = undoStack.popLast() else { return }
        for step in last.reversed() {
            let now = glazing.glass[step.region]
            glazing.glass[step.region] = step.glass
            if let back = Self.glass(step.glass) {
                canvas?.showMode(step.region, value: GlassMode.code(glass: back, replacing: Self.glass(now)), painted: true,
                                 from: nil, animated: true)
            } else {
                canvas?.showMode(step.region, value: GlassMode.code(glass: Self.glass(now), replacing: nil), painted: false,
                                 from: nil, animated: true)
            }
        }
        if !isComplete {
            finishedAt = nil
            mode.sun(at: 0, passes: false)
        }
        canUndo = !undoStack.isEmpty
        changed()
    }

    /// The window just finished, held `elapsed` seconds into the sun's pass (demos).
    func finish(heldAt elapsed: TimeInterval) {
        sunHold = Float(elapsed) / GlassMode.sunDuration
        finished()
    }

    private func finished() {
        finishedAt = .now
        mode.sun(at: canvas?.canvasTime ?? 0, held: sunHold, passes: !reduceMotion)
    }

    /// Every glazed piece shown on a canvas just made, as it stands.
    private func showAll() {
        guard let canvas else { return }
        for r in 0..<pieces {
            guard let glass = Self.glass(glazing.glass[r]) else { continue }
            canvas.showMode(r, value: GlassMode.code(glass: glass, replacing: nil), painted: true, from: nil, animated: false)
        }
        if finishedAt != nil { mode.sun(at: canvas.canvasTime, held: sunHold, passes: !reduceMotion) }
    }

    /// A glazing's glass as a place in `offered`, nil for none.
    private static func glass(_ g: Int16) -> Int? { g >= 0 ? Int(g) : nil }

    private func changed() {
        saving?.cancel()
        let glazing = glazing
        saving = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            onChange(glazing)
        }
    }

    /// Saves at once (leaving the screen).
    func flush() {
        guard saving != nil else { return }
        saving?.cancel()
        saving = nil
        onChange(glazing)
    }

    func name(of glass: Int) -> String {
        ColorNameText.title(ColorName(oklab: offered[glass].oklab))
    }
}

/// The canvas glazing shows on: the painting screen's own (`CanvasView`), pinch, pan and all,
/// in Stained Glass's mode, its touches the window's.
struct GlassCanvas: UIViewRepresentable {
    let model: GlassGlazeModel

    func makeUIView(context: Context) -> CanvasView {
        let view = CanvasView(session: model.session)
        view.reduceMotion = context.environment.accessibilityReduceMotion
        view.mode = model.mode
        view.touches = model
        view.backgroundColor = UIColor(GlassPicture.color(GlassPicture.nave, space: .sRGB))
        // The pieces are VoiceOver's (`GlassGlazeView.pieceElements`), not the canvas's numbers.
        view.accessibilityElementsHidden = true
        model.reduceMotion = context.environment.accessibilityReduceMotion
        model.canvas = view
        return view
    }

    func updateUIView(_ view: CanvasView, context: Context) {
        view.reduceMotion = context.environment.accessibilityReduceMotion
        model.reduceMotion = context.environment.accessibilityReduceMotion
    }

    static func dismantleUIView(_ view: CanvasView, coordinator: Coordinator) {
        view.tearDown()
    }
}

struct GlassGlazeView: View {
    @State var model: GlassGlazeModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    /// Whether the glasses are out: glazed whole, the window stands alone in the dark until a
    /// touch brings them back.
    @State private var showsBeads: Bool
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver

    init(model: GlassGlazeModel) {
        _model = State(initialValue: model)
        _showsBeads = State(initialValue: !model.isComplete)
    }

    var body: some View {
        VStack(spacing: 0) {
            GlassCanvas(model: model)
                .overlay {
                    GeometryReader { proxy in
                        let fit = GlassFit(width: model.template.width, height: model.template.height, in: proxy.size, margin: 28)
                        Color.clear
                            .accessibilityElement(children: .contain)
                            .accessibilityLabel(Text("Window"))
                            .accessibilityValue(Text(progressText))
                            .accessibilityChildren { pieceElements(fit: fit) }
                    }
                    .allowsHitTesting(false)
                }
            if showsBeads || voiceOver {
                beads.transition(.opacity)
            }
        }
        .background(GlassPicture.color(GlassPicture.nave, space: .sRGB).ignoresSafeArea())
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Undo", systemImage: "arrow.uturn.backward") { model.undo() }
                    .disabled(!model.canUndo)
                    .keyboardShortcut("z", modifiers: .command)
                    .accessibilityIdentifier("glass-undo")
            }
        }
        .onChange(of: model.isComplete) { _, complete in
            setBeads(shown: !complete, duration: 0.6)
            guard complete else { return }
            AccessibilityNotification.Announcement(String(
                localized: "glass.finished", defaultValue: "The sun passes behind your window.",
                comment: "VoiceOver announcement when every piece of a stained glass window is glazed")).post()
        }
        .onChange(of: model.beadsAsked) { setBeads(shown: true, duration: 0.35) }
        .onAppear { model.beadsHidden = !showsBeads }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { model.flush() }
        }
        .onDisappear { model.flush() }
    }

    private func setBeads(shown: Bool, duration: TimeInterval) {
        model.beadsHidden = !shown
        withAnimation(reduceMotion ? nil : .easeInOut(duration: duration)) { showsBeads = shown }
    }

    private var progressText: String {
        String(localized: "glass.progress", defaultValue: "Glazed: \(model.glazedCount) of \(model.pieces)",
               comment: "VoiceOver value of a stained glass window: pieces glazed of all its pieces")
    }

    /// One element a piece for VoiceOver, at its number's place: its glass or none, and an
    /// activation that pours the bead in hand.
    private func pieceElements(fit: GlassFit) -> some View {
        ForEach(0..<model.pieces, id: \.self) { r in
            let at = model.template.labels(ofRegion: r).first.map { CGPoint($0.position).applying(fit.transform) }
                ?? CGPoint(x: fit.rect.midX, y: fit.rect.midY)
            let glass = Int(model.glazing.glass[r])
            Color.clear
                .frame(width: 44, height: 44)
                .position(at)
                .accessibilityElement()
                .accessibilityLabel(Text(String(localized: "glass.piece", defaultValue: "Piece \(r + 1)",
                                                comment: "VoiceOver name of one piece of a stained glass window, by its number")))
                .accessibilityValue(Text(glass >= 0 && glass < model.offered.count ? model.name(of: glass) : String(
                    localized: "glass.unglazed", defaultValue: "Unglazed",
                    comment: "VoiceOver value of a piece of stained glass with no glass in it yet")))
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { model.glaze(r, animated: false) }
        }
    }

    // MARK: Beads

    private var beads: some View {
        VStack(spacing: 6) {
            ScrollView(.horizontal) {
                HStack(spacing: 14) {
                    ForEach(model.offered.indices, id: \.self) { g in
                        // The window's own glasses, then a breath, then the glazier's classics.
                        if g == model.template.palette.count && g > 0 {
                            Color.clear.frame(width: 10, height: 1).accessibilityHidden(true)
                        }
                        bead(g)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
            .scrollIndicators(.hidden)
            .defaultScrollAnchor(.center, for: .alignment)
            Text(progressText)
                .font(.footnote.monospacedDigit())
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
        .padding(.bottom, 8)
    }

    private func bead(_ g: Int) -> some View {
        let color = GlassPicture.color(model.offered[g].rgb, space: model.template.colorSpace)
        let isSelected = model.selected == g
        return Button {
            model.selected = g
        } label: {
            Circle()
                .fill(color)
                .overlay {
                    Circle().fill(RadialGradient(colors: [.white.opacity(0.55), .clear], center: UnitPoint(x: 0.32, y: 0.28),
                                                 startRadius: 0, endRadius: 16))
                }
                .overlay { Circle().strokeBorder(.white.opacity(isSelected ? 0.95 : 0.32), lineWidth: isSelected ? 3 : 1) }
                .shadow(color: color.opacity(0.6), radius: isSelected ? 10 : 4)
                .frame(width: 40, height: 40)
                .scaleEffect(isSelected ? 1.15 : 1)
                .animation(reduceMotion ? nil : .snappy, value: isSelected)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(model.name(of: g)))
        .accessibilityHint(Text(String(localized: "glass.bead.hint", defaultValue: "Pours this glass into the pieces you touch.",
                                       comment: "VoiceOver hint of a glass bead in the stained glass palette")))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("glass-bead-\(g)")
    }
}
#endif
