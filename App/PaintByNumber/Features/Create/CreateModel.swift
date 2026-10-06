import CoreGraphics
import Foundation
import Observation
import os
import PaintCore
import PhotosUI
import SwiftUI

/// Drives the create flow: holds the chosen photo, chooses settings for it (Suggested
/// settings: the first candidate shows as a draft at once, the winner swaps in), and
/// regenerates the template as the settings change — quick reduced-size drafts while a slider
/// is being dragged, the full resolution once it settles — always discarding stale work.
@Observable
final class CreateModel {
    struct Source {
        let image: RGBAImage
        let preview: CGImage
        let sampleName: String?
    }

    nonisolated struct Preview: Sendable, Identifiable {
        let id = UUID()
        let template: Template
        /// All regions painted, no lines.
        let painting: CGImage
        /// Outlines with numbers, as the painting starts.
        let outlines: CGImage
        /// Nil for a suggestion's first draft, shown before the settings are chosen.
        let settings: GenerationSettings?
        /// Generated from the reduced photo while adjusting.
        let isDraft: Bool
    }

    nonisolated struct Stats: Equatable, Sendable {
        var colors: Int
        var areas: Int
        var estimate: TimeInterval

        init(_ t: Template) {
            colors = t.palette.count
            areas = t.regions.count
            estimate = PaintingTime.estimate(regionCount: t.regions.count)
        }

        var summary: String { TemplateCounts.summary(colors: colors, areas: areas, seconds: estimate) }
    }

    enum Phase: Equatable {
        case idle
        case loading
        /// Finding the subject (Vision) before the first generation.
        case analyzing
        /// Choosing settings for the photo; its first candidate shows as a draft meanwhile.
        case suggesting
        case generating
        case ready
        case failed(String)
    }

    nonisolated enum CreateError: LocalizedError {
        case unreadable, renderFailed, cameraCapture

        var errorDescription: String? {
            switch self {
            case .unreadable:
                String(localized: "create.error.unreadable", defaultValue: "This photo couldn’t be opened. Try another one.",
                       comment: "Error when a chosen photo can't be decoded")
            case .renderFailed:
                String(localized: "create.error.renderFailed", defaultValue: "The template couldn’t be created. Try different settings.",
                       comment: "Error when the template can't be generated from the photo")
            case .cameraCapture:
                String(localized: "create.error.cameraCapture",
                       defaultValue: "The photo from the camera couldn’t be used. Try taking it again.",
                       comment: "Error when the photo just taken with the camera can't be used")
            }
        }
    }

    private(set) var source: Source?
    private(set) var preview: Preview?
    /// Stats of the latest full-resolution template.
    private(set) var stats: Stats?
    private(set) var phase: Phase = .idle
    /// 0…1 progress of the running full-resolution generation.
    private(set) var progress: Double = 0
    private(set) var isAdjusting = false
    /// The settings a full-resolution generation is running for, if one is.
    private(set) var refining: GenerationSettings?
    /// Whether the settings are the suggestion for this photo or the painter's own; nil until
    /// a suggestion exists.
    private(set) var settingsOrigin: SettingsOrigin?
    /// The suggestion for the current photo, kept so Reset to Suggested restores it without
    /// choosing again. Reproducible from the photo and the painting length, so never saved.
    private(set) var decision: AutoDecision?
    /// What suggestions aim for (Settings › Painting Length).
    let paintingLength: PaintingLength
    /// The line art the painting is made with before the Lines slider (the coloring book's
    /// defaults in the app), on top of the suggested or slider settings: every candidate of a
    /// suggestion carries it.
    let baseLineArt: LineArtSettings
    /// The Lines slider: 0.5 is the base line art, toward 1 more lines, toward 0 fewer
    /// (`lineArt(_:lines:)`). Classic line art has no lines to tune.
    var lines = 0.5
    /// The line art the painting is made with: the base with the Lines slider applied.
    var lineArt: LineArtSettings { Self.lineArt(baseLineArt, lines: lines) }
    /// What the coloring book draws from, computed once per photo; nil for classic line art.
    @ObservationIgnored private(set) var lineArtInput: LineArtInput?
    /// The painting's name as typed; empty means `defaultTitle`.
    var title = ""
    /// The sample's name, or the date for a photo.
    private(set) var defaultTitle = ""

    /// The name the painting is created with: the trimmed title, or the default.
    var resolvedTitle: String {
        let typed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return typed.isEmpty ? defaultTitle : typed
    }

