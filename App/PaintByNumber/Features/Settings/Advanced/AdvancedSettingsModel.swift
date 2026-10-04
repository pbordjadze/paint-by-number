import CoreGraphics
import Foundation
import Observation
import os
import PaintCore
import SwiftUI

/// Drives Settings › Advanced: the three groups of advanced settings, stored as the painter
/// changes them, and the live preview that shows what they do.
///
/// The preview is a picture (a library picture or the painter's most recent photo) at the
/// draft size, on the settings Suggested settings choose for it, with the advanced settings on
/// top. Settings that change templates queue a generation: the first change waits a moment
/// (`debounce`), and while one generation runs, further changes only move the target, so the
/// preview keeps up with a dragged slider at the pipeline's own pace and the last result stays
/// on screen until the next is ready. Every template made is kept for a while (`keptPreviews`),
/// so flipping a switch back shows its preview at once.
///
/// Each changed setting shows its effect: the preview's numbers against the same settings with
/// that one back at its default. Those reference templates are generated once the painter
/// pauses (`settle`), the setting changed last first; one that was at its default before the
/// change needs none, since the preview before the change is its reference.
@Observable
final class AdvancedSettingsModel {
    nonisolated enum Picture: Hashable, Sendable {
        /// A bundled picture, by `Sample.id`.
        case sample(String)
        /// The stored photo of an artwork.
        case photo(UUID)

        var storageValue: String {
            switch self {
            case .sample(let id): "sample:\(id)"
            case .photo(let id): "photo:\(id.uuidString)"
            }
        }

        init?(storageValue: String) {
            if storageValue.hasPrefix("sample:") {
                self = .sample(String(storageValue.dropFirst("sample:".count)))
            } else if storageValue.hasPrefix("photo:"), let id = UUID(uuidString: String(storageValue.dropFirst("photo:".count))) {
                self = .photo(id)
            } else {
                return nil
            }
        }
    }

    /// The painter's newest painting made from their own photo.
    nonisolated struct RecentPhoto: Equatable, Sendable {
        let id: UUID
        let title: String
    }

    enum Phase: Equatable {
        case loading
        case ready
        case failed(String)
    }

    nonisolated struct Preview: Identifiable, Sendable {
        let id = UUID()
        let key: GenerationKey
        let template: Template
        let stats: AdvancedStats
    }

    /// What a setting does to the preview right now.
    enum Effect: Equatable {
        case atDefault
        /// Being measured; meanwhile the last measurement, if any.
        case measuring(AdvancedStats.Delta?)
        case measured(AdvancedStats.Delta)

        var delta: AdvancedStats.Delta? {
            switch self {
            case .atDefault: nil
            case .measuring(let delta): delta
            case .measured(let delta): delta
            }
        }
    }

    // MARK: Settings

    var lineArt: LineArtSettings {
        didSet {
            guard lineArt != oldValue else { return }
            save(lineArt, isDefault: lineArt == LineArtSettings(), forKey: SettingsKey.lineArt)
            generationSettingsChanged(lineArt: oldValue, tuning: tuning)
        }
    }

    var tuning: PipelineTuning {
        didSet {
            guard tuning != oldValue else { return }
            save(tuning, isDefault: tuning.isDefault, forKey: SettingsKey.pipelineTuning)
            generationSettingsChanged(lineArt: lineArt, tuning: oldValue)
        }
    }

    /// How layered lines are drawn: never changes a template, so it needs no generation.
    var appearance: LineAppearance {
        didSet {
            guard appearance != oldValue else { return }
            save(appearance, isDefault: appearance == .default, forKey: SettingsKey.lineAppearance)
        }
    }

    // MARK: Preview

    private(set) var picture: Picture
    private(set) var phase: Phase = .loading
    /// The template on screen; it lags behind the settings while the next one is made.
    private(set) var preview: Preview?
    /// The numbers of the picture at the default settings, which the stats compare with.
    private(set) var baseline: AdvancedStats?
    private(set) var effects: [AdvancedControl: Effect] = [:]
    /// The preview is behind the settings and a new one is on its way.
    private(set) var isUpdating = false
    /// Nothing is queued or running (demo scenarios wait for it).
    private(set) var isIdle = false
    /// The setting changed last: its effect is measured first.
    private(set) var activeControl: AdvancedControl?

