#if UNRELEASED
import CoreGraphics
import Observation
import PaintCore
import SwiftUI
import os

/// Leading a window (painting-company row 366): the photo, dimmed, with the lead it suggests
/// (`GlassLeadSuggestion`, Paul's pick: a suggested lead you can edit) over it, and the painter's
/// finger drawing more or, with Erase, tapping a line away from junction to junction. Nothing
/// snaps: a line stays as drawn, but an end stopping just short of other lead or the frame is
/// joined to it (PaintCore's `PenAssist`, as Edit's Pen joins), and each piece a line closes
/// lights up for a moment. Start From offers the suggestion or a blank window. Start makes the
/// window (`GlassWindow.Leading.window`, the photo's glasses its paints) and the shelf keeps it.
@MainActor
@Observable
final class GlassLeadModel {
    let photo: RGBAImage
    let picture: CGImage
    let width: Int
    let height: Int

    /// Where the lead starts from.
    nonisolated enum Start: Hashable, Sendable { case suggested, blank }

    /// The lead as laid, in canvas units: the suggestion's lines and the painter's.
    private(set) var lead: [[CGPoint]] = [] {
        didSet { leadPath = GlassPicture.leadPath(lines: lead, width: width, height: height) }
    }
    /// The laid lead and the frame as one path, made once a change, never per drawn frame.
    @ObservationIgnored private(set) var leadPath = CGMutablePath() as CGPath
    /// Lines lifted but not laid yet, drawn as they were, so the lead never lags the finger.
    private(set) var pending: [(id: Int, line: [CGPoint])] = []
    private(set) var pieces = 1
    private(set) var start: Start
    /// The suggestion is being made.
    private(set) var isSuggesting = false
    /// The pieces the last line closed, and when, for their flash.
    private(set) var flash: (paths: [CGPath], at: Date)?
    private(set) var isMaking = false
    /// The window has a step of the painter's to take back.
    private var windowCanUndo = false
    var canUndo: Bool { windowCanUndo || !pending.isEmpty }
    @ObservationIgnored private var leading: GlassWindow.Leading?
    @ObservationIgnored private var queue: Task<Void, Never>?
    @ObservationIgnored private var nextID = 0
    /// Which `begin` is the latest, so only its end puts the spinner away.
    @ObservationIgnored private var beginning = 0
    /// Lines taken back before they were laid: their work is skipped, or its result dropped.
    @ObservationIgnored private var withdrawn: Set<Int> = []

    init(photo: RGBAImage, picture: CGImage, start: Start = .suggested) {
        self.photo = photo
        self.picture = picture
        let size = GenerationSettings().workingSize(sourceWidth: photo.width, sourceHeight: photo.height)
        width = size.width
        height = size.height
        self.start = start
        begin(start)
    }

    var waiting: [[CGPoint]] { pending.map(\.line) }
    var hasLead: Bool { !lead.isEmpty || !pending.isEmpty }

    /// Starts the lead over: the photo's suggestion, or no lead at all.
    func begin(_ start: Start) {
        self.start = start
        for line in pending { withdrawn.insert(line.id) }
        pending = []
        pieces = 1
        lead = []
        beginning += 1
        let beginning = beginning
        isSuggesting = start == .suggested
        enqueue(id: nil) { [photo, width, height] _ in
            let blank = { try GlassWindow.Leading(photo: photo, width: width, height: height, colorSpace: photo.colorSpace) }
            guard start == .suggested else { return (try blank(), []) }
            do {
                return (try GlassWindow.Leading.suggested(
                    photo: photo, width: width, height: height, colorSpace: photo.colorSpace, cancel: .task), [])
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // No suggestion: the painter leads a blank window rather than one that takes no lead.
                Log.library.error("No suggested lead: \(String(describing: error), privacy: .public)")
                return (try blank(), [])
            }
        } then: { [weak self] in
            if self?.beginning == beginning { self?.isSuggesting = false }
        }
    }

    /// The screen went: the work still queued (a suggestion being made) stops.
    func stop() { queue?.cancel() }

    /// Lays `line` (canvas units), its ends joined within `reach`.
    func add(_ line: [CGPoint], reach: CGFloat) {
        guard line.count >= 2 else { return }
        let id = nextID
        nextID += 1
        pending.append((id, line))
        enqueue(id: id) { current in
            guard var leading = current else { return (nil, []) }
            let added = leading.add(line.map { SIMD2(Float($0.x), Float($0.y)) }, joining: Float(reach))
            return (leading, added.closed)
        }
    }

    /// Takes away the lead under `point` (canvas units), junction to junction, within `reach`.
    func erase(at point: CGPoint, reach: CGFloat) {
        enqueue(id: nil) { current in
            guard var leading = current, leading.erase(at: SIMD2(Float(point.x), Float(point.y)), reach: Float(reach))
            else { return (nil, []) }
            return (leading, [])
        }
    }