    var colorCount: Double
    var detail: Double
    var smoothness: Double

    /// Settings tried per photo: five where there are cores for them, three on smaller devices
    /// so a suggestion stays within its time budget.
    nonisolated static var maxCandidates: Int { ProcessInfo.processInfo.activeProcessorCount < 6 ? 3 : 5 }

    @ObservationIgnored private var importance: PaintCore.Grid<Float>?
    @ObservationIgnored private var draftImage: RGBAImage?
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var fullTask: Task<Void, Never>?
    @ObservationIgnored private var draftTask: Task<Void, Never>?
    @ObservationIgnored private var draftToken = UUID()
    @ObservationIgnored private var draftPending = false
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var refiningID = 0
    /// Identifies the photo being loaded, so a late first draft of an earlier one is dropped.
    @ObservationIgnored private var loadID = 0

    /// The sliders start at the generator's defaults; a photo moves them to its suggestion.
    init(paintingLength: PaintingLength = Preferences().paintingLength, lineArt: LineArtSettings = LineArtSettings()) {
        self.paintingLength = paintingLength
        self.baseLineArt = lineArt.normalized
        let initial = GenerationSettings()
        colorCount = Double(initial.colorCount)
        detail = Double(initial.detail)
        smoothness = Double(initial.smoothness)
    }

    var settings: GenerationSettings {
        GenerationSettings(
            colorCount: Int(colorCount.rounded()), detail: Float(detail), smoothness: Float(smoothness), lineArt: lineArt
        ).normalized
    }

    /// The photo's settings are still being chosen: the sliders wait for them.
    var isChoosingSettings: Bool {
        switch phase {
        case .loading, .analyzing, .suggesting: true
        default: false
        }
    }

    /// The preview matches the settings at full resolution.
    var isFinal: Bool {
        guard let preview else { return false }
        return !preview.isDraft && preview.settings == settings
    }

    // MARK: Choosing a photo

    func load(sample: Sample) {
        guard let url = sample.url else {
            phase = .failed(CreateError.unreadable.localizedDescription)
            return
        }
        begin(defaultTitle: sample.title, sampleName: sample.id) { try await Self.decode(url: url) }
    }

    func load(item: PhotosPickerItem) {
        begin(defaultTitle: Self.photoTitle(), sampleName: nil) {
            guard let data = try await item.loadTransferable(type: Data.self) else { throw CreateError.unreadable }
            return try await Self.decode(data: data)
        }
    }

    /// `title` names the painting when the photo came with a name (an opened file); without
    /// one, the date does.
    func load(imageData: Data, title: String? = nil) {
        begin(defaultTitle: title ?? Self.photoTitle(), sampleName: nil) { try await Self.decode(data: imageData) }
    }

    /// A photo that never arrived (the camera's shot couldn't be read): shown in place of the
    /// preview.
    func fail(_ error: CreateError) {
        cancelAll()
        source = nil
        preview = nil
        stats = nil
        decision = nil
        settingsOrigin = nil
        phase = .failed(error.localizedDescription)
    }

    private func begin(defaultTitle: String, sampleName: String?, decode: @escaping () async throws -> Decoded) {
        cancelAll()
        // A new photo gets a new default name, and anything typed for the last one goes.
        self.defaultTitle = defaultTitle
        title = ""
        source = nil
        preview = nil
        stats = nil
        importance = nil
        lineArtInput = nil
        draftImage = nil
        decision = nil
        settingsOrigin = nil
        progress = 0
        phase = .loading
        loadID += 1
        let load = loadID
        let preference = paintingLength
        let lineArt = baseLineArt
        loadTask = Task {
            do {
                let decoded = try await decode()
                try Task.checkCancellation()
                source = Source(image: decoded.image, preview: decoded.preview, sampleName: sampleName)
                phase = .analyzing
                let prepared = try await Self.prepare(decoded, lineArt: lineArt)
                try Task.checkCancellation()
                importance = prepared.importance
                lineArtInput = prepared.lineArt
                draftImage = prepared.draft
                phase = .suggesting
                let chosen: AutoDecision?
                do {
                    chosen = try await Self.suggest(
                        prepared, sourceSize: (decoded.image.width, decoded.image.height), preference: preference,
                        lineArt: lineArt, maxCandidates: Self.maxCandidates,
                        firstDraft: Self.firstDraftHandler(for: self, load: load))
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    // Without a suggestion the photo still gets a template, on the sliders' settings.
                    Log.create.error("Choosing settings failed: \(String(describing: error), privacy: .public)")
                    chosen = nil
                }
                try Task.checkCancellation()
                if let chosen {
                    adopt(chosen)
                } else {
                    phase = .ready
                    startGeneration(draftFirst: true)
                }
            } catch is CancellationError {
            } catch {
                Log.create.error("Loading photo failed: \(String(describing: error), privacy: .public)")
                phase = .failed((error as? CreateError ?? .unreadable).localizedDescription)
            }
        }
    }

