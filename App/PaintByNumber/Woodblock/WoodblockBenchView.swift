#if UNRELEASED
import CoreGraphics
import Observation
import PaintCore
import SwiftUI
import UIKit
import os

/// The bench (painting-company row 375): a print made block by block on the painting screen's
/// own canvas (`WoodblockCanvas`), in Woodblock's mode (`WoodblockMode`). For each block: carve
/// (the finger clears the wood around what stays, the tool sizing itself; most of it gone, the
/// rest is tidied), ink (the brush on what stands), the sheet (a tap drops it into the kentō),
/// rub (the baren, as many passes as the painter likes), peel (the sheet lifts from its corner,
/// its face on the flap), and the print so far, the right way round. The colour blocks show
/// their numbered areas (the kyōgō); the key block comes first, the bokashi last. One quiet line
/// says what the step asks, and one button does what a finger can't (lay, peel, the next block).
@MainActor
@Observable
final class WoodblockBenchModel: CanvasTouches {
    let id: UUID
    let plan: WoodblockPlan
    @ObservationIgnored let mode: WoodblockMode
    @ObservationIgnored let session: PaintingSession
    @ObservationIgnored weak var canvas: CanvasView? {
        didSet { if canvas !== oldValue { showAll() } }
    }
    /// The bench's state. Not observed: a stroke changes it every touch sample; the screen reads
    /// `step`, `block` and `canPeel`.
    @ObservationIgnored private(set) var bench: WoodblockBench
    @ObservationIgnored private(set) var field: WoodblockField
    private(set) var step: WoodblockBench.Step
    private(set) var block: Int
    private(set) var canPeel = false
    /// The print shown the right way round, after a peel.
    private(set) var showsPrint = false
    /// A block's field is being made (between blocks).
    private(set) var isTurning = false
    @ObservationIgnored var reduceMotion = false
    @ObservationIgnored private var last: SIMD2<Float>?
    /// A stroke laid the sheet and hasn't lifted yet.
    @ObservationIgnored private var laidByStroke = false
    @ObservationIgnored private var saving: Task<Void, Never>?
    @ObservationIgnored private var lastBite = Date.distantPast
    @ObservationIgnored private let bite = UIImpactFeedbackGenerator(style: .light)
    @ObservationIgnored var onChange: @MainActor (WoodblockBench) -> Void = { _ in }

    init(id: UUID, plan: WoodblockPlan, bench: WoodblockBench, field: WoodblockField, mode: WoodblockMode) {
        self.id = id
        self.plan = plan
        self.bench = bench
        self.field = field
        self.mode = mode
        step = bench.step
        block = bench.block
        session = PaintingSession(template: plan.template)
        var byRegion = [Int](repeating: .max, count: plan.template.regions.count)
        for b in plan.blocks.indices {
            for r in byRegion.indices where byRegion[r] == .max && plan.prints(region: r, block: b) { byRegion[r] = b }
        }
        regionBlocks = byRegion
        showsPrint = bench.step == .peeled
    }

    var isDone: Bool { bench.isDone(in: plan) }
    var blocks: Int { plan.blocks.count }
    var current: WoodblockPlan.Block? { plan.blocks.indices.contains(block) ? plan.blocks[block] : nil }

    /// The field and the look of the block `b`, made off the main actor (the mode uploads its shape).
    nonisolated static func prepare(plan: WoodblockPlan, block b: Int, mode: WoodblockMode) -> WoodblockField {
        let field = WoodblockField(plan: plan, block: min(b, plan.blocks.count - 1))
        let space = plan.template.colorSpace
        let blk = plan.blocks[min(b, plan.blocks.count - 1)]
        let ink = CanvasColor.linearP3(PaletteColor(oklab: .zero, rgb: blk.ink), space: space)
        mode.setBlock(field, kind: blk.kind, ink: ink, opacity: blk.opacity, tint: ink)
        mode.setColorSpace(p3: space == .displayP3)
        return field
    }

    // MARK: Touches

    /// Sizes in cells: the brush and the baren.
    private var brush: Float { Float(max(bench.width, bench.height)) * 0.035 }
    private var baren: Float { Float(max(bench.width, bench.height)) * 0.06 }