    let paintingLength: PaintingLength
    let recentPhoto: RecentPhoto?

    var currentKey: GenerationKey { GenerationKey(lineArt: lineArt, tuning: tuning) }

    var pictureTitle: String {
        switch picture {
        case .sample(let id): Sample.named(id)?.title ?? id
        case .photo: recentPhoto?.title ?? ""
        }
    }

    /// The preview's numbers against the defaults'; nil until both exist.
    var statsDelta: AdvancedStats.Delta? {
        guard let stats = preview?.stats, let baseline else { return nil }
        return stats.delta(from: baseline)
    }

    var isLineArtDefault: Bool { lineArt == LineArtSettings() }
    var isAppearanceDefault: Bool { appearance == .default }
    var isTuningDefault: Bool { tuning.isDefault }

    // MARK: Internals

    /// The picture, prepared once: the photo (layered line art's edge map is made from it, once,
    /// by `LineArtInputs`), the draft, its importance map and the settings Suggested settings
    /// choose for it, which the advanced settings go on top of.
    nonisolated struct Base: Sendable {
        let photo: CGImage
        let draft: RGBAImage
        let importance: PaintCore.Grid<Float>?
        let settings: GenerationSettings
        /// Full-painting areas per draft area, from the suggestion's own estimate.
        let areaScale: Double
    }

    private enum Job {
        case generate(GenerationKey, isReference: Bool)
        case wait(Duration)
    }

    /// Before the first generation after a change: a few slider ticks travel together.
    static let debounce: Duration = .milliseconds(120)
    /// Effects are measured once the settings have been still this long.
    static let settle: Duration = .milliseconds(450)
    static let keptPreviews = 8

    let defaults: UserDefaults
    private let store: ArtworkStore?
    @ObservationIgnored private var base: Base?
    @ObservationIgnored private var stats: [GenerationKey: AdvancedStats] = [:]
    @ObservationIgnored private var previews: [GenerationKey: Preview] = [:]
    /// `previews` keys, least recently made first.
    @ObservationIgnored private var previewOrder: [GenerationKey] = []
    /// Keys whose generation failed for this picture: not tried again.
    @ObservationIgnored private var failed: Set<GenerationKey> = []
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var worker: Task<Void, Never>?
    /// Identifies the running worker, so one that was stopped leaves its successor alone.
    @ObservationIgnored private var workerID = 0
    @ObservationIgnored private var job: (key: GenerationKey, isReference: Bool, task: Task<Preview, any Error>)?
    @ObservationIgnored private var lastChange = ContinuousClock.now
    /// Identifies the picture being loaded, so a late result for an earlier one is dropped.
    @ObservationIgnored private var loadID = 0
    /// The `loadID` of the picture `preview` shows: an earlier picture's stays up, dimmed,
    /// until the new one's first template replaces it.
    @ObservationIgnored private var previewLoadID = -1

    private static let log = Logger(subsystem: "com.pbordjadze.paintbynumber", category: "advanced")

    /// - Parameters:
    ///   - picture: The picture to preview; by default the one chosen last, else the painter's
    ///     most recent photo, else the library's first picture.
    ///   - paintingLength: What the suggestion under the preview aims for (Settings › Painting Length).
    init(library: Library?, defaults: UserDefaults = .standard, picture: Picture? = nil, paintingLength: PaintingLength? = nil) {
        let preferences = Preferences(defaults: defaults)
        self.defaults = defaults
        store = library?.store
        lineArt = preferences.lineArt
        tuning = preferences.tuning
        appearance = preferences.lineAppearance
        self.paintingLength = paintingLength ?? preferences.paintingLength
        let recent = Self.recentPhoto(in: library)
        recentPhoto = recent
        let stored = defaults.string(forKey: SettingsKey.advancedPreviewPicture).flatMap(Picture.init(storageValue:))
            .flatMap { Self.isAvailable($0, recent: recent) ? $0 : nil }
        self.picture = picture ?? stored ?? recent.map { .photo($0.id) } ?? .sample(Sample.all.first?.id ?? "parrots")
        refreshEffects()
    }

    // MARK: Lifecycle

    /// Prepares the picture (once) and brings the preview up to date.
    func start() {
        if base == nil {
            if loadTask == nil { load(picture) }
        } else {
            scheduleWork(after: .zero)
        }
    }