    /// Takes the last step back: a line not laid yet is withdrawn; a laid line or an erase is
    /// taken back on the window. The suggestion stays: Start From takes it away.
    func undo() {
        if let last = pending.popLast() {
            withdrawn.insert(last.id)
            return
        }
        enqueue(id: nil) { current in
            guard var leading = current, leading.canUndo else { return (nil, []) }
            try leading.undo()
            return (leading, [])
        }
    }

    /// The window, once every line is laid.
    func make() async -> GlassWindow.Leaded? {
        isMaking = true
        defer { isMaking = false }
        await queue?.value
        guard let leading else { return nil }
        return await Background.run { leading.window() }
    }

    /// Runs `work` on the window after the work before it, off the main actor; a nil window from
    /// it changes nothing. `id` is the line it lays, if any: withdrawn, the work is skipped or its
    /// result dropped.
    private func enqueue(
        id: Int?,
        _ work: @escaping @Sendable (GlassWindow.Leading?) throws -> (GlassWindow.Leading?, [Int]),
        then: (@MainActor () -> Void)? = nil
    ) {
        let previous = queue
        queue = Task {
            await previous?.value
            defer {
                if let id {
                    pending.removeAll { $0.id == id }
                    withdrawn.remove(id)
                }
                then?()
            }
            if let id, withdrawn.contains(id) { return }
            let leading = self.leading
            let result = try? await Background.run { () -> (GlassWindow.Leading, [[CGPoint]], [Int])? in
                let (laid, closed) = try work(leading)
                guard let laid else { return nil }
                return (laid, laid.lead.map { $0.map { CGPoint(x: CGFloat($0.x), y: CGFloat($0.y)) } }, closed)
            }
            if let id, withdrawn.contains(id) { return }
            guard let result else { return }
            let (laid, lead, closed) = result
            self.leading = laid
            self.lead = lead
            pieces = laid.template.regions.count
            windowCanUndo = laid.canUndo
            if !closed.isEmpty {
                let at = Date.now
                flash = (closed.map { GlassPicture.piecePath(of: laid.template, region: $0) }, at)
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
    /// A tap takes lead away instead of a finger drawing it.
    @State private var erasing = false
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
                .accessibilityHint(erasing ? Text("Tap a line of lead to take it away.")
                                   : Text("Draw the lead over your photo. Every shape you close becomes a piece of glass."))
                .gesture(lead(fit: fit))
                if model.isSuggesting {
                    ProgressView()
                        .controlSize(.large)
                        .accessibilityLabel(Text("Suggesting lead"))
                } else if !model.hasLead && drawing.isEmpty {
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
            // Until the painter changes the lead, as Edit's Start From: after, a start over would
            // take what they did with no way back.
            if !model.canUndo {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Picker(selection: Binding(get: { model.start }, set: { if $0 != model.start { model.begin($0) } })) {
                            Text("Suggested Lead").tag(GlassLeadModel.Start.suggested)
                            Text("Blank").tag(GlassLeadModel.Start.blank)
                        } label: {
                            Text("Start From")
                        }
                    } label: {
                        SwiftUI.Label("Start From", systemImage: "square.on.square.dashed")
                    }
                    .accessibilityIdentifier("glass-lead-start-from")
            }
            }
            ToolbarItemGroup(placement: .bottomBar) {
                Button("Undo", systemImage: "arrow.uturn.backward") { model.undo() }
                    .disabled(!model.canUndo)
                    .keyboardShortcut("z", modifiers: .command)
                    .accessibilityIdentifier("glass-lead-undo")
                Toggle(isOn: $erasing) {
                    SwiftUI.Label("Erase", systemImage: "eraser")
                }
                .accessibilityHint(Text("Tap a line of lead to take it away."))
                .accessibilityIdentifier("glass-lead-erase")
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
                .disabled(model.pieces < 2 || model.isMaking || model.isSuggesting)
                .accessibilityIdentifier("glass-lead-start")
            }
        }
        .onDisappear { if !model.isMaking { model.stop() } }
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
        var lead = Path(model.leadPath).applying(toScreen)
        // The lines not laid yet and the finger's, few points, drawn as they are.
        for line in model.waiting + [stroke] where line.count >= 2 {
            var path = Path()
            path.addLines(line.map { $0.applying(toScreen) })
            lead.addPath(path)
        }
        let ink = GlassPicture.color(GlassPicture.lead, space: .sRGB)
        graphics.stroke(lead, with: .color(ink), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
    }

    private func lead(fit: GlassFit) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard !erasing else { return }
                let p = fit.toCanvas(value.location)
                if drawing.last.map({ hypot($0.x - p.x, $0.y - p.y) * fit.scale >= 1.5 }) ?? true { drawing.append(p) }
            }
            .onEnded { value in
                if erasing {
                    drawing = []
                    model.erase(at: fit.toCanvas(value.location), reach: Self.reach / fit.scale)
                    return
                }
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