    @discardableResult
    func canvas(_ canvas: CanvasView, touched point: SIMD2<Float>, phase: CanvasTouchPhase) -> Bool {
        guard !isTurning, !showsPrint else { return false }
        // The rest of the stroke that laid the sheet rubs nothing either.
        if laidByStroke {
            if phase == .ended || phase == .tap { laidByStroke = false }
            return true
        }
        let p = plan.grid.cells(point)
        let from = phase == .began || phase == .tap ? p : (last ?? p)
        last = phase == .ended || phase == .tap ? nil : p
        switch bench.step {
        case .carve:
            let dirty = bench.carve(from: from, to: p, field: field)
            if !dirty.isEmpty {
                mode.update(.carved, from: bench.carved, dirty: dirty)
                ring()
            }
        case .ink:
            mode.update(.inked, from: bench.inked, dirty: bench.ink(from: from, to: p, radius: brush, field: field))
        case .sheet:
            guard phase == .tap || phase == .began else { return false }
            // The touch that lays the sheet rubs nothing.
            last = nil
            laySheet()
            laidByStroke = phase == .began
            return true
        case .rub:
            mode.update(.inked, from: bench.inked, dirty: bench.rub(from: from, to: p, radius: baren))
        case .peeled:
            return false
        }
        canvas.requestRender()
        if phase == .ended || phase == .tap { strokeEnded() }
        return true
    }

    /// The knife's bite in the hand, at most one a twentieth of a second.
    private func ring() {
        guard Date.now.timeIntervalSince(lastBite) > 0.05 else { return }
        lastBite = .now
        bite.impactOccurred(intensity: 0.45)
    }

    private func strokeEnded() {
        if let dirty = bench.advanceIfReady(field: field) {
            mode.update(bench.step == .ink ? .carved : .inked, from: bench.step == .ink ? bench.carved : bench.inked, dirty: dirty)
        }
        if bench.step == .rub { canPeel = bench.rubbedFraction(field: field) >= WoodblockBench.rubbedAt }
        stepChanged()
        changed()
    }

    // MARK: Steps

    func laySheet() {
        bench.laySheet()
        stepChanged()
        changed()
    }

    /// Finishes the step at once: VoiceOver's way through, which a finger may take too.
    func finishStep() {
        switch bench.step {
        case .carve:
            mode.update(.carved, from: bench.carved, dirty: bench.tidy(field: field))
            _ = bench.advanceIfReady(field: field)
        case .ink:
            bench.finishStep(plan: plan, field: field)
            mode.replace(.inked, with: bench.inked)
        case .sheet:
            laySheet()
            return
        case .rub:
            mode.update(.inked, from: bench.inked, dirty: bench.rubAll())
            canPeel = true
        case .peeled:
            return
        }
        canvas?.requestRender()
        stepChanged()
        changed()
    }

    /// Lifts the sheet: the block's ink is laid over the sheet, the flap peels, then the print shows.
    func peel() {
        guard bench.step == .rub else { return }
        let (start, plan, field) = (bench, plan, field)
        isTurning = true
        Task {
            bench = await Background.run {
                var b = start
                b.peel(plan: plan, field: field)
                return b
            }
            mode.replace(.sheet, with: bench.sheet)
            mode.show(.peeling, at: canvas?.canvasTime ?? 0, numbers: false, reduceMotion: reduceMotion)
            canvas?.requestRender()
            stepChanged()
            changed()
            if !reduceMotion { try? await Task.sleep(for: .seconds(Double(WoodblockMode.peelDuration) + 0.4)) }
            isTurning = false
            showsPrint = true
            // The last block's print is the finished print.
            if bench.block == plan.blocks.count - 1 {
                bench.next(plan: plan, field: nil)
                stepChanged()
                changed()
            }
            showPrint()
        }
    }

    /// The print so far, the areas blocks still to come print numbered on it (faint, mirrored as
    /// the print is: `WoodblockMode.drawOver`), the rest painted, which hides their numbers.
    private func showPrint() {
        guard let canvas else { return }
        let printed = isDone ? plan.blocks.count : bench.block + 1
        for r in plan.template.regions.indices {
            let waits = regionBlocks[r] != .max && regionBlocks[r] >= printed
            canvas.showMode(r, value: 0, painted: !waits, from: nil, animated: false)
        }
        mode.show(.print, at: canvas.canvasTime, numbers: !isDone, reduceMotion: reduceMotion)
        canvas.requestRender()
    }

    /// The block that prints each region, `Int.max` for one no block prints (the paper's).
    @ObservationIgnored private let regionBlocks: [Int]

