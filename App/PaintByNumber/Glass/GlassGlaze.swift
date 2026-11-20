#if UNRELEASED
import CoreGraphics
import Observation
import PaintCore
import SwiftUI

/// Glazing a window (painting-company row 366; Paul's free glazing, November 20, 2026): the room
/// dark, the window's glass unlit, each piece keeping a faint tint of the glass the photo
/// suggests, and below it the glasses as beads, the window's own then the glazier's classics
/// (`GlassPalette.offered`). Any glass goes in any piece: a touch, or a drag across pieces, pours
/// the bead's glass in from the finger, lit. Glazed whole, the sun passes behind the window once.
@MainActor
@Observable
final class GlassGlazeModel {
    struct Pour: Equatable {
        var region: Int
        var from: SIMD3<Float>
        var point: CGPoint
        var at: Date
    }

    let id: UUID
    let template: Template
    let offered: [PaletteColor]
    @ObservationIgnored let paths: [CGPath]
    @ObservationIgnored let lead: CGPath
    private(set) var glazing: Glazing
    /// Each piece's color as it stands: its glass, or unlit.
    private(set) var colors: [SIMD3<Float>]
    /// The bead in hand: a place in `offered`.
    var selected = 0
    private(set) var pours: [Pour] = []
    /// When the window was glazed whole on screen, for the sun's pass.
    private(set) var finishedAt: Date?
    @ObservationIgnored private var undoStack: [[(region: Int, glass: Int16)]] = []
    @ObservationIgnored private var stroke: [(region: Int, glass: Int16)]?
    @ObservationIgnored private var saving: Task<Void, Never>?
    private(set) var canUndo = false
    @ObservationIgnored var onChange: (Glazing) -> Void = { _ in }

    static let pourDuration: TimeInterval = 0.45
    static let sunDuration: TimeInterval = 2.6

    init(id: UUID, template: Template, glazing: Glazing, offered: [PaletteColor]) {
        self.id = id
        self.template = template
        self.glazing = glazing
        self.offered = offered
        paths = GlassPicture.piecePaths(of: template)
        lead = GlassPicture.leadPath(of: template)
        colors = GlassPicture.colors(of: template, glazing: glazing, offered: offered)
        // The bead in hand at first: the glass suggested for the largest piece left unglazed.
        let largest = template.regions.indices.filter { glazing.glass[$0] == Glazing.none }
            .max { template.regions[$0].area < template.regions[$1].area }
        selected = largest.map { Int(template.regions[$0].colorIndex) } ?? 0
    }

    var pieces: Int { template.regions.count }
    var glazedCount: Int { glazing.glazedCount }
    var isComplete: Bool { glazedCount == pieces }

    /// The piece under `p` (canvas units), if any.
    func piece(at p: CGPoint) -> Int? {
        let x = Int(p.x), y = Int(p.y)
        guard x >= 0, y >= 0, x < template.width, y < template.height else { return nil }
        let r = Int(template.regionMap[x, y])
        return r < pieces ? r : nil
    }

    /// Pours the bead in hand into the piece under `p`: part of the stroke under way.
    func pour(at p: CGPoint, animated: Bool) {
        guard let r = piece(at: p) else { return }
        glaze(r, from: p, animated: animated)
    }

    /// Pours the bead in hand into piece `r` (VoiceOver's activation too, then a stroke of its own).
    func glaze(_ r: Int, from p: CGPoint? = nil, animated: Bool) {
        let glass = Int16(selected)
        guard r < pieces, glazing.glass[r] != glass else { return }
        let wasComplete = isComplete
        if stroke == nil { stroke = [] }
        stroke?.append((r, glazing.glass[r]))
        if animated {
            let point = p ?? template.labels(ofRegion: r).first.map { CGPoint($0.position) } ?? .zero
            let pour = Pour(region: r, from: colors[r], point: point, at: .now)
            pours.append(pour)
            Task {
                try? await Task.sleep(for: .seconds(Self.pourDuration))
                pours.removeAll { $0 == pour }
            }
        }
        glazing.glass[r] = glass
        colors[r] = offered[Int(glass)].rgb
        if isComplete && !wasComplete { finishedAt = .now }
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
            glazing.glass[step.region] = step.glass
        }
        colors = GlassPicture.colors(of: template, glazing: glazing, offered: offered)
        if !isComplete { finishedAt = nil }
        canUndo = !undoStack.isEmpty
        changed()
    }

    /// The window just finished, held at `elapsed` seconds of the sun's pass (demos).
    func finish(heldAt elapsed: TimeInterval) {
        finishedAt = Date.now.addingTimeInterval(-elapsed)
    }

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