    // MARK: Adjusting

    /// How long a slider's thumb rests under the finger before the full resolution renders:
    /// the painter sees what they get without letting go.
    static let restDelay: Duration = .milliseconds(350)

    /// Call when the painter changed a setting: the settings become their own, unless they
    /// are back on the suggestion's (the sliders' detents).
    func settingsChanged() {
        guard source != nil, !isChoosingSettings else { return }
        if let decision { settingsOrigin = settings == decision.settings ? .suggested : .custom }
        if isAdjusting {
            requestDraft()
            scheduleFull(after: Self.restDelay)
        } else {
            scheduleFull(after: .milliseconds(250))
        }
    }

    /// A slider drag began or ended.
    func setAdjusting(_ adjusting: Bool) {
        guard adjusting != isAdjusting else { return }
        isAdjusting = adjusting
        if adjusting {
            fullTask?.cancel()
        } else {
            stopDrafts()
            // The resting thumb's full resolution, already under way for these settings, carries on.
            if refining != settings { scheduleFull(after: .milliseconds(60)) }
        }
    }

    /// Back to the suggestion's settings, without choosing again.
    func resetToSuggested() {
        guard let decision else { return }
        apply(decision.settings)
        settingsOrigin = .suggested
        startGeneration(draftFirst: true)
    }

    func cancelAll() {
        loadTask?.cancel()
        loadTask = nil
        fullTask?.cancel()
        stopDrafts()
    }

    /// The full-resolution template for the current settings, generating it if needed.
    func makeDraft() async throws -> ArtworkDraft {
        // Settings still being chosen are chosen first.
        _ = await loadTask?.value
        guard let source else { throw CreateError.unreadable }
        let settings = self.settings
        if !isFinal {
            fullTask?.cancel()
            stopDrafts()
            await generate(draft: false, settings: settings)
        }
        guard let preview, !preview.isDraft, preview.settings == settings else { throw CreateError.renderFailed }
        return ArtworkDraft(
            title: resolvedTitle, template: preview.template, settings: settings, settingsOrigin: settingsOrigin,
            paintingLength: decision?.preference, photo: source.preview, sampleName: source.sampleName)
    }

    /// Moves the sliders to the suggestion and generates it: the winner as a draft first unless
    /// it is the candidate already on screen and drawn as it will be (suggestion drafts have no
    /// edge map, so line art other than classic is drafted again), then at full resolution.
    private func adopt(_ decision: AutoDecision) {
        self.decision = decision
        apply(decision.settings)
        settingsOrigin = .suggested
        phase = .generating
        let shownAsItWillBe = decision.winner == 0 && preview != nil && lineArt.style == .classic
        startGeneration(draftFirst: !shownAsItWillBe)
    }

    /// A suggestion's settings on the sliders; its candidates carry the base line art, the Lines
    /// slider's middle.
    private func apply(_ settings: GenerationSettings) {
        colorCount = Double(settings.colorCount)
        detail = Double(settings.detail)
        smoothness = Double(settings.smoothness)
        lines = 0.5
    }

    /// Generates the current settings as the cancellable full-resolution job, so setting
    /// changes supersede it; a quick draft first makes something appear at once.
    private func startGeneration(draftFirst: Bool) {
        fullTask?.cancel()
        stopDrafts()
        let settings = self.settings
        fullTask = Task {
            if draftFirst {
                await generate(draft: true, settings: settings)
                guard !Task.isCancelled else { return }
            }
            await generate(draft: false, settings: settings)
        }
    }

    /// A suggestion's first candidate, rendered: shown unless the photo changed or the
    /// suggestion already finished.
    private func showFirstDraft(_ draft: Preview, load: Int) {
        guard load == loadID, phase == .suggesting, preview == nil else { return }
        withAnimation(.easeInOut(duration: 0.18)) { preview = draft }
    }

