import CoreGraphics
import Foundation
import Observation
import os
import PaintCore
import PhotosUI
import SwiftUI

/// Drives the create flow: holds the chosen photo and regenerates the template as the
/// settings change — quick reduced-size drafts while a slider is being dragged, the full
/// resolution once it settles — always discarding stale work.
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
        let settings: GenerationSettings
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

        var summary: String {
            "\(colors) colors · \(areas.formatted()) areas · \(PaintingTime.approximate(estimate))"
        }
    }

    enum Phase: Equatable {
        case idle
        case loading
        /// Finding the subject (Vision) before the first generation.
        case analyzing
        case generating
        case ready
        case failed(String)
    }

    nonisolated enum CreateError: LocalizedError {
        case unreadable, renderFailed

        var errorDescription: String? {
            switch self {
            case .unreadable: "This photo couldn’t be opened. Try another one."
            case .renderFailed: "The template couldn’t be created. Try different settings."
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

    /// Working long side of drafts (the generator upsamples small inputs up to 1.5×).
    nonisolated static let draftLongSide = 640.0

    @ObservationIgnored private var importance: PaintCore.Grid<Float>?
    @ObservationIgnored private var draftImage: RGBAImage?
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var fullTask: Task<Void, Never>?
    @ObservationIgnored private var draftTask: Task<Void, Never>?
    @ObservationIgnored private var draftToken = UUID()
    @ObservationIgnored private var draftPending = false
    @ObservationIgnored private var generation = 0

    init(initial: GenerationSettings = Preferences().initialGenerationSettings) {
        colorCount = Double(initial.colorCount)
        detail = Double(initial.detail)
        smoothness = Double(initial.smoothness)
    }

    var settings: GenerationSettings {
        GenerationSettings(colorCount: Int(colorCount.rounded()), detail: Float(detail), smoothness: Float(smoothness)).normalized
    }

    var isWorking: Bool {
        switch phase {
        case .loading, .analyzing, .generating: true
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

    func load(imageData: Data) {
        begin(defaultTitle: Self.photoTitle(), sampleName: nil) { try await Self.decode(data: imageData) }
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
        draftImage = nil
        progress = 0
        phase = .loading
        loadTask = Task {
            do {
                let decoded = try await decode()
                try Task.checkCancellation()
                source = Source(image: decoded.image, preview: decoded.preview, sampleName: sampleName)
                phase = .analyzing
                let prepared = await Self.prepare(decoded)
                try Task.checkCancellation()
                importance = prepared.importance
                draftImage = prepared.draft
                // A quick draft first so something appears at once, then the real thing.
                // Runs as the cancellable full-resolution job so setting changes supersede it.
                fullTask = Task {
                    await generate(draft: true, settings: settings)
                    guard !Task.isCancelled else { return }
                    await generate(draft: false, settings: settings)
                }
            } catch is CancellationError {
            } catch {
                Log.create.error("Loading photo failed: \(String(describing: error), privacy: .public)")
                phase = .failed((error as? CreateError ?? .unreadable).localizedDescription)
            }
        }
    }

    // MARK: Adjusting

    /// Call when any setting changed.
    func settingsChanged() {
        guard source != nil, phase != .loading, phase != .analyzing else { return }
        if isAdjusting {
            requestDraft()
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
            scheduleFull(after: .milliseconds(60))
        }
    }

    func cancelAll() {
        loadTask?.cancel()
        loadTask = nil
        fullTask?.cancel()
        stopDrafts()
    }

    /// The full-resolution template for the current settings, generating it if needed.
    func makeDraft() async throws -> ArtworkDraft {
        guard let source else { throw CreateError.unreadable }
        let settings = self.settings
        if !isFinal {
            fullTask?.cancel()
            stopDrafts()
            await generate(draft: false, settings: settings)
        }
        guard let preview, !preview.isDraft, preview.settings == settings else { throw CreateError.renderFailed }
        return ArtworkDraft(
            title: resolvedTitle, template: preview.template, settings: settings,
            photo: source.preview, sampleName: source.sampleName)
    }

    private func requestDraft() {
        fullTask?.cancel()
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
        }
        // Called on pipeline threads; hops to the main actor.
        let report: @Sendable (Float) -> Void = { value in
            Task { @MainActor in
                guard self.generation == id else { return }
                self.progress = Double(value)
            }
        }
        do {
            let result = try await Self.render(
                input, importance: importance, settings: settings, isDraft: draft, progress: draft ? nil : report)
            try Task.checkCancellation()
            withAnimation(.easeInOut(duration: draft ? 0.18 : 0.35)) {
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

    nonisolated struct Decoded: Sendable {
        var image: RGBAImage
        var preview: CGImage
    }

    nonisolated struct Prepared: Sendable {
        var importance: PaintCore.Grid<Float>?
        var draft: RGBAImage
    }

    @concurrent
    private static func decode(url: URL) async throws -> Decoded {
        try decoded(PhotoLoader.load(url: url, maxPixelSize: ArtworkStore.sourceMaxPixelSize))
    }

    @concurrent
    private static func decode(data: Data) async throws -> Decoded {
        try decoded(PhotoLoader.load(data: data, maxPixelSize: ArtworkStore.sourceMaxPixelSize))
    }

    nonisolated private static func decoded(_ image: RGBAImage) throws -> Decoded {
        guard image.width >= 16, image.height >= 16, let preview = PhotoLoader.cgImage(from: image) else {
            throw CreateError.unreadable
        }
        return Decoded(image: image, preview: preview)
    }

    /// Subject importance (once per photo) and the reduced photo for drafts.
    @concurrent
    private static func prepare(_ decoded: Decoded) async -> Prepared {
        let importance = SubjectImportance.map(for: decoded.preview)
        let image = decoded.image
        let long = Double(max(image.width, image.height))
        let scale = min(1, draftLongSide / 1.5 / long)
        let draft = scale < 1
            ? Resample.area(image, width: max(1, Int(Double(image.width) * scale)), height: max(1, Int(Double(image.height) * scale)))
            : image
        return Prepared(importance: importance, draft: draft)
    }

    @concurrent
    private static func render(
        _ image: RGBAImage, importance: PaintCore.Grid<Float>?, settings: GenerationSettings, isDraft: Bool,
        progress: (@Sendable (Float) -> Void)?
    ) async throws -> Preview {
        let template = try TemplateGenerator(settings: settings)
            .generate(from: image, importance: importance, cancel: .task, progress: progress)
            .template
        try Task.checkCancellation()
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