struct GlassGlazeView: View {
    @State var model: GlassGlazeModel
    /// Where a demo holds the sun's pass (seconds into it).
    var sunHold: TimeInterval?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { proxy in
                let fit = GlassFit(width: model.template.width, height: model.template.height, in: proxy.size, margin: 28)
                TimelineView(.animation(paused: !isMoving)) { context in
                    Canvas { graphics, size in
                        draw(in: &graphics, size: size, fit: fit, now: context.date)
                    }
                }
                .gesture(glaze(fit: fit))
                .accessibilityElement(children: .contain)
                .accessibilityLabel(Text("Window"))
                .accessibilityValue(Text(progressText))
                .accessibilityChildren { pieceElements(fit: fit) }
            }
            beads
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
            guard complete else { return }
            AccessibilityNotification.Announcement(String(
                localized: "glass.finished", defaultValue: "The sun passes behind your window.",
                comment: "VoiceOver announcement when every piece of a stained glass window is glazed")).post()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { model.flush() }
        }
        .onDisappear { model.flush() }
    }

    private var isMoving: Bool {
        if !model.pours.isEmpty && !reduceMotion { return true }
        guard let at = model.finishedAt, !reduceMotion else { return false }
        return sunHold == nil && Date.now.timeIntervalSince(at) < GlassGlazeModel.sunDuration + 0.5
    }

    private var progressText: String {
        String(localized: "glass.progress", defaultValue: "Glazed: \(model.glazedCount) of \(model.pieces)",
               comment: "VoiceOver value of a stained glass window: pieces glazed of all its pieces")
    }

    // MARK: Drawing

    private func draw(in graphics: inout GraphicsContext, size: CGSize, fit: GlassFit, now: Date) {
        let space = model.template.colorSpace
        let toScreen = fit.transform
        let pieces = model.paths.map { Path($0).applying(toScreen) }
        let eo = FillStyle(eoFill: true)
        // Light spilling past the frame: the lit glass, blurred, behind the window.
        graphics.drawLayer { glow in
            glow.addFilter(.blur(radius: max(fit.rect.width, fit.rect.height) * 0.06))
            for (r, path) in pieces.enumerated() where model.glazing.glass[r] != Glazing.none {
                glow.fill(path, with: .color(GlassPicture.color(model.colors[r], space: space).opacity(0.55)), style: eo)
            }
        }
        let pouring = Dictionary(model.pours.map { ($0.region, $0) }, uniquingKeysWith: { _, last in last })
        for (r, path) in pieces.enumerated() {
            let lit = model.glazing.glass[r] != Glazing.none
            if let pour = pouring[r], !reduceMotion {
                let t = min(1, now.timeIntervalSince(pour.at) / GlassGlazeModel.pourDuration)
                graphics.fill(path, with: .color(GlassPicture.color(pour.from, space: space)), style: eo)
                let bounds = path.boundingRect
                let reach = hypot(bounds.width, bounds.height) * (1 - pow(1 - t, 3))
                let centre = pour.point.applying(toScreen)
                var poured = graphics
                poured.clip(to: path, style: eo)
                let disc = Path(ellipseIn: CGRect(x: centre.x - reach, y: centre.y - reach, width: 2 * reach, height: 2 * reach))
                poured.fill(disc, with: .color(GlassPicture.color(model.colors[r], space: space)))
                poured.fill(disc, with: .color(.white.opacity(0.45 * (1 - t))))
            } else {
                graphics.fill(path, with: .color(GlassPicture.color(model.colors[r], space: space)), style: eo)
            }
            if lit {
                // The glass itself: thicker and thinner across a piece, so it isn't paint.
                let b = path.boundingRect
                graphics.fill(path, with: .linearGradient(
                    Gradient(colors: [.white.opacity(0.16), .clear, .black.opacity(0.14)]),
                    startPoint: CGPoint(x: b.minX, y: b.minY), endPoint: CGPoint(x: b.maxX, y: b.maxY)), style: eo)
            }
        }
        // Light from behind, brightest a little above the middle.
        var light = graphics
        light.blendMode = .screen
        let centre = CGPoint(x: fit.rect.midX, y: fit.rect.minY + fit.rect.height * 0.4)
        light.fill(Path(fit.rect), with: .radialGradient(
            Gradient(colors: [Color(white: 1).opacity(0.14), .clear]), center: centre, startRadius: 0,
            endRadius: max(fit.rect.width, fit.rect.height) * 0.7))
        drawSun(in: &graphics, fit: fit, now: now)
        let width = max(3, GlassPicture.leadWidth(width: model.template.width, height: model.template.height) * fit.scale)
        let lead = Path(model.lead).applying(toScreen)
        graphics.stroke(lead, with: .color(GlassPicture.color(GlassPicture.lead, space: .sRGB)),
                        style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
        graphics.stroke(lead, with: .color(.white.opacity(0.14)),
                        style: StrokeStyle(lineWidth: max(1, width * 0.22), lineCap: .round, lineJoin: .round))
    }

    /// The sun passing behind the finished window: a band of light crossing it once, corner to
    /// corner.
    private func drawSun(in graphics: inout GraphicsContext, fit: GlassFit, now: Date) {
        guard let at = model.finishedAt, !reduceMotion else { return }
        let elapsed = sunHold ?? now.timeIntervalSince(at)
        let t = elapsed / GlassGlazeModel.sunDuration
        guard t > 0, t < 1 else { return }
        var sun = graphics
        sun.clip(to: Path(fit.rect))
        sun.blendMode = .plusLighter
        let rect = fit.rect, span = rect.width + rect.height
        let front = -rect.height + span * (t * 1.3 - 0.15)
        let band = rect.width * 0.35
        let start = CGPoint(x: rect.minX + front, y: rect.minY), end = CGPoint(x: rect.minX + front + band, y: rect.minY + band * 0.6)
        let strength = sin(.pi * t)
        sun.fill(Path(rect), with: .linearGradient(
            Gradient(stops: [
                .init(color: .clear, location: 0), .init(color: Color(red: 1, green: 0.95, blue: 0.8).opacity(0.5 * strength), location: 0.5),
                .init(color: .clear, location: 1),
            ]), startPoint: start, endPoint: end))
    }

    // MARK: Touch

    private func glaze(fit: GlassFit) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in model.pour(at: fit.toCanvas(value.location), animated: !reduceMotion) }
            .onEnded { _ in model.endStroke() }
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
                        bead(g)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
            .scrollIndicators(.hidden)
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
                .overlay { Circle().strokeBorder(.white.opacity(isSelected ? 0.95 : 0.2), lineWidth: isSelected ? 3 : 1) }
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
