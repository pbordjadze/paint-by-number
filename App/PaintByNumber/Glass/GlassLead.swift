#if UNRELEASED
import CoreGraphics
import Observation
import PaintCore
import SwiftUI

/// Leading a window (painting-company row 366): the photo, dimmed, and the painter's finger
/// drawing the lead over it. Nothing snaps: a line stays as drawn, but an end stopping just short
/// of other lead or the frame is joined to it (PaintCore's `PenAssist`, as Edit's Pen joins), and
/// each piece a line closes lights up for a moment. Start makes the window
/// (`GlassWindow.Leading.window`, the photo's glasses its paints) and the shelf keeps it.
@MainActor
@Observable
final class GlassLeadModel {
    let photo: RGBAImage
    let picture: CGImage
    let width: Int
    let height: Int

    /// The lines laid, as joined, in canvas units.
    private(set) var lines: [[CGPoint]] = []
    /// Lines lifted but not laid yet, drawn as they were, so the lead never lags the finger.
    private(set) var pending: [(id: Int, line: [CGPoint])] = []
    private(set) var pieces = 1
    /// The pieces the last line closed, and when, for their flash.
    private(set) var flash: (paths: [CGPath], at: Date)?
    private(set) var isMaking = false
    @ObservationIgnored private var leading: GlassWindow.Leading?
    @ObservationIgnored private var queue: Task<Void, Never>?
    @ObservationIgnored private var nextID = 0
    /// Lines taken back before they were laid: their work is skipped, or its result dropped.
    @ObservationIgnored private var withdrawn: Set<Int> = []

    init(photo: RGBAImage, picture: CGImage) {
        self.photo = photo
        self.picture = picture
        let size = GenerationSettings().workingSize(sourceWidth: photo.width, sourceHeight: photo.height)
        width = size.width
        height = size.height
    }

    var waiting: [[CGPoint]] { pending.map(\.line) }
    var canUndo: Bool { !lines.isEmpty || !pending.isEmpty }

    /// Lays `line` (canvas units), its ends joined within `reach`.
    func add(_ line: [CGPoint], reach: CGFloat) {
        guard line.count >= 2 else { return }
        let id = nextID
        nextID += 1
        pending.append((id, line))
        enqueue(id: id) { [photo, width, height] current in
            var leading = try current ?? GlassWindow.Leading(photo: photo, width: width, height: height, colorSpace: photo.colorSpace)
            let added = leading.add(line.map { SIMD2(Float($0.x), Float($0.y)) }, joining: Float(reach))
            return (leading, added.closed)
        }
    }

    /// Takes the last line back: one not laid yet is withdrawn; a laid one is taken up, the window
    /// leaded again from the lines before it.
    func undo() {
        if let last = pending.popLast() {
            withdrawn.insert(last.id)
            return
        }
        guard !lines.isEmpty else { return }
        enqueue(id: nil) { [photo, width, height] current in
            guard let leading = current, !leading.lines.isEmpty else { return (current, []) }
            var again = try GlassWindow.Leading(photo: photo, width: width, height: height, colorSpace: photo.colorSpace)
            for line in leading.lines.dropLast() { again.add(line) }
            return (again, [])
        }
    }

    /// The window, once every line is laid.
    func make() async -> GlassWindow.Leaded? {
        isMaking = true
        defer { isMaking = false }
        await queue?.value
        let leading = self.leading
        let photo = photo, width = width, height = height
        return await Background.run {
            (try? leading ?? GlassWindow.Leading(photo: photo, width: width, height: height, colorSpace: photo.colorSpace))?.window()
        }
    }

    /// Runs `work` on the window after the work before it, off the main actor. `id` is the line
    /// it lays, if any: withdrawn, the work is skipped or its result dropped.
    private func enqueue(
        id: Int?,
        _ work: @escaping @Sendable (GlassWindow.Leading?) throws -> (GlassWindow.Leading?, [Int])
    ) {
        let previous = queue
        queue = Task {
            await previous?.value
            defer {
                if let id {
                    pending.removeAll { $0.id == id }
                    withdrawn.remove(id)
                }
            }
            if let id, withdrawn.contains(id) { return }
            let leading = self.leading
            let result = try? await Background.run { try work(leading) }
            if let id, withdrawn.contains(id) { return }
            guard let result, let laid = result.0 else { return }
            self.leading = laid
            lines = laid.lines.map { $0.map { CGPoint(x: CGFloat($0.x), y: CGFloat($0.y)) } }
            pieces = laid.template.regions.count
            if !result.1.isEmpty {
                let at = Date.now
                flash = (result.1.map { GlassPicture.piecePath(of: laid.template, region: $0) }, at)
                Task {
                    try? await Task.sleep(for: .seconds(GlassLeadView.flashDuration))
                    if flash?.at == at { flash = nil }
                }
            }
        }
    }
}

struct GlassLeadView: View {
    @State var model: GlassLeadModel
    let onStart: (GlassWindow.Leaded) -> Void
    let onCancel: () -> Void

    @State private var drawing: [CGPoint] = []
    @State private var showsPhoto = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// How far an end may stop short of the lead and still be joined, on screen (Edit's Pen's
    /// `snapReach`, a little more for a finger on a photo).
    static let reach: CGFloat = 12
    static let flashDuration: TimeInterval = 0.7