    private func requestDraft() {
        fullTask?.cancel()
        // A full resolution the thumb's rest started gives way to the drafts again.
        if refining != nil, phase == .generating, preview != nil { phase = .ready }
        draftPending = true
        guard draftTask == nil else { return }
        let token = UUID()
        draftToken = token
        // Coalesce: while a draft renders, further changes only mark it dirty, so the
        // preview keeps up with the finger at the pipeline's own pace.
        draftTask = Task {
            while draftPending && !Task.isCancelled {
                draftPending = false
                await generate(draft: true, settings: settings)
            }
            if draftToken == token { draftTask = nil }
        }
    }

    private func stopDrafts() {
        draftTask?.cancel()
        draftTask = nil
        draftPending = false
        draftToken = UUID()
    }

    private func scheduleFull(after delay: Duration) {
        fullTask?.cancel()
        fullTask = Task {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await generate(draft: false, settings: settings)
        }
    }

    // MARK: Generation

    private func generate(draft: Bool, settings: GenerationSettings) async {
        guard let source else { return }
        if isFinal && preview?.settings == settings {
            phase = .ready
            return
        }
        generation += 1
        let id = generation
        let input = draft ? (draftImage ?? source.image) : source.image
        if !draft {
            phase = .generating
            progress = 0
            refining = settings
            refiningID = id
        }
        defer { if !draft, refiningID == id { refining = nil } }
        // Called on pipeline threads; hops to the main actor.
        let report: @Sendable (Float) -> Void = { value in
            Task { @MainActor in
                guard self.generation == id else { return }
                self.progress = Double(value)
            }
        }
        do {
            let made = draft ? Self.draftSettings(settings, draft: input, source: source.image) : settings
            let result = try await Self.render(
                input, importance: importance, lineArt: lineArtInput, settings: made, recorded: settings, isDraft: draft,
                progress: draft ? nil : report)
            try Task.checkCancellation()
            // A draft finishing after a newer generation began (the resting thumb's full
            // resolution) would replace it with less.
            if draft, generation != id { return }
            // Drafts follow the finger as they come: a crossfade would blur one into the next.
            withAnimation(draft ? nil : .easeInOut(duration: 0.35)) {
                preview = result
                if !draft { stats = Stats(result.template) }
            }
            if generation == id { phase = .ready }
        } catch is CancellationError {
        } catch {
            Log.create.error("Generation failed: \(String(describing: error), privacy: .public)")
            phase = .failed(CreateError.renderFailed.localizedDescription)
        }
    }

    // MARK: Background work

    /// A decoded photo the pipeline can work with: at least 16 px on each side, with a preview.
    nonisolated struct Decoded: Sendable {
        let image: RGBAImage
        let preview: CGImage

        init(_ image: RGBAImage) throws {
            guard image.width >= 16, image.height >= 16, let preview = PhotoLoader.cgImage(from: image) else {
                throw CreateError.unreadable
            }
            self.image = image
            self.preview = preview
        }
    }

    nonisolated struct Prepared: Sendable {
        var importance: PaintCore.Grid<Float>?
        var hints: SubjectHints
        var draft: RGBAImage
        var lineArt: LineArtInput?
    }

    @concurrent
    static func decode(url: URL) async throws -> Decoded {
        try Decoded(PhotoLoader.load(url: url, maxPixelSize: ArtworkStore.sourceMaxPixelSize))
    }

    @concurrent
    private static func decode(data: Data) async throws -> Decoded {
        try Decoded(PhotoLoader.load(data: data, maxPixelSize: ArtworkStore.sourceMaxPixelSize))
    }

    /// Subject importance and hints, and for a coloring book the edge map and eyes (once per
    /// photo, side by side), and the reduced photo for drafts and suggestions.
    @concurrent
    private static func prepare(_ decoded: Decoded, lineArt: LineArtSettings) async throws -> Prepared {
        async let input = LineArtInputs.forGeneration(of: decoded.preview, settings: lineArt, cached: true)
        let subject = SubjectImportance.analyze(decoded.preview)
        let draft = AutoSettings.draftImage(from: decoded.image)
        return Prepared(importance: subject.map, hints: subject.hints, draft: draft, lineArt: try await input)
    }

