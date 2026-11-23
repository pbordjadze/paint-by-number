#if UNRELEASED
import CoreGraphics
import CoreMotion
import Metal
import Observation
import PaintCore
import QuartzCore
import SwiftUI
import UIKit
import os

/// Glazing a window (painting-company row 366; by number, Paul's pick of November 22, 2026): the
/// room dark, the window's pieces clear lenses over its photo, each numbered for the glass the
/// photo suggests, and below it those glasses as numbered beads. A drag from the leaded part
/// round bare pieces and back leads them (`GlassFraming`); a tap in a led piece of the bead's
/// number pours its glass from the finger, tinting its lens. Glazed whole, the sun passes behind
/// the window once.
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
    /// The bead in hand: a place in `offered`. Its pieces' numbers stand out, as a paint's do.
    var selected = 0 {
        didSet { selectNumbers() }
    }
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
    /// A piece as it was before a step changed it, for Undo.
    private struct Step {
        let region: Int
        let glass: Int16
        let framed: Bool
    }
    @ObservationIgnored private var undoStack: [[Step]] = []
    @ObservationIgnored private var stroke: [Step]?
    /// The lead being drawn (canvas units), and the layer that shows it under the finger.
    @ObservationIgnored private var leadStroke: [SIMD2<Float>]?
    @ObservationIgnored private var leadLayer: CAShapeLayer?
    /// Strokes lifted and being laid, in order.
    @ObservationIgnored private var laying: Task<Void, Never>?
    /// How many pieces the painter has framed (the hidden ones aside): none yet, and the screen
    /// says how.
    private(set) var framedByHand = 0
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
        let hidden = Self.hidden(in: template)
        self.hidden = hidden
        framedByHand = template.regions.indices.filter { glazing.isFramed($0) && !hidden.contains($0) }.count
        // The bead in hand at first: the glass suggested for the largest piece left unglazed.
        let largest = template.regions.indices.filter { glazing.glass[$0] == Glazing.none }
            .max { template.regions[$0].area < template.regions[$1].area }
        selected = min(largest.map { Int(template.regions[$0].colorIndex) } ?? 0, max(0, offered.count - 1))
        selectNumbers()
    }

    /// The canvas emphasizes the numbers of the bead in hand: one of the window's own glasses,
    /// whose number is its place (a classic has no pieces of its own).
    private func selectNumbers() {
        session.select(color: selected < template.palette.count ? selected : nil)
    }

    var pieces: Int { template.regions.count }
    var isComplete: Bool { glazedCount == pieces }

    /// The pieces the lead covers whole: no wider than the lead, so no touch can find one and
    /// no eye sees it (a line drawn close beside another leaves one where they meet). Each takes
    /// the glass suggested for it as the window opens (`glazeHidden`), so a window is never left
    /// an invisible piece short of finished, nor its number shown on the lead.
    @ObservationIgnored let hidden: [Int]

    nonisolated static func hidden(in template: Template) -> [Int] {
        let half = Float(GlassPicture.leadWidth(width: template.width, height: template.height)) / 2
        return template.regions.indices.filter { r in (template.labels(ofRegion: r).map(\.radius).max() ?? 0) < half }
    }

    /// Glazes the hidden pieces still empty, for good (Undo never takes them back).
    private func glazeHidden() {
        for r in hidden where glazing.glass[r] == Glazing.none {
            let glass = Int16(min(Int(template.regions[r].colorIndex), max(0, offered.count - 1)))
            glazing.glass[r] = glass
            glazing.framed[r] = true
            canvas?.showMode(r, value: GlassMode.code(glass: Int(glass), replacing: nil), painted: true, from: nil, animated: false)
        }
    }

    /// The piece under `p` (canvas units), if any.
    func piece(at p: SIMD2<Float>) -> Int? {
        let x = Int(p.x.rounded(.down)), y = Int(p.y.rounded(.down))
        guard x >= 0, y >= 0, x < template.width, y < template.height else { return nil }
        let r = Int(template.regionMap[x, y])
        return r < pieces ? r : nil
    }

    /// A touch on the canvas (Paul's interface, November 22, 2026): a stroke draws lead, and one
    /// from the leaded part round bare pieces and back frames them (`GlassFraming`); a tap in a
    /// framed piece pours its glass. With VoiceOver, activating a piece frames it and pours.
    @discardableResult
    func canvas(_ canvas: CanvasView, touched point: SIMD2<Float>, phase: CanvasTouchPhase) -> Bool {
        if phase == .tap || phase == .began {
            touchShowedBeads = beadsHidden
            if beadsHidden { beadsAsked += 1 }
        }
        defer { if phase == .tap || phase == .ended { touchShowedBeads = false } }
        guard !touchShowedBeads else { return false }
        switch phase {
        case .tap:
            guard let r = piece(at: point) else { return false }
            if !glazing.isFramed(r) && UIAccessibility.isVoiceOverRunning { frame([r]) }
            let poured = glazing.isFramed(r) && glaze(r, from: point, animated: true)
            endStroke()
            return poured
        case .began:
            leadStroke = [point]
        case .moved:
            leadStroke?.append(point)
        case .ended:
            leadStroke?.append(point)
            if let stroke = leadStroke { lay(stroke) }
            leadStroke = nil
        }
        drawLead()
        return false
    }

    /// The lead under the finger, as wide as the lead it will be.
    private func drawLead() {
        guard let canvas else { return }
        let layer = leadLayer ?? {
            let layer = CAShapeLayer()
            layer.fillColor = nil
            layer.strokeColor = UIColor(GlassPicture.color(GlassPicture.lead, space: .sRGB)).cgColor
            layer.lineCap = .round
            layer.lineJoin = .round
            layer.shadowColor = UIColor.white.cgColor
            layer.shadowOpacity = 0.35
            layer.shadowRadius = 1.5
            layer.shadowOffset = .zero
            canvas.layer.addSublayer(layer)
            leadLayer = layer
            return layer
        }()
        if layer.superlayer !== canvas.layer { canvas.layer.addSublayer(layer) }
        guard let stroke = leadStroke, let first = stroke.first else {
            layer.path = nil
            return
        }
        let path = CGMutablePath()
        path.move(to: canvas.viewPoint(forCanvas: first))
        for p in stroke.dropFirst() { path.addLine(to: canvas.viewPoint(forCanvas: p)) }
        let zoom = canvas.viewPoint(forCanvas: SIMD2(1, 0)).x - canvas.viewPoint(forCanvas: .zero).x
        layer.lineWidth = GlassPicture.leadWidth(width: template.width, height: template.height) * zoom
        layer.path = path
    }

    /// Frames the pieces a lifted stroke closes, after the strokes before it.
    private func lay(_ stroke: [SIMD2<Float>]) {
        let before = laying
        let template = template
        let reach = Float(GlassPicture.leadWidth(width: template.width, height: template.height)) * 0.6
        laying = Task {
            await before?.value
            let framed = template.regions.indices.map(glazing.isFramed)
            let closed = await Background.run {
                GlassFraming.framed(by: stroke, in: template, framed: framed, reach: reach)
            }
            frame(closed)
        }
    }

    /// Frames `regions`, one step for Undo.
    func frame(_ regions: [Int]) {
        let new = regions.filter { $0 < pieces && !glazing.isFramed($0) }
        guard !new.isEmpty else { return }
        endStroke()
        stroke = new.map { Step(region: $0, glass: glazing.glass[$0], framed: false) }
        for r in new {
            glazing.framed[r] = true
            canvas?.showMode(r, value: GlassMode.code(glass: nil, replacing: nil), painted: false, from: nil, animated: false)
        }
        framedByHand += new.filter { !hidden.contains($0) }.count
        endStroke()
        ring(glass: Int(template.regions[new[0]].colorIndex), poured: true)
        changed()
    }

    /// Pours the bead in hand into framed piece `r` from `p` (none: a stroke of its own).
    @discardableResult
    func glaze(_ r: Int, from p: SIMD2<Float>? = nil, animated: Bool) -> Bool {
        let glass = Int16(selected)
        // By number (Paul's pick, November 22, 2026): a piece takes only its own number's glass.
        guard r < pieces, selected < offered.count, glazing.glass[r] != glass, glazing.isFramed(r),
              Int(template.regions[r].colorIndex) == selected else { return false }
        let wasComplete = isComplete
        let before = glazing.glass[r]
        if stroke == nil { stroke = [] }
        stroke?.append(Step(region: r, glass: before, framed: glazing.framed[r]))
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
            if glazing.framed[step.region] && !step.framed && step.glass == now && !hidden.contains(step.region) { framedByHand -= 1 }
            glazing.glass[step.region] = step.glass
            glazing.framed[step.region] = step.framed
            let framed = glazing.isFramed(step.region)
            if let back = Self.glass(step.glass) {
                canvas?.showMode(step.region, value: GlassMode.code(glass: back, replacing: Self.glass(now)), painted: true,
                                 from: nil, animated: true)
            } else if step.glass != now {
                canvas?.showMode(step.region, value: GlassMode.code(glass: Self.glass(now), replacing: nil, framed: framed),
                                 painted: false, from: nil, animated: true)
            } else {
                canvas?.showMode(step.region, value: GlassMode.code(glass: nil, replacing: nil, framed: framed),
                                 painted: false, from: nil, animated: false)
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
        // A window saved before its hidden pieces glazed themselves (one left with only those
        // finishes as it opens).
        let glazed = glazedCount
        glazeHidden()
        if glazedCount != glazed { changed() }
        for r in 0..<pieces {
            if let glass = Self.glass(glazing.glass[r]) {
                canvas.showMode(r, value: GlassMode.code(glass: glass, replacing: nil), painted: true, from: nil, animated: false)
            } else if glazing.framed[r] {
                canvas.showMode(r, value: GlassMode.code(glass: nil, replacing: nil), painted: false, from: nil, animated: false)
            }
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
            guard g >= 0, g < count else {
                var state = RegionState.settled(painted: false)
                state.mode = GlassMode.code(glass: nil, replacing: nil, framed: r < glazing.framed.count && glazing.framed[r])
                return state
            }
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
        // A piece is named by the number of its glass, the one its bead carries, as the window shows.
        let number = region < template.regions.count ? Int(template.regions[region].colorIndex) + 1 : 0
        return (String(localized: "glass.piece.number", defaultValue: "Number \(number)",
                       comment: "VoiceOver name of one piece of a stained glass window: the number of the glass it takes"),
                glass >= 0 && glass < offered.count ? name(of: glass) : String(
                    localized: "glass.unglazed", defaultValue: "Unglazed",
                    comment: "VoiceOver value of a piece of stained glass with no glass in it yet"))
    }

    /// Lead is drawn with one finger, at once; two move the window.
    var strokesWithOneFinger: Bool { true }

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
    /// Whether the beads have melted into one bar of glass, as the window is glazed whole.
    @State private var melted = false
    /// The wait between the melt and the beads going, called off when they come back.
    @State private var melting: Task<Void, Never>?
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
            } else if model.isComplete {
                plaque
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
            melt(complete)
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
            melting?.cancel()
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

    /// Glazed whole, the beads melt into one bar of glass and then go; an undo brings them back
    /// apart. Reduce Motion lets them go at once.
    private func melt(_ complete: Bool) {
        guard complete, !reduceMotion else {
            melted = false
            setBeads(shown: !complete, duration: 0.6)
            return
        }
        withAnimation(.smooth(duration: 0.7)) { melted = true }
        melting?.cancel()
        melting = Task {
            try? await Task.sleep(for: .seconds(0.9))
            guard !Task.isCancelled, model.isComplete else { return }
            setBeads(shown: false, duration: 0.6)
        }
    }

    private func setBeads(shown: Bool, duration: TimeInterval) {
        if shown {
            melting?.cancel()
            melted = false
        }
        model.beadsHidden = !shown
        withAnimation(reduceMotion ? nil : .easeInOut(duration: duration)) { showsBeads = shown }
    }

    private var progressText: String { model.progressText }

    /// The finished window's name on a plaque of glass, come out of the glass the beads melted
    /// into; a touch on the window brings the beads back.
    private var plaque: some View {
        GlassEffectContainer {
            VStack(spacing: 2) {
                Text(verbatim: title)
                    .font(.display(.headline))
                    .lineLimit(1)
                Text("Finished")
                    .font(.caption)
                    .foregroundStyle(GlassEra.gold)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 10)
            .glassEffect(.regular.tint(GlassEra.gold.opacity(0.14)), in: .capsule)
            .glassEffectTransition(reduceMotion ? .identity : .materialize)
        }
        .padding(.vertical, 14)
        .accessibilityElement(children: .combine)
    }

    // MARK: Beads

    private var beads: some View {
        VStack(spacing: 6) {
            // Its own view: a pour changes the count below, never the beads.
            GlassBeads(model: model, melted: melted)
            if model.framedByHand == 0 {
                // How a window is led in, until the painter has framed a first piece.
                Text(String(localized: "glass.lead.howTo",
                            defaultValue: "Draw lead from the edge round a few pieces and back, then tap inside to pour.",
                            comment: "Stained Glass: how to frame pieces by drawing lead and then pour glass, shown under the glass beads until the first pieces are framed"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .glassEffect(.regular, in: .capsule)
                    .padding(.horizontal, 20)
            } else {
                Text(progressText)
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .glassEffect(.regular, in: .capsule)
                    .accessibilityHidden(true)
            }
        }
        .padding(.bottom, 8)
    }
}

/// The window's glasses, one numbered bead each, of real Liquid Glass (painting-company row 366):
/// each bead a drop of its glass in one `GlassEffectContainer`, so the bead in hand swells and
/// its neighbours lean into it as glass does, a glint inside each that follows the device's tilt
/// (`GlassTilt`), and, as the window is glazed whole, every bead melting into one bar of glass
/// before it goes (`melted`). Reads only the bead in hand.
private struct GlassBeads: View {
    let model: GlassGlazeModel
    let melted: Bool
    @Namespace private var drops
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView(.horizontal) {
            GlassEffectContainer(spacing: melted ? 48 : 16) {
                HStack(spacing: melted ? 2 : 14) {
                    // The window's own glasses, one a number (by number, the glazier's classics,
                    // which no piece is numbered for, stay in the box).
                    ForEach(0..<min(model.template.palette.count, model.offered.count), id: \.self) { g in
                        bead(g)
                    }
                }
                .frame(height: 60)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 6)
        }
        .scrollIndicators(.hidden)
        .defaultScrollAnchor(.center, for: .alignment)
        .onAppear { GlassTilt.shared.start() }
        .onDisappear { GlassTilt.shared.stop() }
    }

    private func bead(_ g: Int) -> some View {
        let color = GlassPicture.color(model.offered[g].rgb, space: model.template.colorSpace)
        let isSelected = model.selected == g
        let side: CGFloat = isSelected && !melted ? 54 : 40
        return Button {
            model.selected = g
        } label: {
            Text(g + 1, format: .number)
                .font(.system(.footnote, design: .serif, weight: .bold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.7), radius: 1.5)
                .dynamicTypeSize(...DynamicTypeSize.xLarge)
                .frame(width: side, height: side)
                .background { GlassGlint(still: reduceMotion) }
                .clipShape(Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.tint(color.opacity(isSelected ? 0.9 : 0.65)).interactive(), in: .circle)
        .glassEffectID(g, in: drops)
        .glassEffectUnion(id: melted ? -1 : g, namespace: drops)
        .animation(reduceMotion ? nil : .bouncy(duration: 0.35), value: isSelected)
        .accessibilityLabel(Text(model.name(of: g)))
        .accessibilityHint(Text(String(localized: "glass.bead.hint", defaultValue: "Pours this glass into the pieces you touch.",
                                       comment: "VoiceOver hint of a glass bead in the stained glass palette")))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("glass-bead-\(g)")
    }
}

/// The light caught inside a bead of glass: a soft spot of white where the window's light would
/// strike it, sliding round the bead as the device tilts (still under Reduce Motion, and on a
/// device without motion).
private struct GlassGlint: View {
    let still: Bool

    var body: some View {
        // One still frame where nothing tilts: no motion, or Reduce Motion.
        let moves = !still && GlassTilt.shared.isAvailable
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !moves)) { _ in
            let tilt = moves ? GlassTilt.shared.tilt : CGPoint.zero
            RadialGradient(colors: [.white.opacity(0.55), .white.opacity(0.08), .clear],
                           center: UnitPoint(x: 0.32 + 0.3 * tilt.x, y: 0.28 - 0.3 * tilt.y),
                           startRadius: 0, endRadius: 22)
                .blendMode(.plusLighter)
        }
        .accessibilityHidden(true)
    }
}

/// The device's tilt, for the glass that catches the light (Core Motion's gravity, read when a
/// glint draws: no handler runs off the main actor). Started while beads are on screen.
@MainActor
final class GlassTilt {
    static let shared = GlassTilt()
    private let motion = CMMotionManager()
    private var users = 0

    func start() {
        users += 1
        guard users == 1, motion.isDeviceMotionAvailable else { return }
        motion.deviceMotionUpdateInterval = 1 / 30
        motion.startDeviceMotionUpdates()
    }

    func stop() {
        users = max(0, users - 1)
        if users == 0 { motion.stopDeviceMotionUpdates() }
    }

    /// Whether the device reports its motion at all (no simulator does).
    var isAvailable: Bool { motion.isDeviceMotionAvailable }

    /// Gravity across the screen, each axis in -1...1: zero lying flat or with no motion.
    var tilt: CGPoint {
        guard let gravity = motion.deviceMotion?.gravity else { return .zero }
        return CGPoint(x: gravity.x, y: gravity.y)
    }
}
#endif