    /// Stops all work (the screen went away); `start()` resumes it.
    func stop() {
        loadTask?.cancel()
        loadTask = nil
        worker?.cancel()
        worker = nil
        job?.task.cancel()
        job = nil
        updateStatus()
    }

    func choose(_ picture: Picture) {
        guard picture != self.picture || base == nil else { return }
        self.picture = picture
        defaults.set(picture.storageValue, forKey: SettingsKey.advancedPreviewPicture)
        load(picture)
    }

    // MARK: Changing settings

    /// A slider's setting.
    func value(of control: AdvancedControl) -> Double { control.value(lineArt: lineArt, tuning: tuning) }

    func valueText(of control: AdvancedControl) -> String { control.valueText(lineArt: lineArt, tuning: tuning) }

    /// A coloring book's line weight (Line Appearance), as the slider shows it.
    var coloringBookWeight: Double {
        get { Double(appearance.coloringBookWeight) }
        set { appearance.coloringBookWeight = Float(newValue) }
    }

    func isChanged(_ control: AdvancedControl) -> Bool { value(of: control) != control.defaultValue(for: lineArt.style) }

    /// Sets a slider's setting. The three thresholds push each other along, so texture ≤
    /// detail ≤ outline always holds and the sliders show what generation uses.
    func set(_ control: AdvancedControl, to value: Double) {
        let v = Float(value)
        var art = lineArt, tune = tuning
        switch control {
        case .outlineThreshold:
            art.outlineThreshold = v
            art.detailThreshold = min(art.detailThreshold, v)
            art.textureThreshold = min(art.textureThreshold, v)
        case .detailThreshold:
            art.detailThreshold = v
            art.outlineThreshold = max(art.outlineThreshold, v)
            art.textureThreshold = min(art.textureThreshold, v)
        case .textureThreshold:
            art.textureThreshold = v
            art.detailThreshold = max(art.detailThreshold, v)
            art.outlineThreshold = max(art.outlineThreshold, v)
        case .minimumStrokeLength: art.minimumStrokeLength = v
        case .gapBridging: art.gapBridging = v
        case .lineSmoothing: art.lineSmoothing = v
        case .smoothing: tune.smoothing = v
        case .textureFlattening: tune.textureFlattening = v
        case .minimumCellSize: tune.minimumCellSize = v
        case .subjectEmphasis: tune.subjectEmphasis = v
        case .accentColors: tune.accentColors = v
        case .colorfulness: tune.colorfulness = v
        case .style, .detector, .samePaint, .keepColorEdges, .outlineEyes, .outlineObjects: return
        }
        if activeControl != control { activeControl = control }
        lineArt = art
        tuning = tune
    }

    func reset(_ control: AdvancedControl) {
        var art = lineArt, tune = tuning
        control.reset(&art, &tune)
        if activeControl != control { activeControl = control }
        lineArt = art
        tuning = tune
    }

    func resetLineArt() { lineArt = LineArtSettings() }
    func resetAppearance() { appearance = .default }
    func resetTuning() { tuning = PipelineTuning() }

    func resetAll() {
        resetLineArt()
        resetAppearance()
        resetTuning()
    }

    func apply(_ preset: LineAppearancePreset) { appearance = preset.applied(to: appearance) }

    /// The preset of the whole screen the settings match, if any.
    var currentPreset: AdvancedPreset? { AdvancedPreset.matching(lineArt: lineArt, tuning: tuning, appearance: appearance) }

    func apply(_ preset: AdvancedPreset) { apply(preset.settings) }

    /// Takes on pasted settings (`AdvancedReport.settings(in:)`): every group the text had; the
    /// others stay as they are.
    func apply(_ imported: AdvancedReport.Imported) {
        if let art = imported.lineArt { lineArt = art }
        if let tune = imported.tuning { tuning = tune }
        if let look = imported.lineAppearance { appearance = look }
    }

    // MARK: Feedback