    /// Takes the next block to the bench.
    func nextBlock() {
        guard bench.step == .peeled, !isDone else { return }
        isTurning = true
        var advanced = bench
        advanced.next(plan: plan, field: nil)
        let (plan, mode, b) = (plan, mode, advanced.block)
        Task {
            var next = advanced
            guard b < plan.blocks.count else {
                bench = next
                isTurning = false
                stepChanged()
                changed()
                return
            }
            let made = await Background.run { Self.prepare(plan: plan, block: b, mode: mode) }
            if next.step == .ink { next.startInked(field: made) }
            bench = next
            field = made
            showsPrint = false
            canPeel = false
            isTurning = false
            step = bench.step
            block = bench.block
            showAll()
            stepChanged()
            changed()
        }
    }

    private func stepChanged() {
        step = bench.step
        block = bench.block
        if !showsPrint { mode.show(view, at: canvas?.canvasTime ?? 0, numbers: showsNumbers, reduceMotion: reduceMotion) }
    }

    private var view: WoodblockMode.View {
        switch bench.step {
        case .carve, .ink, .sheet: .block
        case .rub: .sheet
        case .peeled: showsPrint ? .print : .peeling
        }
    }

    /// The colour blocks show their numbers while they are carved and inked.
    private var showsNumbers: Bool {
        current?.kind == .color && (bench.step == .carve || bench.step == .ink || bench.step == .sheet)
    }

    /// Everything on a canvas just made, or a block just brought: the textures, the numbers.
    private func showAll() {
        guard let canvas else { return }
        mode.replace(.carved, with: bench.carved)
        mode.replace(.inked, with: bench.inked)
        mode.replace(.sheet, with: bench.sheet)
        for r in plan.template.regions.indices {
            canvas.showMode(r, value: 0, painted: !plan.prints(region: r, block: bench.block), from: nil, animated: false)
        }
        if bench.step == .rub { canPeel = bench.rubbedFraction(field: field) >= WoodblockBench.rubbedAt }
        if showsPrint {
            showPrint()
            return
        }
        mode.show(view, at: canvas.canvasTime, numbers: showsNumbers, reduceMotion: reduceMotion)
        canvas.requestRender()
    }

    // MARK: Words

    /// Where the print stands while a block is worked, over the step's line.
    var progress: String? {
        guard !isDone, !showsPrint else { return nil }
        return String(localized: "woodblock.blockOf", defaultValue: "Block \(block + 1) of \(blocks)",
                      comment: "Over the woodblock bench's line while a block is worked: its place among the print's blocks, and how many there are")
    }

    /// The one line the step shows.
    var instruction: String {
        if isDone {
            return String(localized: "woodblock.done", defaultValue: "Your print is finished.",
                          comment: "The woodblock bench's line once every block is printed")
        }
        if showsPrint {
            return String(localized: "woodblock.printed", defaultValue: "Block \(block + 1) of \(blocks) printed.",
                          comment: "The woodblock bench's line after a block is printed: its place among the print's blocks")
        }
        switch step {
        case .carve:
            return current?.kind == .key
                ? String(localized: "woodblock.carveKey", defaultValue: "Clear the wood around the lines.",
                         comment: "The woodblock bench's line while the key block (the drawing's lines) is carved")
                : String(localized: "woodblock.carveColor", defaultValue: "Clear the wood around block \(current?.number ?? 0)’s areas.",
                         comment: "The woodblock bench's line while a colour block is carved: its number")
        case .ink:
            return current?.kind == .key
                ? String(localized: "woodblock.inkKey", defaultValue: "Brush the ink on the lines.",
                         comment: "The woodblock bench's line while black ink is brushed onto the key block (the drawing's lines)")
                : String(localized: "woodblock.inkColor", defaultValue: "Brush block \(current?.number ?? 0)’s colour on.",
                         comment: "The woodblock bench's line while a colour block's ink is brushed on: its number")
        case .sheet:
            return String(localized: "woodblock.sheet", defaultValue: "Tap to lay the sheet.",
                          comment: "The woodblock bench's line when the damp paper is ready to lay on the block")
        case .rub:
            return String(localized: "woodblock.rub", defaultValue: "Rub with the baren.",
                          comment: "The woodblock bench's line while the paper is pressed with a baren, the printer's rubbing pad")
        case .peeled:
            return String(localized: "woodblock.peeling", defaultValue: "The sheet comes up with the print.",
                          comment: "The woodblock bench's line while the paper peels off the inked block")
        }
    }

    /// The ink on the bench, shown beside the line while a colour block is worked.
    var inkSwatch: Color? {
        guard !isDone, !showsPrint, step != .peeled, let current, current.kind != .key else { return nil }
        let space: Color.RGBColorSpace = plan.template.colorSpace == .displayP3 ? .displayP3 : .sRGB
        return Color(space, red: Double(current.ink.x), green: Double(current.ink.y), blue: Double(current.ink.z))
    }