    var body: some View {
        GeometryReader { proxy in
            let fit = GlassFit(width: model.width, height: model.height, in: proxy.size, margin: 16)
            ZStack {
                GlassPicture.color(GlassPicture.nave, space: .sRGB).ignoresSafeArea()
                if showsPhoto {
                    Image(decorative: model.picture, scale: 1)
                        .resizable()
                        .frame(width: fit.rect.width, height: fit.rect.height)
                        .position(x: fit.rect.midX, y: fit.rect.midY)
                        .opacity(0.72)
                        .accessibilityHidden(true)
                }
                let stroke = drawing
                TimelineView(.animation(paused: model.flash == nil || reduceMotion)) { context in
                    Canvas { graphics, _ in
                        draw(in: &graphics, fit: fit, stroke: stroke, now: context.date)
                    }
                }
                .accessibilityElement()
                .accessibilityLabel(Text("Window"))
                .accessibilityValue(Text(piecesText))
                .accessibilityHint(Text("Draw the lead over your photo. Every shape you close becomes a piece of glass."))
                .gesture(lead(fit: fit))
                if model.lines.isEmpty && model.waiting.isEmpty && drawing.isEmpty {
                    Text("Draw the lead over your photo. Every shape you close becomes a piece of glass.")
                        .font(.callout)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .glassEffect(.regular, in: .rect(cornerRadius: 18))
                        .padding(24)
                        .frame(maxWidth: 420)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
        }
        .navigationTitle(Text("Draw the Lead"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", action: onCancel)
                    .accessibilityIdentifier("glass-lead-cancel")
            }
            ToolbarItemGroup(placement: .bottomBar) {
                Button("Undo", systemImage: "arrow.uturn.backward") { model.undo() }
                    .disabled(!model.canUndo)
                    .keyboardShortcut("z", modifiers: .command)
                    .accessibilityIdentifier("glass-lead-undo")
                Group {
                    if showsPhoto {
                        Button("Hide Photo", systemImage: "eye.slash") { showsPhoto = false }
                    } else {
                        Button("Show Photo", systemImage: "eye") { showsPhoto = true }
                    }
                }
                .accessibilityIdentifier("glass-lead-photo")
            }
            ToolbarSpacer(.flexible, placement: .bottomBar)
            ToolbarItem(placement: .bottomBar) {
                Text(piecesText)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
                    .accessibilityHidden(true)
            }
            .sharedBackgroundVisibility(.hidden)
            ToolbarSpacer(.flexible, placement: .bottomBar)
            ToolbarItem(placement: .bottomBar) {
                Button {
                    Task {
                        if let window = await model.make() { onStart(window) }
                    }
                } label: {
                    Text("Start")
                }
                .buttonStyle(.glassProminent)
                .tint(Theme.signature)
                .disabled(model.lines.isEmpty || model.isMaking)
                .accessibilityIdentifier("glass-lead-start")
            }
        }
        .onChange(of: model.pieces) { old, new in
            guard new > old else { return }
            AccessibilityNotification.Announcement(piecesText).post()
        }
    }

    private var piecesText: String {
        String(localized: "glass.pieces", defaultValue: "\(model.pieces) pieces",
               comment: "How many pieces of glass the lead drawn so far makes (plural)")
    }

    private func draw(in graphics: inout GraphicsContext, fit: GlassFit, stroke: [CGPoint], now: Date) {
        let toScreen = fit.transform
        let width = max(3, GlassPicture.leadWidth(width: model.width, height: model.height) * fit.scale)
        if let flash = model.flash, !reduceMotion {
            let t = now.timeIntervalSince(flash.at) / Self.flashDuration
            if t < 1 {
                let light = (1 - t) * (1 - t)
                for path in flash.paths {
                    graphics.fill(Path(path).applying(toScreen), with: .color(.white.opacity(0.55 * light)), style: FillStyle(eoFill: true))
                }
            }
        }
        var lead = Path(GlassPicture.leadPath(lines: model.lines + model.waiting, width: model.width, height: model.height))
            .applying(toScreen)
        if stroke.count >= 2 {
            var line = Path()
            line.addLines(stroke.map { $0.applying(toScreen) })
            lead.addPath(line)
        }
        let ink = GlassPicture.color(GlassPicture.lead, space: .sRGB)
        graphics.stroke(lead, with: .color(ink), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
    }

    private func lead(fit: GlassFit) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let p = fit.toCanvas(value.location)
                if drawing.last.map({ hypot($0.x - p.x, $0.y - p.y) * fit.scale >= 1.5 }) ?? true { drawing.append(p) }
            }
            .onEnded { _ in
                let line = drawing
                drawing = []
                let length = zip(line, line.dropFirst()).reduce(0) { $0 + hypot($1.1.x - $1.0.x, $1.1.y - $1.0.y) }
                guard length * fit.scale >= 8 else { return }
                model.add(line, reach: Self.reach / fit.scale)
            }
    }
}

/// A window fitted in a view: where its canvas lies, and the way between canvas units and points.
struct GlassFit {
    let rect: CGRect
    let scale: CGFloat

    init(width: Int, height: Int, in size: CGSize, margin: CGFloat) {
        let w = max(1, size.width - 2 * margin), h = max(1, size.height - 2 * margin)
        scale = min(w / CGFloat(max(width, 1)), h / CGFloat(max(height, 1)))
        let fitted = CGSize(width: CGFloat(width) * scale, height: CGFloat(height) * scale)
        rect = CGRect(x: (size.width - fitted.width) / 2, y: (size.height - fitted.height) / 2, width: fitted.width, height: fitted.height)
    }

    var transform: CGAffineTransform { CGAffineTransform(translationX: rect.minX, y: rect.minY).scaledBy(x: scale, y: scale) }

    func toCanvas(_ p: CGPoint) -> CGPoint { CGPoint(x: (p.x - rect.minX) / scale, y: (p.y - rect.minY) / scale) }
}
#endif