    /// Every setting that differs from its default, worded ("Smallest Area 2×"), after the
    /// preset they add up to, if any.
    var changes: [String] {
        var list: [String] = []
        // A preset other than the defaults names the style, so the style line is left out.
        let preset = currentPreset
        if let preset, preset != .defaults {
            list.append(Self.change(AdvancedText.presetTitle, preset.name))
        }
        for control in AdvancedControl.allCases
        where isChanged(control) && control.applies(to: lineArt.style) && (control != .style || preset == nil) {
            list.append(Self.change(control.title(for: lineArt.style), valueText(of: control)))
        }
        var layers = appearance
        layers.coloringBookWeight = LineAppearance.default.coloringBookWeight
        if layers != .default {
            let title = String(localized: "advanced.section.appearance", defaultValue: "Line Appearance",
                               comment: "Settings › Advanced: header of the section on how layered lines are drawn at each zoom")
            let value = LineAppearancePreset.matching(appearance)?.name
                ?? String(localized: "advanced.preset.custom", defaultValue: "Custom",
                          comment: "Settings › Advanced › Line Appearance: the layers' values match no preset; in shared settings text")
            list.append(Self.change(title, value))
            if appearance.weighted != LineAppearance.default.weighted {
                list.append(Self.change(AdvancedText.weightTitle, AdvancedText.onOff(appearance.weighted)))
            }
            for layer in LineLayer.allCases where appearance[layer].painted != LineAppearance.default[layer].painted {
                list.append(Self.change(AdvancedText.paintedTitle(of: layer), AdvancedText.percent(appearance[layer].painted)))
            }
        }
        if appearance.coloringBookWeight != LineAppearance.default.coloringBookWeight {
            list.append(Self.change(AdvancedText.coloringBookWeightTitle, AdvancedText.multiplier(Double(appearance.coloringBookWeight))))
        }
        return list
    }

    private static func change(_ title: String, _ value: String) -> String {
        String(localized: "advanced.report.change", defaultValue: "\(title) \(value)",
               comment: "Settings › Advanced: one changed setting in shared settings text, e.g. Smallest Area 2×; the arguments are the setting's name and its value")
    }

    /// The preview's numbers worded for the shared text, with their change from the defaults.
    var summary: String? {
        guard let stats = preview?.stats else { return nil }
        let numbers = String(
            localized: "advanced.report.numbers",
            defaultValue: "\(TemplateCounts.colors(stats.colors)) · \(TemplateCounts.areas(stats.areas)) · \(PaintingTime.approximate(stats.seconds))",
            comment: "Settings › Advanced: the preview's numbers in shared settings text, e.g. 24 colors · 1,284 areas · ~1 h; the arguments are the colors, areas and painting time")
        guard let delta = statsDelta, !delta.isZero else { return numbers }
        let effect = AdvancedText.effect(delta)
        return String(localized: "advanced.report.numbersWithChange", defaultValue: "\(numbers) (\(effect) from the defaults)",
                      comment: "Settings › Advanced: the preview's numbers and their change from the default settings in shared settings text; the arguments are the numbers and the change, e.g. +212 areas")
    }

    /// The text Copy Settings and Share with a Note hand over.
    func report(note: String = "") -> String {
        let snapshot = AdvancedReport.Snapshot(
            app: AppInfo().summary, picture: pictureID, paintingLength: paintingLength.rawValue, lineArt: lineArt,
            tuning: tuning, lineAppearance: appearance, preview: preview.map { .init($0.stats) },
            defaults: baseline.map { .init($0) })
        return AdvancedReport.text(snapshot: snapshot, pictureTitle: pictureTitle, summary: summary, changes: changes, note: note)
    }

    private var pictureID: String {
        switch picture {
        case .sample(let id): id
        case .photo: "photo"
        }
    }

    // MARK: Loading a picture

    private static func recentPhoto(in library: Library?) -> RecentPhoto? {
        guard let library else { return nil }
        return library.artworks
            .filter { $0.sampleName == nil && !$0.needsNewerApp && library.store.hasSource($0.id) }
            .max { $0.createdAt < $1.createdAt }
            .map { RecentPhoto(id: $0.id, title: $0.title) }
    }

    private static func isAvailable(_ picture: Picture, recent: RecentPhoto?) -> Bool {
        switch picture {
        case .sample(let id): Sample.named(id)?.url != nil
        case .photo(let id): recent?.id == id
        }
    }

    nonisolated private enum Source: Sendable {
        case file(URL)
        case artwork(UUID, ArtworkStore)
    }