    func canvas(_ canvas: CanvasView, speak region: Int) -> (label: String, value: String) {
        let paint = Int(plan.template.regions[region].colorIndex) + 1
        return (String(localized: "woodblock.area", defaultValue: "Area \(region + 1)",
                       comment: "VoiceOver name of one area of a woodblock print, by its number"),
                String(localized: "woodblock.areaBlock", defaultValue: "Block \(paint)",
                       comment: "VoiceOver value of an area of a woodblock print: the number of the colour block that prints it"))
    }

    func canvasSummary(_ canvas: CanvasView) -> (label: String, value: String) {
        (String(localized: "woodblock.bench", defaultValue: "Woodblock",
                comment: "VoiceOver name of the woodblock bench, where the block is carved and printed"), instruction)
    }

    // MARK: Saving and sharing

    private func changed() {
        saving?.cancel()
        let bench = bench
        saving = Task {
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            onChange(bench)
        }
    }

    func flush() {
        guard saving != nil else { return }
        saving?.cancel()
        saving = nil
        onChange(bench)
    }

    /// The print as it stands, as a PNG named `title` to share.
    func sharedPicture(title: String) async throws -> URL {
        let (bench, space) = (bench, plan.template.colorSpace)
        return try await Background.run {
            guard let image = WoodblockShelf.picture(of: bench, space: space), let png = ImageCodec.pngData(image)
            else { throw CocoaError(.fileWriteUnknown) }
            return try ArtworkExporter.temporaryFile(png, name: ArtworkExporter.fileName(title), pathExtension: "png")
        }
    }
}

/// The canvas the bench shows on: the painting screen's own (`CanvasView`), pinch, pan and all,
/// in Woodblock's mode, its touches the bench's.
struct WoodblockCanvas: UIViewRepresentable {
    let model: WoodblockBenchModel

    func makeUIView(context: Context) -> CanvasView {
        let view = CanvasView(session: model.session)
        view.reduceMotion = context.environment.accessibilityReduceMotion
        view.mode = model.mode
        view.touches = model
        // Room past the picture for the block's margin, its kentō.
        view.chromeInsets = UIEdgeInsets(top: 30, left: 30, bottom: 30, right: 30)
        view.backgroundColor = UIColor(WoodblockEra.bench)
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

struct WoodblockBenchView: View {
    @State var model: WoodblockBenchModel
    let title: String
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @State private var sharedFile: URL?
    @State private var isSharing = false

    init(model: WoodblockBenchModel, title: String) {
        _model = State(initialValue: model)
        self.title = title
    }

    var body: some View {
        VStack(spacing: 0) {
            WoodblockCanvas(model: model)
            footer
        }
        .background(WoodblockEra.bench.ignoresSafeArea())
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Share", systemImage: "square.and.arrow.up", action: share)
                    .disabled(isSharing || model.block == 0 && !model.showsPrint)
                    .accessibilityIdentifier("woodblock-share")
            }
        }
        .background {
            ActivityShareSheet(item: sharedFile) {
                if let sharedFile { ArtworkExporter.removeExport(at: sharedFile) }
                sharedFile = nil
            }
        }
        .sensoryFeedback(.success, trigger: model.showsPrint) { _, shown in shown }
        .onChange(of: model.instruction) { _, line in
            AccessibilityNotification.Announcement(line).post()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { model.flush() }
        }
        .onDisappear { model.flush() }
    }

    private var footer: some View {
        VStack(spacing: 10) {
            if let progress = model.progress {
                Text(progress)
                    .font(.footnote.smallCaps())
                    .foregroundStyle(Color(red: 0.93, green: 0.86, blue: 0.74).opacity(0.6))
                    .accessibilityIdentifier("woodblock-progress")
            }
            HStack(spacing: 10) {
                if let swatch = model.inkSwatch {
                    Circle()
                        .fill(swatch)
                        .overlay(Circle().strokeBorder(.white.opacity(0.35), lineWidth: 1))
                        .frame(width: 22, height: 22)
                        .accessibilityHidden(true)
                }
                Text(model.instruction)
                    .font(.display(.body))
                    .foregroundStyle(Color(red: 0.93, green: 0.86, blue: 0.74))
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("woodblock-instruction")
            }
            action
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 92)
        // The line sits on the bench itself, not on a bar of its own.
        .background(WoodblockEra.bench.ignoresSafeArea(edges: .bottom))
    }