    /// Chooses settings for the photo on its draft. `sourceSize` is the photo's own size: it
    /// sets the canvas the painting time is estimated for.
    @concurrent
    private static func suggest(
        _ prepared: Prepared, sourceSize: (width: Int, height: Int), preference: PaintingLength,
        lineArt: LineArtSettings, maxCandidates: Int,
        firstDraft: @escaping @Sendable (Preview) -> Void
    ) async throws -> AutoDecision {
        // A task's cancellation shows only on the thread running it; the flag reaches every
        // candidate's thread at once.
        let flag = CancellationFlag()
        return try await withTaskCancellationHandler {
            try AutoSettings.choose(
                image: prepared.draft, sourceSize: sourceSize, importance: prepared.importance, hints: prepared.hints,
                preference: preference, maxCandidates: maxCandidates, lineArt: lineArt,
                cancel: CancellationCheck { flag.isSet }
            ) { output in
                // Rendered here, before the other candidates run: it is what the painter waits for.
                guard let preview = try? Self.makePreview(output.template, settings: nil, isDraft: true) else { return }
                firstDraft(preview)
            }
        } onCancel: {
            flag.set()
        }
    }

    /// Hands a first draft from the pipeline thread that rendered it to the main actor. Formed
    /// here, outside the main actor, because it is called on that thread.
    nonisolated private static func firstDraftHandler(for model: CreateModel, load: Int) -> @Sendable (Preview) -> Void {
        { preview in
            Task { @MainActor in model.showFirstDraft(preview, load: load) }
        }
    }

    /// The template of `settings`, its preview recording `recorded` (the sliders' settings a
    /// draft stands for).
    @concurrent
    private static func render(
        _ image: RGBAImage, importance: PaintCore.Grid<Float>?, lineArt: LineArtInput?, settings: GenerationSettings,
        recorded: GenerationSettings, isDraft: Bool, progress: (@Sendable (Float) -> Void)?
    ) async throws -> Preview {
        let template = try TemplateGenerator(settings: settings)
            .generate(from: image, importance: importance, lineArt: lineArt, cancel: .task, progress: progress)
            .template
        try Task.checkCancellation()
        return try makePreview(template, settings: recorded, isDraft: isDraft)
    }

    /// A draft's settings: the line art's lengths in canvas pixels (the shortest line, the gaps
    /// closed) scaled from the full resolution's canvas to the draft's, a third of it or less, so
    /// a draft draws the short strokes the final will (an eye, a nostril), which the full lengths
    /// drop at a draft's size.
    nonisolated static func draftSettings(_ settings: GenerationSettings, draft: RGBAImage, source: RGBAImage) -> GenerationSettings {
        let small = settings.workingSize(sourceWidth: draft.width, sourceHeight: draft.height)
        let full = settings.workingSize(sourceWidth: source.width, sourceHeight: source.height)
        let scale = Float(max(small.width, small.height)) / Float(max(full.width, full.height, 1))
        guard scale < 1 else { return settings }
        var made = settings
        made.lineArt.minimumStrokeLength *= scale
        made.lineArt.gapBridging *= scale
        return made
    }

    /// `base` with the Lines slider at `lines`: toward More the thresholds fall by up to 0.2 (weaker
    /// edges drawn, outlines with them) and the shortest line halves, toward Fewer they rise and it
    /// grows half again; the middle is `base` itself.
    nonisolated static func lineArt(_ base: LineArtSettings, lines: Double) -> LineArtSettings {
        let more = Float(min(max(lines, 0), 1) - 0.5) * 2
        guard base.style != .classic, more != 0 else { return base }
        var art = base
        art.detailThreshold = min(max(base.detailThreshold - 0.2 * more, 0.2), 0.95)
        art.outlineThreshold = min(max(base.outlineThreshold - 0.2 * more, 0.2), 0.95)
        art.minimumStrokeLength = base.minimumStrokeLength * (1 - 0.5 * more)
        return art.normalized
    }

    nonisolated private static func makePreview(_ template: Template, settings: GenerationSettings?, isDraft: Bool) throws -> Preview {
        #if DEBUG
        // Debug builds (CI's simulator runs) check every final template's invariants,
        // legible numbers included.
        if !isDraft {
            let report = template.validate(minLabelRadius: LabelSizing.minimumRadius)
            if !report.isValid { assertionFailure("Generated template violates its invariants: \(report)") }
        }
        #endif
        let long = max(template.width, template.height)
        guard let painting = TemplateRasterizer.image(template, style: .painting, maxPixelSize: long),
              let outlines = TemplateRasterizer.image(template, style: .template, maxPixelSize: min(2400, max(1280, long * 2)))
        else { throw CreateError.renderFailed }
        return Preview(template: template, painting: painting, outlines: outlines, settings: settings, isDraft: isDraft)
    }

    private static func photoTitle() -> String {
        Date.now.formatted(.dateTime.month(.wide).day())
    }
}