    private func load(_ picture: Picture) {
        stop()
        loadID += 1
        let id = loadID
        base = nil
        baseline = nil
        stats = [:]
        previews = [:]
        previewOrder = []
        failed = []
        phase = .loading
        refreshEffects()
        updateStatus()
        let source: Source?
        switch picture {
        case .sample(let name): source = Sample.named(name)?.url.map(Source.file)
        case .photo(let artwork): source = store.map { Source.artwork(artwork, $0) }
        }
        let preference = paintingLength
        loadTask = Task {
            do {
                guard let source else { throw CreateModel.CreateError.unreadable }
                let prepared = try await Self.prepare(source, preference: preference)
                guard id == loadID else { return }
                base = prepared.base
                baseline = prepared.baseline.stats
                phase = .ready
                record(prepared.baseline, isReference: false)
                // Cleared only now and the worker started at once, so the model never looks idle
                // between the picture's first template and the work it still has.
                loadTask = nil
                scheduleWork(after: .zero)
            } catch is CancellationError {
            } catch {
                guard id == loadID else { return }
                loadTask = nil
                Self.log.error("Preparing the preview failed: \(String(describing: error), privacy: .public)")
                phase = .failed(CreateModel.CreateError.unreadable.localizedDescription)
                updateStatus()
            }
        }
    }

    /// Decodes the picture the way the create flow does, finds its subject and chooses its
    /// settings (the suggestion's center, at the draft size), then renders the preview at the
    /// default advanced settings like any other (the suggestion's own draft has no edge map,
    /// and the default lines draw from one).
    @concurrent
    private static func prepare(_ source: Source, preference: PaintingLength) async throws -> (base: Base, baseline: Preview) {
        let image: RGBAImage
        switch source {
        case .file(let url):
            image = try PhotoLoader.load(url: url, maxPixelSize: ArtworkStore.sourceMaxPixelSize)
        case .artwork(let id, let store):
            guard let photo = store.source(id, maxPixelSize: ArtworkStore.sourceMaxPixelSize) else {
                throw CreateModel.CreateError.unreadable
            }
            image = try PhotoLoader.rgbaImage(from: photo)
        }
        guard image.width >= 16, image.height >= 16, let photo = PhotoLoader.cgImage(from: image) else {
            throw CreateModel.CreateError.unreadable
        }
        try Task.checkCancellation()
        let subject = SubjectImportance.analyze(photo)
        try Task.checkCancellation()
        let draft = AutoSettings.draftImage(from: image)
        let decision = try AutoSettings.choose(
            image: draft, sourceSize: (image.width, image.height), importance: subject.map, hints: subject.hints,
            preference: preference, maxCandidates: 1, cancel: .task, firstDraft: nil)
        guard let score = decision.candidates.first?.score, score.regions > 0 else {
            throw CreateModel.CreateError.renderFailed
        }
        let scale = score.estimatedSeconds / PaintingTime.estimate(regionCount: score.regions)
        let base = Base(photo: photo, draft: draft, importance: subject.map, settings: decision.settings, areaScale: scale)
        return (base, try await render(.defaults, base: base))
    }

    @concurrent
    private static func render(_ key: GenerationKey, base: Base) async throws -> Preview {
        // As the create flow does: computed once per photo and cached; nil for classic lines.
        let input = try await LineArtInputs.forGeneration(of: base.photo, settings: key.lineArt, cached: true)
        let template = try TemplateGenerator(settings: key.settings(on: base.settings))
            .generate(from: base.draft, importance: base.importance, lineArt: input, cancel: .task)
            .template
        try Task.checkCancellation()
        return Preview(key: key, template: template, stats: AdvancedStats(template, areaScale: base.areaScale))
    }

    // MARK: Generation queue

    private func generationSettingsChanged(lineArt oldArt: LineArtSettings, tuning oldTuning: PipelineTuning) {
        let moved = AdvancedControl.allCases.filter {
            $0.value(lineArt: oldArt, tuning: oldTuning) != $0.value(lineArt: lineArt, tuning: tuning)
        }
        // A new style carries its own defaults along: the style is what moved.
        let active: AdvancedControl? = moved.contains(.style) ? .style : (moved.count == 1 ? moved[0] : nil)
        if let active, activeControl != active {
            activeControl = active
        }
        lastChange = .now
        if let cached = previews[currentKey] { show(cached) }
        // Measuring an effect of the settings before this change is no longer worth finishing first.
        if let job, job.isReference { job.task.cancel() }
        refreshEffects()
        scheduleWork(after: Self.debounce)
    }

