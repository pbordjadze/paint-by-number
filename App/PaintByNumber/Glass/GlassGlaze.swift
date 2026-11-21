#if UNRELEASED
import CoreGraphics
import Metal
import Observation
import PaintCore
import SwiftUI
import UIKit
import os

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
    /// The glass in each piece. Not observed: a drag pours many a second, and the screen reads
    /// only how many are glazed (`glazedCount`).
    @ObservationIgnored private(set) var glazing: Glazing {
        didSet {
            let count = glazing.glazedCount
            if count != glazedCount { glazedCount = count }
        }
    }
    private(set) var glazedCount: Int
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
    /// A soft glass note per pour, pitched to its glass, as Settings' Sounds says.
    @ObservationIgnored private let sounds = SoundPlayer()
    @ObservationIgnored private var lastNote = Date.distantPast
    @ObservationIgnored var onChange: @MainActor (Glazing) -> Void = { _ in }

    init(id: UUID, template: Template, glazing: Glazing, offered: [PaletteColor], mode: GlassMode) {
        self.id = id
        self.template = template
        self.glazing = glazing
        glazedCount = glazing.glazedCount
        self.offered = offered
        self.mode = mode
        session = PaintingSession(template: template)
        // The bead in hand at first: the glass suggested for the largest piece left unglazed.
        let largest = template.regions.indices.filter { glazing.glass[$0] == Glazing.none }
            .max { template.regions[$0].area < template.regions[$1].area }
        selected = min(largest.map { Int(template.regions[$0].colorIndex) } ?? 0, max(0, offered.count - 1))
    }

    var pieces: Int { template.regions.count }
    var isComplete: Bool { glazedCount == pieces }

    /// The piece under `p` (canvas units), if any.
    func piece(at p: SIMD2<Float>) -> Int? {
        let x = Int(p.x.rounded(.down)), y = Int(p.y.rounded(.down))
        guard x >= 0, y >= 0, x < template.width, y < template.height else { return nil }
        let r = Int(template.regionMap[x, y])
        return r < pieces ? r : nil
    }

    /// A touch on the canvas: a tap pours into one piece, a stroke into each it crosses.
    @discardableResult
    func canvas(_ canvas: CanvasView, touched point: SIMD2<Float>, phase: CanvasTouchPhase) -> Bool {
        if phase == .tap || phase == .began {
            touchShowedBeads = beadsHidden
            if beadsHidden { beadsAsked += 1 }
        }
        var poured = false
        if !touchShowedBeads, phase != .ended, let r = piece(at: point) {
            poured = glaze(r, from: point, animated: true)
        }
        if phase == .tap || phase == .ended {
            touchShowedBeads = false
            endStroke()
        }
        return poured
    }

    /// Pours the bead in hand into piece `r` from `p` (none: VoiceOver's activation, a stroke of
    /// its own).
    @discardableResult
    func glaze(_ r: Int, from p: SIMD2<Float>? = nil, animated: Bool) -> Bool {
        let glass = Int16(selected)
        guard r < pieces, selected < offered.count, glazing.glass[r] != glass else { return false }
        let wasComplete = isComplete
        let before = glazing.glass[r]
        if stroke == nil { stroke = [] }
        stroke?.append((r, before))
        glazing.glass[r] = glass
        canvas?.showMode(r, value: GlassMode.code(glass: Int(glass), replacing: Self.glass(before)), painted: true,
                         from: p, animated: animated)
        ring(glass: Int(glass), poured: animated)
        if isComplete && !wasComplete { finished() }
        if p == nil { endStroke() }
        changed()
        return true
    }

    /// The glass's note, at most one a stroke's tenth of a second, so a drag rings, never rattles.
    private func ring(glass: Int, poured: Bool) {
        guard poured, UserDefaults.standard.object(forKey: SettingsKey.sounds) as? Bool ?? SettingsDefault.sounds,
              Date.now.timeIntervalSince(lastNote) > 0.1 else { return }
        lastNote = .now
        sounds.glass(index: SoundPlayer.glassNote(lightness: offered[glass].oklab.x), velocity: 0.7)
    }

    /// The window's screen came or went: the sounds get ready, or rest.
    func soundsReady(_ ready: Bool) {
        if ready { sounds.prepare(sky: .moon) } else { sounds.rest() }
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
            mode.sun(at: 0, passes: false, hour: nil)
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
        mode.sun(at: canvas?.canvasTime ?? 0, held: sunHold, passes: !reduceMotion, hour: Self.hour())
    }

    /// Every glazed piece shown on a canvas just made, as it stands.
    private func showAll() {
        guard let canvas else { return }
        for r in 0..<pieces {
            guard let glass = Self.glass(glazing.glass[r]) else { continue }
            canvas.showMode(r, value: GlassMode.code(glass: glass, replacing: nil), painted: true, from: nil, animated: false)
        }
        if finishedAt != nil {
            mode.sun(at: canvas.canvasTime, held: sunHold, passes: !reduceMotion, hour: Self.hour())
        } else if isComplete {
            // A window opened whole stands in the hour's light, with no sun passing.
            mode.sun(at: canvas.canvasTime, passes: false, hour: Self.hour())
        }
    }

    /// A whole window back in front stands in the light of the hour it is now, not the one it
    /// was left in.
    func refreshLight() {
        guard isComplete, sunHold == nil, let canvas, !mode.isAnimating(at: canvas.canvasTime) else { return }
        mode.sun(at: canvas.canvasTime, passes: false, hour: Self.hour())
        canvas.requestRender()
    }

    /// The hour now on the device's clock, 0…24.
    static func hour(_ date: Date = .now) -> Float {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return Float(c.hour ?? 12) + Float(c.minute ?? 0) / 60
    }

    /// The window as it stands, lit where it is glazed, drawn as the canvas draws it, as a PNG
    /// named `title` to share (Paul's pick: a lit picture now; printing waits for the build book).
    func sharedPicture(title: String) async throws -> URL {
        let (template, glazing, count, mode) = (template, glazing, offered.count, mode)
        return try await Background.run {
            guard let image = Self.picture(template: template, glazing: glazing, offered: count, mode: mode,
                                           longSide: ArtworkExporter.imagePixelSize),
                  let png = ImageCodec.pngData(image)
            else { throw CocoaError(.fileWriteUnknown) }
            return try ArtworkExporter.temporaryFile(png, name: ArtworkExporter.fileName(title), pathExtension: "png")
        }
    }

    /// The window in `mode` with the glasses `glazing` holds, `longSide` pixels on its long side.
    nonisolated static func picture(template: Template, glazing: Glazing, offered count: Int, mode: GlassMode,
                                    longSide: Int) -> CGImage? {
        guard let context = RenderContext.shared, let scene = CanvasScene(template: template, context: context) else { return nil }
        let states = template.regions.indices.map { r -> RegionState in
            let g = r < glazing.glass.count ? Int(glazing.glass[r]) : -1
            guard g >= 0, g < count else { return .settled(painted: false) }
            var state = RegionState.settled(painted: true)
            state.mode = GlassMode.code(glass: g, replacing: nil)
            return state
        }
        let size = CanvasSnapshot.fittedSize(for: template, longSide: longSide)
        let w = Int(size.width), h = Int(size.height)
        let nave = CanvasColor.linearP3(sRGB: GlassPicture.nave)
        return CanvasSnapshot.image(
            scene: scene, states: states, uniforms: CanvasSnapshot.uniforms(scene: scene, width: w, height: h, options: .painting),
            content: RenderContext.Content(
                outlines: false, numbers: false,
                clear: MTLClearColor(red: Double(nave.x), green: Double(nave.y), blue: Double(nave.z), alpha: 1), mode: mode),
            width: w, height: h, context: context)
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

    func canvas(_ canvas: CanvasView, speak region: Int) -> (label: String, value: String) {
        let glass = region < glazing.glass.count ? Int(glazing.glass[region]) : -1
        return (String(localized: "glass.piece", defaultValue: "Piece \(region + 1)",
                       comment: "VoiceOver name of one piece of a stained glass window, by its number"),
                glass >= 0 && glass < offered.count ? name(of: glass) : String(
                    localized: "glass.unglazed", defaultValue: "Unglazed",
                    comment: "VoiceOver value of a piece of stained glass with no glass in it yet"))
    }

    func canvasSummary(_ canvas: CanvasView) -> (label: String, value: String) {
        (String(localized: "Window"), progressText)
    }

    var progressText: String {
        String(localized: "glass.progress", defaultValue: "Glazed: \(glazedCount) of \(pieces)",
               comment: "VoiceOver value of a stained glass window: pieces glazed of all its pieces")
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
    /// The lit picture being shared, while the share sheet is up.
    @State private var sharedFile: URL?
    @State private var isSharing = false
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver

    let title: String

    init(model: GlassGlazeModel, title: String) {
        _model = State(initialValue: model)
        self.title = title
        _showsBeads = State(initialValue: !model.isComplete)
    }

    var body: some View {
        VStack(spacing: 0) {
            // The canvas offers each piece in view to VoiceOver (`GlassGlazeModel`'s `CanvasTouches`).
            GlassCanvas(model: model)
            if showsBeads || voiceOver {
                beads.transition(.opacity)
            }
        }
        .background(GlassPicture.color(GlassPicture.nave, space: .sRGB).ignoresSafeArea())
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Share", systemImage: "square.and.arrow.up", action: share)
                    .disabled(isSharing || model.glazedCount == 0)
                    .accessibilityIdentifier("glass-share")
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Undo", systemImage: "arrow.uturn.backward") { model.undo() }
                    .disabled(!model.canUndo)
                    .keyboardShortcut("z", modifiers: .command)
                    .accessibilityIdentifier("glass-undo")
            }
        }
        .background {
            ActivityShareSheet(item: sharedFile) {
                if let sharedFile { ArtworkExporter.removeExport(at: sharedFile) }
                sharedFile = nil
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
        .onAppear {
            model.beadsHidden = !showsBeads
            model.soundsReady(true)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { model.refreshLight() } else { model.flush() }
        }
        .onDisappear {
            model.flush()
            model.soundsReady(false)
        }
    }

    private func share() {
        isSharing = true
        Task {
            defer { isSharing = false }
            do {
                sharedFile = try await model.sharedPicture(title: title)
            } catch {
                Log.library.error("Couldn't share a window: \(String(describing: error), privacy: .public)")
            }
        }
    }

    private func setBeads(shown: Bool, duration: TimeInterval) {
        model.beadsHidden = !shown
        withAnimation(reduceMotion ? nil : .easeInOut(duration: duration)) { showsBeads = shown }
    }

    private var progressText: String { model.progressText }

    // MARK: Beads

    private var beads: some View {
        VStack(spacing: 6) {
            // Its own view: a pour changes the count below, never the beads.
            GlassBeads(model: model)
            Text(progressText)
                .font(.footnote.monospacedDigit())
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
        .padding(.bottom, 8)
    }
}

/// The glasses, one bead each: the window's own, a breath, then the glazier's classics. Reads
/// only the bead in hand.
private struct GlassBeads: View {
    let model: GlassGlazeModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
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