    @ViewBuilder private var action: some View {
        if model.isDone {
            EmptyView()
        } else if model.showsPrint {
            Button("Next Block") { model.nextBlock() }
                .buttonStyle(.glassProminent)
                .tint(Theme.signature)
                .disabled(model.isTurning)
                .accessibilityIdentifier("woodblock-next")
        } else if model.step == .sheet {
            Button("Lay the Sheet") { model.laySheet() }
                .buttonStyle(.glass)
                .accessibilityIdentifier("woodblock-lay")
        } else if model.step == .rub && (model.canPeel || stepsByButton) {
            HStack {
                if stepsByButton && !model.canPeel {
                    Button("Rub It All") { model.finishStep() }
                        .buttonStyle(.glass)
                        .disabled(model.isTurning)
                        .accessibilityIdentifier("woodblock-rub-all")
                }
                Button("Lift the Sheet") { model.peel() }
                    .buttonStyle(.glassProminent)
                    .tint(Theme.signature)
                    .disabled(model.isTurning || !model.canPeel)
                    .accessibilityIdentifier("woodblock-peel")
            }
        } else if stepsByButton && (model.step == .carve || model.step == .ink) {
            if model.step == .carve {
                Button("Carve It") { model.finishStep() }
                    .buttonStyle(.glass)
                    .accessibilityIdentifier("woodblock-carve-it")
            } else {
                Button("Ink It") { model.finishStep() }
                    .buttonStyle(.glass)
                    .accessibilityIdentifier("woodblock-ink-it")
            }
        }
    }

    /// The steps a finger works, each as a button: VoiceOver's way through, and a UI test's
    /// (`-woodblock-steps`, Debug builds) once its own strokes have shown the finger's.
    private var stepsByButton: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-woodblock-steps") { return true }
        #endif
        return voiceOver
    }

    private func share() {
        isSharing = true
        Task {
            defer { isSharing = false }
            do {
                sharedFile = try await model.sharedPicture(title: title)
            } catch {
                Log.library.error("Couldn't share a print: \(String(describing: error), privacy: .public)")
            }
        }
    }
}
#endif

#if UNRELEASED && DEBUG
extension WoodblockBenchModel {
    /// Works the bench to where a demo holds it (`WoodblockDemo`): `printed` blocks printed in
    /// full, then the block on the bench taken to `step` with `share` of that step's work done
    /// by strokes, as a finger would. Synchronous: demos only.
    func demoWork(printed: Int, step: WoodblockBench.Step, share: Float) {
        let wholeBlocks = step == .peeled ? printed - 1 : printed
        for _ in 0..<max(0, wholeBlocks) where !bench.isDone(in: plan) {
            while bench.step != .peeled { bench.finishStep(plan: plan, field: field) }
            bench.next(plan: plan, field: nil)
            guard !bench.isDone(in: plan) else { break }
            field = Self.prepare(plan: plan, block: bench.block, mode: mode)
            if bench.step == .ink { bench.startInked(field: field) }
        }
        let w = Float(bench.width), h = Float(bench.height)
        func sweep(_ stroke: (SIMD2<Float>, SIMD2<Float>) -> Void) {
            let rows = Int(h / 6)
            for k in 0..<Int(Float(rows) * share) {
                let y = Float(k) * 6 + 3
                stroke(SIMD2(0, y), SIMD2(w, y + (k % 2 == 0 ? 4 : -4)))
            }
        }
        if step == .peeled {
            while bench.step != .peeled { bench.finishStep(plan: plan, field: field) }
            if printed >= plan.blocks.count { bench.next(plan: plan, field: nil) }
        }
        if bench.step == .carve && step != .carve { bench.finishStep(plan: plan, field: field) }
        if bench.step == .ink && step != .ink && step != .carve { bench.finishStep(plan: plan, field: field) }
        if bench.step == .sheet && step == .rub { bench.laySheet() }
        switch bench.step {
        case .carve: sweep { bench.carve(from: $0, to: $1, field: field) }
        case .ink: sweep { bench.ink(from: $0, to: $1, radius: 10, field: field) }
        case .rub:
            sweep { bench.rub(from: $0, to: $1, radius: 12) }
            sweep { bench.rub(from: $0, to: $1, radius: 12) }
            canPeel = true
        default: break
        }
        self.step = bench.step
        self.block = bench.block
        self.showsPrint = bench.step == .peeled
    }

    /// Holds the peel `fraction` of the way, the block's ink laid on the sheet (demos).
    func demoHoldPeel(at fraction: Float) {
        guard bench.step == .rub else { return }
        bench.peel(plan: plan, field: field)
        step = bench.step
        mode.replace(.sheet, with: bench.sheet)
        mode.holdPeel(at: fraction)
        canvas?.requestRender()
    }
}
#endif