    private func scheduleWork(after delay: Duration) {
        guard base != nil, worker == nil else {
            updateStatus()
            return
        }
        workerID += 1
        let id = workerID
        worker = Task {
            if delay > .zero { try? await Task.sleep(for: delay) }
            await runJobs(worker: id)
        }
        updateStatus()
    }

    private func runJobs(worker id: Int) async {
        while !Task.isCancelled, let base, let next = nextJob() {
            switch next {
            case .wait(let duration):
                try? await Task.sleep(for: duration)
            case let .generate(key, isReference):
                let task = Task { try await Self.render(key, base: base) }
                job = (key, isReference, task)
                updateStatus()
                let result = await task.result
                // A stopped worker resumes after its successor may have started a job of its own.
                if job?.task == task { job = nil }
                guard !Task.isCancelled else { return }
                switch result {
                case .success(let preview):
                    record(preview, isReference: isReference)
                case .failure(let error):
                    if error is CancellationError { continue }
                    Self.log.error("Preview generation failed: \(String(describing: error), privacy: .public)")
                    failed.insert(key)
                    refreshEffects()
                }
            }
        }
        // In the same main-actor turn as the last look at the queue: a change after it finds
        // no worker and starts one.
        if workerID == id { worker = nil }
        updateStatus()
    }

    /// The preview for the current settings first; then the references that measure what each
    /// changed setting does, once the painter pauses.
    private func nextJob() -> Job? {
        let key = currentKey
        if previews[key] == nil, !failed.contains(key) { return .generate(key, isReference: false) }
        var changed = AdvancedControl.allCases.filter { $0.isChanged(in: key) }
        if let active = activeControl, let index = changed.firstIndex(of: active) {
            changed.insert(changed.remove(at: index), at: 0)
        }
        guard let reference = changed.lazy.map({ $0.reset(key) }).first(where: { stats[$0] == nil && !failed.contains($0) })
        else { return nil }
        let quiet = ContinuousClock.now - lastChange
        if quiet < Self.settle { return .wait(Self.settle - quiet) }
        return .generate(reference, isReference: true)
    }

    private func record(_ result: Preview, isReference: Bool) {
        stats[result.key] = result.stats
        // References are kept too: moving a setting back to its default shows one at once.
        remember(result)
        // A step on the way while the painter is still moving a slider shows too, unless the
        // preview already matches the settings (they came back to a kept one).
        if !isReference, preview?.key != currentKey || previewLoadID != loadID { show(result) }
        refreshEffects()
        updateStatus()
    }

    private func remember(_ result: Preview) {
        previews[result.key] = result
        previewOrder.removeAll { $0 == result.key }
        previewOrder.append(result.key)
        while previews.count > Self.keptPreviews,
              let index = previewOrder.firstIndex(where: { $0 != .defaults && $0 != preview?.key && $0 != result.key }) {
            previews[previewOrder.remove(at: index)] = nil
        }
    }

    private func show(_ result: Preview) {
        guard preview?.id != result.id else { return }
        previewLoadID = loadID
        withAnimation(.easeInOut(duration: 0.25)) { preview = result }
        updateStatus()
    }

    private func refreshEffects() {
        let key = currentKey
        let current = stats[key]
        var next: [AdvancedControl: Effect] = [:]
        for control in AdvancedControl.allCases {
            guard control.isChanged(in: key) else {
                next[control] = .atDefault
                continue
            }
            if let current, let reference = stats[control.reset(key)] {
                next[control] = .measured(current.delta(from: reference))
            } else {
                next[control] = .measuring(effects[control]?.delta)
            }
        }
        if next != effects { effects = next }
    }

    private func updateStatus() {
        let behind = base != nil && (preview?.key != currentKey || previewLoadID != loadID)
        if isUpdating != behind { isUpdating = behind }
        let idle = phase != .loading && worker == nil && job == nil && loadTask == nil
        if isIdle != idle { isIdle = idle }
    }

    private func save<T: Encodable>(_ value: T, isDefault: Bool, forKey key: String) {
        // Defaults are not written down, so a later build's better defaults reach them.
        if isDefault {
            defaults.removeObject(forKey: key)
        } else {
            Preferences.store(value, forKey: key, in: defaults)
        }
    }
}
