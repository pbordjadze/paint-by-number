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
///
/// The template shown at full resolution is the one the generator makes from the photo, the
/// settings and the refinements' generator inputs (the base), with the painter's manual edits laid
/// on it in order (`EditTrail`, `refinements.edits`). Refine's edits are made to that template
/// alone (`edit(_:)`, `fill(at:color:)`: no regeneration), its brushes and the sliders make the
/// base again and the edits are laid on the new one. `MARK: Refine` says how.
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
        let picture: Picture
        /// The template's lines, which Refine draws and erases over whatever the preview shows.
        let drawing: LineArtDrawing
        /// Nil for a suggestion's first draft, shown before the settings are chosen.
        let settings: GenerationSettings?
        /// What it was refined with (none for a suggestion's first draft); a full-resolution
        /// template has these edits laid.
        let refinements: TemplateRefinements
        /// Generated from the reduced photo while adjusting.
        let isDraft: Bool
    }

    /// What the comparison shows of a template (`previewStyle`).
    nonisolated enum Picture: Sendable {
        /// All regions painted, under a coloring book's drawing (a classic template shows no lines).
        case painting(CGImage)
        /// The lines alone, drawn by the comparison at the size it shows them.
        case lineArt(LineArtDrawing)
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
    /// What the comparison shows beside the photo (Settings › Preview).
    let previewStyle: PreviewStyle
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
    /// The painter's refinements of this photo's template (the optional Refine step): the
    /// generator's inputs apply to every draft and the painting, and the edits are laid on each
    /// full-resolution template. None until refined.
    private(set) var refinements = TemplateRefinements()
    /// What Undo and Redo step through on the Refine screen, and what Cancel puts back.
    private(set) var history = RefineHistory()
    /// The newest edit sent (`edit(_:)`, `fill(at:color:)`) whose result `preview` shows, or that
    /// did nothing: Refine draws the edits sent after it over the template on screen.
    private(set) var settledEdits = 0
    /// What Refine tells the painter: an edit that could not be made, edits that no longer fit.
    private(set) var note: RefineNote?
    /// The painter tapped Refine before the final template was there (`askForRefine()`): it opens
    /// as soon as it is.
    private(set) var refineAsked = false
    /// The painting's name as typed; empty means `defaultTitle`.
    var title = ""
    /// The sample's name, or the date for a photo.
    private(set) var defaultTitle = ""
    /// Names the photo, new with each one chosen and the draft's for a photo resumed from one.
    private(set) var photoID = UUID()

    /// The name the painting is created with: the trimmed title, or the default.
    var resolvedTitle: String { CreateDraft.resolvedTitle(typed: title, default: defaultTitle) }

    /// What `Drafts` keeps of this flow: nil until the photo has refinements, and while its
    /// settings are being chosen (the sliders don't hold them yet).
    var draft: CreateDraft? {
        guard let source, !isChoosingSettings, !refinements.isEmpty else { return nil }
        return CreateDraft(
            photoID: photoID, title: title, defaultTitle: defaultTitle, settings: settings, lines: lines,
            sampleName: source.sampleName, refinements: refinements)
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
    /// The photo's latest full-resolution templates as the generator made them (no edits) and
    /// what they were made with, newest first: stepping back to one (a brush undone, a slider put
    /// back) lays the edits on it again without generating.
    @ObservationIgnored private var made: [Made] = []

    /// How many base templates are kept for stepping back (`made`).
    var rememberedBases: Int { made.count }

    private struct Made {
        let settings: GenerationSettings
        /// The generator inputs it was made with (`TemplateRefinements.generatorInputs`).
        let refinements: TemplateRefinements
        let template: Template
    }

    /// What a base template is made of: the settings and the refinements' generator inputs.
    private struct BaseKey: Equatable {
        let settings: GenerationSettings
        let inputs: TemplateRefinements
    }

    private var currentKey: BaseKey { BaseKey(settings: settings, inputs: refinements.generatorInputs) }

    /// The base template on screen with the edits laid on it, and what it is the base of.
    @ObservationIgnored private var trail: EditTrail?
    @ObservationIgnored private var trailKey: BaseKey?
    /// Edits numbered as sent, and the newest whose turn has come (`MARK: Refine`).
    @ObservationIgnored private var sentEdits = 0
    @ObservationIgnored private var handledEdits = 0
    /// How many edits the newest base left out, as the painter was last told.
    @ObservationIgnored private var leftOutEdits = 0
    /// Refine's changes run one after another (`enqueue`); a new photo makes the ones waiting moot.
    @ObservationIgnored private var refineQueue: Task<Void, Never>?
    @ObservationIgnored private var refineEpoch = 0
    @ObservationIgnored private var noteTask: Task<Void, Never>?

    /// How many full-resolution templates `made` keeps: a template is a megabyte or two.
    static let madeKept = 6

    /// The sliders start at the generator's defaults; a photo moves them to its suggestion.
    init(
        paintingLength: PaintingLength = Preferences().paintingLength, lineArt: LineArtSettings = LineArtSettings(),
        previewStyle: PreviewStyle = Preferences().previewStyle
    ) {
        self.paintingLength = paintingLength
        self.previewStyle = previewStyle
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

    /// Refine can open: it draws on the final template, because its edits are in the canvas units
    /// of the template it is shown and are laid unscaled on whichever template is made next (a
    /// draft's canvas is smaller than the full one's, and a Detail change moves the full one's).
    var canRefine: Bool { !isChoosingSettings && isFinal }

    /// Refine can be tapped: it opens now (`canRefine`), or as soon as the final template is made
    /// (`askForRefine()`), which a full-resolution generation takes tens of seconds to do on a
    /// phone. Not while the photo's settings are chosen, nor after a generation failed (the status
    /// says so): no final template is on its way then.
    var canAskForRefine: Bool {
        if canRefine { return true }
        guard source != nil, !isChoosingSettings else { return false }
        if case .failed = phase { return false }
        return true
    }

    /// Refine was tapped and waits for the final template.
    var isWaitingToRefine: Bool { refineAsked && !canRefine }

    /// Refine, asked for earlier, can open: the final template is made. (A thumb on a slider has
    /// called the wait off already, `setAdjusting`; `isAdjusting` is no part of this, as a drag
    /// whose end never came would keep Refine from opening for good.)
    var opensRefine: Bool { refineAsked && canRefine }

    /// A tap on Refine before the final template is made: Refine opens when it is, unless the
    /// painter goes back to the sliders (`setAdjusting`), starts the painting or changes the photo
    /// first.
    func askForRefine() {
        guard !canRefine, canAskForRefine else { return }
        refineAsked = true
        trace("Refine asked for")
    }

    /// Refine opened, or is not wanted any more.
    func withdrawRefine() {
        refineAsked = false
        trace("Refine opens")
    }

    /// The preview matches the settings and refinements at full resolution.
    var isFinal: Bool {
        guard let preview else { return false }
        return !preview.isDraft && preview.settings == settings && preview.refinements == refinements
    }

    /// The lines of text the app found in the photo, for Refine to show; none for classic line art.
    var foundText: [[SIMD2<Float>]] { lineArtInput?.writing ?? [] }

    /// Whether the template draws from the line-art inputs, where lines can be drawn and erased
    /// and the text corrections apply.
    var hasLineArtInput: Bool { lineArtInput != nil }

    /// Takes refinements as they are: a change to the generator's inputs makes the template again
    /// at full resolution (Refine shows what the painter did over the last full template until the
    /// new one has it, so a draft would only coarsen the lines meanwhile); a change to the edits
    /// alone lays them on the template on screen, without generating (`converge`).
    func refine(_ refinements: TemplateRefinements) {
        if take(refinements) { enqueue { [self] in await converge() } }
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

    /// Picks up a draft (`Drafts`): its photo, title and refinements, with the settings the
    /// painter left on the sliders. The suggestion is still made, for Reset to Suggested and the
    /// sliders' detents, but the draft's settings are the ones generated.
    func load(draft: CreateDraft, photo: Data) {
        begin(defaultTitle: draft.defaultTitle, sampleName: draft.sampleName, resuming: draft) {
            try await Self.decode(data: photo)
        }
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
        refinements = TemplateRefinements()
        made = []
        // A generation still finishing belonged to the photo that is gone.
        loadID += 1
        forgetEdits()
        phase = .failed(error.localizedDescription)
    }

    private func begin(
        defaultTitle: String, sampleName: String?, resuming saved: CreateDraft? = nil,
        decode: @escaping () async throws -> Decoded
    ) {
        cancelAll()
        // A new photo gets a new default name, and anything typed for the last one goes.
        self.defaultTitle = defaultTitle
        title = saved?.title ?? ""
        photoID = saved?.photoID ?? UUID()
        source = nil
        preview = nil
        stats = nil
        importance = nil
        lineArtInput = nil
        draftImage = nil
        decision = nil
        settingsOrigin = nil
        refinements = saved?.refinements ?? TemplateRefinements()
        made = []
        forgetEdits()
        progress = 0
        phase = .loading
        loadID += 1
        let load = loadID
        let preference = paintingLength
        let lineArt = baseLineArt
        // A suggestion's candidates have no edge map: as line art the first would be every edge
        // between its regions, which the painting won't draw, so line art waits for the winner.
        // Nor does a draft show the suggestion: the painter's settings are what it generates.
        let firstDraft: (@Sendable (Preview) -> Void)? =
            previewStyle == .painting && saved == nil ? Self.firstDraftHandler(for: self, load: load) : nil
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
                        lineArt: lineArt, maxCandidates: Self.maxCandidates, firstDraft: firstDraft)
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    // Without a suggestion the photo still gets a template, on the sliders' settings.
                    Log.create.error("Choosing settings failed: \(String(describing: error), privacy: .public)")
                    chosen = nil
                }
                try Task.checkCancellation()
                if let saved {
                    resume(saved, suggestion: chosen)
                } else if let chosen {
                    adopt(chosen)
                } else {
                    phase = .ready
                    startGeneration(draftFirst: true)
                }
            } catch is CancellationError {
            } catch {
                Log.create.error("Loading photo failed: \(String(describing: error), privacy: .private)")
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
        trace("Settings changed to \(settings.colorCount) colors, detail \(settings.detail), lines \(lines)")
        if let decision { settingsOrigin = settings == decision.settings ? .suggested : .custom }
        if isAdjusting {
            requestDraft()
            scheduleFull(after: Self.restDelay)
        } else {
            scheduleFull(after: .milliseconds(250))
        }
    }

    /// A slider drag began or ended. A touch cancels nothing: the first setting it changes
    /// (`settingsChanged`) supersedes the full resolution under way, and one that changes none
    /// leaves it be.
    func setAdjusting(_ adjusting: Bool) {
        // Back to the sliders: a Refine tapped while the painting was updating is not wanted now,
        // whether or not the last drag's end was heard.
        if adjusting { refineAsked = false }
        guard adjusting != isAdjusting else { return }
        isAdjusting = adjusting
        trace(adjusting ? "A slider was touched" : "A slider was let go")
        if !adjusting {
            stopDrafts()
            // The resting thumb's full resolution, already under way for these settings, carries on;
            // otherwise the settings let go on get theirs, so the painter is never left with a draft.
            if !isFinal, !(isMakingFull && refining == settings) { scheduleFull(after: .milliseconds(60)) }
        }
    }

    /// A full-resolution generation is under way and not cancelled (`refining` alone also holds
    /// for one cancelled and still unwinding).
    private var isMakingFull: Bool { refining != nil && fullTask?.isCancelled == false }

    /// A line of the app's log (`ci/collect.sh` keeps its category) with the state the generation
    /// is in: what a preview that stays off, or goes off again, is diagnosed from.
    private func trace(_ event: String) {
        let phaseName = String(describing: self.phase)
        Log.create.notice(
            "\(event, privacy: .public) [adjusting \(self.isAdjusting, privacy: .public), full under way \(self.refining != nil, privacy: .public), final \(self.isFinal, privacy: .public), phase \(phaseName, privacy: .public)]"
        )
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
        refineQueue?.cancel()
        stopDrafts()
        refineAsked = false
    }

    /// The full-resolution template for the current settings, generating it if needed.
    func makeDraft() async throws -> ArtworkDraft {
        // Starting the painting leaves no Refine to open over it.
        refineAsked = false
        // Settings still being chosen are chosen first, and the edits sent are laid.
        _ = await loadTask?.value
        _ = await refineQueue?.value
        guard let source else { throw CreateError.unreadable }
        let settings = self.settings
        if !isFinal {
            fullTask?.cancel()
            stopDrafts()
            await generate(draft: false, settings: settings)
        }
        guard let preview, !preview.isDraft, preview.settings == settings, preview.refinements == refinements else {
            throw CreateError.renderFailed
        }
        return ArtworkDraft(
            title: resolvedTitle, template: preview.template, settings: settings, settingsOrigin: settingsOrigin,
            paintingLength: decision?.preference, photo: source.preview, sampleName: source.sampleName,
            refinements: refinements)
    }

    /// What the making-of show of `draft` (the painting Start saved, as `artworkID`) is made from:
    /// this photo and the generator inputs its base was made with, so making the base again with an
    /// observer gives its stage pictures, and the painting's own template. Seeded by the artwork, so
    /// a painting's show is the same each time it is made.
    func makingOfSource(for draft: ArtworkDraft, artworkID: UUID) -> MakingOfSource? {
        guard let source else { return nil }
        return MakingOfSource(
            image: source.image, importance: importance, lineArt: lineArtInput, refinements: draft.refinements,
            settings: draft.settings, template: draft.template, photo: source.preview,
            seed: ColorNickname.seed(for: artworkID))
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

    /// Puts a draft's settings on the sliders and generates them with its refinements at full
    /// resolution. The suggestion is kept (nil if it failed), so the chip says whether the
    /// draft's settings are still it.
    private func resume(_ saved: CreateDraft, suggestion: AutoDecision?) {
        decision = suggestion
        apply(saved.settings)
        lines = saved.lines
        if let suggestion { settingsOrigin = settings == suggestion.settings ? .suggested : .custom }
        phase = .generating
        startGeneration(draftFirst: false)
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
        let load = loadID
        let kind = draft ? "Draft" : "Full"
        trace("\(kind) #\(id) started for \(settings.colorCount) colors, detail \(settings.detail), lines \(lines)")
        let input = draft ? (draftImage ?? source.image) : source.image
        if !draft {
            phase = .generating
            progress = 0
            refining = settings
            refiningID = id
        }
        defer { if !draft, refiningID == id { refining = nil } }
        // Called on pipeline threads; hops to the main actor. Only the full resolution reports, and
        // a draft starting beside it must not stop its progress (`generation` counts drafts too).
        let report: @Sendable (Float) -> Void = { value in
            Task { @MainActor in
                guard self.refiningID == id else { return }
                self.progress = Double(value)
            }
        }
        do {
            #if DEBUG
            if !draft, let delay = DemoMode.fullResolutionDelay { try await Task.sleep(for: delay) }
            #endif
            let refinements = self.refinements
            let inputs = refinements.generatorInputs
            var shown: Shown
            if !draft, let earlier = made.first(where: { $0.settings == settings && $0.refinements == inputs }) {
                shown = try await Self.laid(earlier.template, settings: settings, refinements: refinements, style: previewStyle)
            } else {
                let used = draft ? Self.draftSettings(settings, draft: input, source: source.image) : settings
                shown = try await Self.render(
                    input, importance: importance, lineArt: lineArtInput, refinements: refinements,
                    aspect: Float(source.image.width) / Float(source.image.height), settings: used, recorded: settings,
                    isDraft: draft, style: previewStyle, progress: draft ? nil : report)
            }
            // Kept even if cancelled meanwhile: it is what these settings and inputs make of this
            // photo, not of the one that replaced it (`made` was cleared for that one).
            if load == loadID, let base = shown.trail?.base { remember(base, settings: settings, refinements: inputs) }
            try Task.checkCancellation()
            // A draft finishing after a newer generation began (the resting thumb's full
            // resolution) would replace it with less, and one finishing after the full resolution
            // of the sliders' settings is shown would take it back: Refine would never open.
            if draft, generation != id || isFinal {
                trace("Draft #\(id) dropped")
                return
            }
            // Edits sent while this was being made are laid before it shows, so it never takes
            // one back.
            var left = shown.replay.left
            while let trail = shown.trail, self.refinements.edits != shown.preview.refinements.edits {
                guard self.refinements.generatorInputs == inputs else { return }
                shown = try await Self.follow(trail, to: self.refinements, settings: settings, style: previewStyle)
                left += shown.replay.left
                try Task.checkCancellation()
            }
            // Drafts follow the finger as they come: a crossfade would blur one into the next.
            withAnimation(draft ? nil : .easeInOut(duration: 0.35)) {
                preview = shown.preview
                if !draft { stats = Stats(shown.preview.template) }
            }
            if let current = shown.trail {
                trail = current
                trailKey = BaseKey(settings: settings, inputs: inputs)
                settledEdits = handledEdits
                // Told once: not again while the same edits stay out.
                if left != leftOutEdits, left > 0 { say(.left(left)) }
                leftOutEdits = left
            }
            trace("\(kind) #\(id) shown")
            // Ready with the newest full resolution, or with a draft when none is under way: the
            // status goes on saying "Updating…" while a draft shows beside the full resolution.
            if draft {
                if generation == id, !isMakingFull { phase = .ready }
            } else if refiningID == id {
                phase = .ready
            }
        } catch is CancellationError {
            trace("\(kind) #\(id) cancelled")
        } catch {
            Log.create.error("Generation failed: \(String(describing: error), privacy: .public)")
            // No final template is on its way: a Refine waiting for it would wait for ever.
            refineAsked = false
            phase = .failed(CreateError.renderFailed.localizedDescription)
        }
    }

    /// Keeps a full-resolution base template (made with the generator inputs `refinements`) for
    /// stepping back to it.
    private func remember(_ template: Template, settings: GenerationSettings, refinements: TemplateRefinements) {
        made.removeAll { $0.settings == settings && $0.refinements == refinements }
        made.insert(Made(settings: settings, refinements: refinements, template: template), at: 0)
        if made.count > Self.madeKept { made.removeLast(made.count - Self.madeKept) }
    }

    // MARK: Refine

    // The painter's changes in Refine are made one after another, in the order they were sent
    // (`enqueue`), each from the state the ones before it left:
    //
    // - An edit (`edit(_:)`, `fill(at:color:)`) is laid on the template on screen off the main
    //   actor (`EditTrail`: tens of milliseconds, no regeneration) and shows at once, without a
    //   crossfade. An edit that is declined (`EditTrail.Verdict.declined`) or has nothing to
    //   change changes nothing: it is not kept, takes no step of the history, and a declined one
    //   says so (`note`). A shape a line closed that has no room for a number is cut off by nothing,
    //   but the line stays, and says so.
    // - A brush or a correction of the text (`change(_:)`), and every Undo, Redo and Cancel that
    //   crosses one, changes the generator's inputs: the base is made again (`startGeneration`) and
    //   the edits are laid on it, those that no longer fit left out and counted (`note`). The
    //   sliders do the same with the settings. A base made before is reused (`made`).
    // - While the base is being made again, an edit is kept with the others and the new template
    //   has it laid before it shows (`generate`).
    //
    // `settledEdits` says which edits sent the template on screen already shows, so Refine draws
    // only the ones after it.

    /// How long a note stays up.
    static let noteDuration: Duration = .seconds(4)

    /// Lays a manual edit on the template on screen, in its turn. Returns its number: Refine draws
    /// the edit over the template until `settledEdits` reaches it.
    @discardableResult
    func edit(_ edit: TemplateEditor.Edit) -> Int {
        sentEdits += 1
        let serial = sentEdits
        enqueue { [self] in await lay(edit, serial: serial, tapped: false) }
        return serial
    }

    /// A tap of Fill. In an area a fill made it takes that fill out (the area goes back to what the
    /// drawing makes of it), anywhere else it fills the shape under `point` with `color` (OKLab).
    /// Numbered as `edit(_:)` is.
    @discardableResult
    func fill(at point: SIMD2<Float>, color: SIMD3<Float>) -> Int {
        sentEdits += 1
        let serial = sentEdits
        enqueue { [self] in await lay(.fill(at: point, color: color), serial: serial, tapped: true) }
        return serial
    }

    /// A brush or a correction of the text, in its turn.
    func change(_ change: RefineChange) {
        enqueue { [self] in
            var next = refinements
            change.apply(to: &next)
            guard next != refinements else { return }
            history.push(refinements)
            take(next)
        }
    }

    /// Takes back the newest change, in its turn.
    func undo() {
        enqueue { [self] in
            guard let previous = history.undo.popLast() else { return }
            history.redo.append(refinements)
            await settle(on: previous)
        }
    }

    /// Puts back the change taken back last.
    func redo() {
        enqueue { [self] in
            guard let next = history.redo.popLast() else { return }
            history.undo.append(refinements)
            await settle(on: next)
        }
    }

    var canUndo: Bool { !history.undo.isEmpty }
    var canRedo: Bool { !history.redo.isEmpty }

    /// Refine opened: its history starts here.
    func beginRefining() {
        enqueue { [self] in
            history = RefineHistory(opening: refinements)
            dismissNote()
        }
    }

    /// Refine's Cancel: back to what it opened with.
    func cancelRefining() {
        enqueue { [self] in
            let opening = history.opening
            history = RefineHistory(opening: opening)
            await settle(on: opening)
        }
    }

    func dismissNote() {
        noteTask?.cancel()
        note = nil
    }

    private func say(_ kind: RefineNote.Kind) {
        let next = RefineNote(kind: kind)
        note = next
        Announcer.announce(next.text)
        noteTask?.cancel()
        noteTask = Task {
            try? await Task.sleep(for: Self.noteDuration)
            guard !Task.isCancelled, note?.id == next.id else { return }
            note = nil
        }
    }

    /// Runs `work` after the changes enqueued before it, unless another photo has come since.
    private func enqueue(_ work: @escaping @MainActor @Sendable () async -> Void) {
        let previous = refineQueue
        let epoch = refineEpoch
        refineQueue = Task {
            _ = await previous?.value
            guard epoch == refineEpoch else { return }
            await work()
        }
    }

    /// A new photo, or none: nothing of the last one's changes is left.
    private func forgetEdits() {
        refineEpoch += 1
        refineQueue = nil
        trail = nil
        trailKey = nil
        history = RefineHistory()
        sentEdits = 0
        handledEdits = 0
        leftOutEdits = 0
        settledEdits = 0
        dismissNote()
    }

    /// Takes `new` as the refinements. True when only the edits differ from the template on
    /// screen's and it should follow them (`converge`); a change to the generator's inputs makes
    /// the base again, and the edits with it.
    @discardableResult
    private func take(_ new: TemplateRefinements) -> Bool {
        guard new != refinements else { return false }
        let remake = new.generatorInputs != refinements.generatorInputs
        refinements = new
        guard source != nil, !isChoosingSettings else { return false }
        if remake {
            startGeneration(draftFirst: false)
            return false
        }
        return true
    }

    private func settle(on target: TemplateRefinements) async {
        if take(target) { await converge() }
    }

    /// The edit numbered `serial` has had its turn; `shown` when the template on screen shows
    /// what it did (or it did nothing).
    private func handled(_ serial: Int, shown: Bool = true) {
        handledEdits = serial
        if shown { settledEdits = serial }
    }

    /// Shows a template with its edits laid. No crossfade: an edit is there the moment it lands.
    private func show(_ shown: Shown) {
        preview = shown.preview
        stats = Stats(shown.preview.template)
        trail = shown.trail
    }

    /// Makes the template on screen the base with the edits of the current refinements laid: from
    /// the templates kept where they part from the ones laid now, so taking an edit back or
    /// putting it back lays nothing.
    private func converge() async {
        guard let current = trail, let key = trailKey, key == currentKey else { return }
        let target = refinements
        guard current.edits != target.edits || preview?.refinements != target else { return }
        do {
            let moved = try await Self.follow(current, to: target, settings: key.settings, style: previewStyle)
            // Another change is in line behind this one: it shows then.
            guard refinements == target, trailKey == key else { return }
            show(moved)
            settledEdits = handledEdits
        } catch is CancellationError {
        } catch {
            Log.create.error("Following the edits failed: \(String(describing: error), privacy: .public)")
        }
    }

    private func lay(_ edit: TemplateEditor.Edit, serial: Int, tapped: Bool) async {
        let before = refinements
        guard let current = trail, let key = trailKey, key == currentKey else {
            // The template on screen is being made again: it has the edit laid with the others.
            if before.edits.count < TemplateRefinements.maximumEdits {
                history.push(before)
                refinements.edits.append(edit)
            }
            handled(serial, shown: false)
            return
        }
        // A tap in an area a fill made takes that fill out, with any other that made it.
        if tapped, case .fill(let point, _) = edit {
            let cleared = EditFills.cleared(by: point, edits: before.edits, on: current.template)
            if !cleared.isEmpty {
                var next = before
                next.edits = before.edits.indices.filter { !cleared.contains($0) }.map { before.edits[$0] }
                history.push(before)
                await settle(on: next)
                handled(serial)
                return
            }
        }
        guard before.edits.count < TemplateRefinements.maximumEdits else {
            say(.init(declined: edit))
            handled(serial)
            return
        }
        var next = before
        next.edits.append(edit)
        do {
            let laid = try await Self.laying(edit, on: current, settings: key.settings, refinements: next, style: previewStyle)
            guard refinements == before, trailKey == key else {
                // Something else changed the refinements meanwhile: the edit joins them.
                history.push(refinements)
                refinements.edits.append(edit)
                await converge()
                handled(serial)
                return
            }
            switch laid.verdict {
            case .made(let tooSmall):
                history.push(before)
                refinements = next
                if let preview = laid.preview { show(Shown(preview: preview, trail: laid.trail)) }
                handled(serial)
                if tooSmall { say(.tooSmall) }
            case .nothing:
                handled(serial)
            case .declined(let why):
                Log.create.info("An edit was declined: \(why, privacy: .public)")
                say(.init(declined: edit))
                handled(serial)
            }
        } catch {
            if !(error is CancellationError) {
                Log.create.error("Laying an edit failed: \(String(describing: error), privacy: .public)")
            }
            handled(serial)
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
    /// sets the canvas the painting time is estimated for. `firstDraft` gets the first candidate,
    /// painted.
    @concurrent
    private static func suggest(
        _ prepared: Prepared, sourceSize: (width: Int, height: Int), preference: PaintingLength,
        lineArt: LineArtSettings, maxCandidates: Int,
        firstDraft: (@Sendable (Preview) -> Void)?
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
                guard let firstDraft,
                      let preview = try? Self.makePreview(
                        output.template, settings: nil, refinements: TemplateRefinements(), isDraft: true, style: .painting)
                else { return }
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

    /// A preview, with the trail its template came from: the base the generator made and the
    /// edits laid on it (none for a draft, which has no edits), and what laying them did.
    nonisolated struct Shown: Sendable {
        var preview: Preview
        var trail: EditTrail?
        var replay = EditTrail.Replay()
    }

    /// The template of `settings` made from the generator inputs of `refinements` (`aspect`: the
    /// photo's width over height), with its edits laid unless it is a draft, its preview recording
    /// `recorded` (the sliders' settings a draft stands for).
    @concurrent
    private static func render(
        _ image: RGBAImage, importance: PaintCore.Grid<Float>?, lineArt: LineArtInput?, refinements: TemplateRefinements,
        aspect: Float, settings: GenerationSettings, recorded: GenerationSettings, isDraft: Bool, style: PreviewStyle,
        progress: (@Sendable (Float) -> Void)?
    ) async throws -> Shown {
        let inputs = refinements.refining(importance: importance, lineArt: lineArt, aspect: aspect)
        let template = try TemplateGenerator(settings: settings)
            .generate(from: image, importance: inputs.importance, lineArt: inputs.lineArt, cancel: .task, progress: progress)
            .template
        try Task.checkCancellation()
        return try composed(template, settings: recorded, refinements: refinements, isDraft: isDraft, style: style)
    }

    /// A base template made earlier, with the edits of `refinements` laid on it and drawn again.
    @concurrent
    private static func laid(
        _ base: Template, settings: GenerationSettings, refinements: TemplateRefinements, style: PreviewStyle
    ) async throws -> Shown {
        try composed(base, settings: settings, refinements: refinements, isDraft: false, style: style)
    }

    nonisolated private static func composed(
        _ base: Template, settings: GenerationSettings, refinements: TemplateRefinements, isDraft: Bool, style: PreviewStyle
    ) throws -> Shown {
        guard !isDraft else {
            return Shown(preview: try makePreview(base, settings: settings, refinements: refinements, isDraft: true, style: style))
        }
        var trail = EditTrail(base: base)
        let replay = try trail.move(to: refinements.edits, cancel: .task)
        try Task.checkCancellation()
        let preview = try makePreview(trail.template, settings: settings, refinements: refinements, isDraft: false, style: style)
        return Shown(preview: preview, trail: trail, replay: replay)
    }

    /// `trail` with its edits made those of `refinements` and the result drawn (a list taken back,
    /// put back or changed in the middle; edits sent while a template was being made).
    @concurrent
    private static func follow(
        _ trail: EditTrail, to refinements: TemplateRefinements, settings: GenerationSettings, style: PreviewStyle
    ) async throws -> Shown {
        var trail = trail
        let replay = try trail.move(to: refinements.edits, cancel: .task)
        try Task.checkCancellation()
        let preview = try makePreview(trail.template, settings: settings, refinements: refinements, isDraft: false, style: style)
        return Shown(preview: preview, trail: trail, replay: replay)
    }

    /// One edit laid on `trail`, and the result drawn when it changed the template.
    nonisolated struct Laid: Sendable {
        var trail: EditTrail
        var verdict: EditTrail.Verdict
        var preview: Preview?
    }

    /// `edit` laid on `trail`; `refinements` are the ones the template will have been made with,
    /// the edit among them.
    @concurrent
    private static func laying(
        _ edit: TemplateEditor.Edit, on trail: EditTrail, settings: GenerationSettings, refinements: TemplateRefinements,
        style: PreviewStyle
    ) async throws -> Laid {
        var trail = trail
        let verdict = trail.add(edit)
        guard verdict.isMade else { return Laid(trail: trail, verdict: verdict, preview: nil) }
        try Task.checkCancellation()
        let preview = try makePreview(trail.template, settings: settings, refinements: refinements, isDraft: false, style: style)
        return Laid(trail: trail, verdict: verdict, preview: preview)
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

    nonisolated private static func makePreview(
        _ template: Template, settings: GenerationSettings?, refinements: TemplateRefinements, isDraft: Bool,
        style: PreviewStyle
    ) throws -> Preview {
        #if DEBUG
        // Debug builds (CI's simulator runs) check every final template's invariants,
        // legible numbers included.
        if !isDraft {
            let report = template.validate(minLabelRadius: LabelSizing.minimumRadius)
            if !report.isValid { assertionFailure("Generated template violates its invariants: \(report)") }
        }
        #endif
        let drawing = LineArtDrawing(template)
        let picture: Picture
        switch style {
        case .painting:
            let long = max(template.width, template.height)
            guard let painting = TemplateRasterizer.image(template, style: .painting, maxPixelSize: long) else {
                throw CreateError.renderFailed
            }
            picture = .painting(painting)
        case .lineArt:
            picture = .lineArt(drawing)
        }
        return Preview(
            template: template, picture: picture, drawing: drawing, settings: settings, refinements: refinements,
            isDraft: isDraft)
    }

    private static func photoTitle() -> String {
        Date.now.formatted(.dateTime.month(.wide).day())
    }
}
