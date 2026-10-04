import CoreGraphics
import Foundation
import os
import PaintCore

/// What layered and coloring-book line art draw from, computed once per photo: the line
/// drawing over the HED edge map (`EdgeDetector.combinedMap`) and the eyes (`EyeFinder`).
///
/// Inputs are cached by the photo's identity (the same `CGImage` instance) for the last
/// `cacheCapacity` photos, so the create flow's drafts, candidates and full resolution, and a
/// preview regenerating as settings move, run the model once per photo. Concurrent requests
/// for one photo share a single computation, which is cancelled once every task waiting for
/// it is (a cancelled caller still waiting alongside others gets the result when it comes).
nonisolated enum LineArtInputs {
    /// Photos whose inputs are kept: the photo being made into a painting and a preview's.
    static let cacheCapacity = 2

    /// The inputs `settings` need for `image`: nil for classic line art, which draws from the
    /// photo alone.
    static func make(for image: CGImage, settings: LineArtSettings) async throws -> LineArtInput? {
        guard settings.style.usesEdgeMap else { return nil }
        return try await cache.input(for: image)
    }

    /// The inputs for a template about to be generated: `make` (or `compute` when not
    /// `cached`, for a one-off template), except that a failure other than cancellation is
    /// logged and gives nil, so a layered or coloring-book template comes out classic, as the
    /// generator documents, rather than not at all. Nil for classic settings.
    static func forGeneration(of image: CGImage?, settings: LineArtSettings, cached: Bool) async throws -> LineArtInput? {
        guard settings.style.usesEdgeMap else { return nil }
        guard let image else {
            Log.create.error("Line art without a photo image: generating classic lines")
            return nil
        }
        do {
            if cached { return try await cache.input(for: image) }
            return try await compute(for: image)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            Log.create.error("Line art inputs failed: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    /// The inputs of `image`, computed now without the cache: the combined map (both models,
    /// one after the other) and, meanwhile, the eyes.
    @concurrent
    static func compute(for image: CGImage) async throws -> LineArtInput {
        async let eyes = findEyes(in: image)
        let edges = try EdgeDetector.combinedMap(for: image)
        return LineArtInput(edges: edges, eyes: await eyes)
    }

    @concurrent
    private static func findEyes(in image: CGImage) async -> [[SIMD2<Float>]] {
        EyeFinder.eyes(in: image)
    }

    private static let cache = InputCache()
}

/// The cache behind `LineArtInputs.make`: one computation task per photo, shared by the
/// callers waiting for it.
private actor InputCache {
    private nonisolated struct Entry {
        let image: CGImage
        let task: Task<LineArtInput, any Error>
        /// Callers waiting for `task`, and those of them whose own tasks were cancelled.
        var waiting: Set<UUID> = []
        var abandoned: Set<UUID> = []
    }

    /// Least recently requested first.
    private var entries: [Entry] = []

    func input(for image: CGImage) async throws -> LineArtInput {
        let caller = UUID()
        let task = join(image, as: caller)
        defer { leave(task, as: caller) }
        do {
            return try await withTaskCancellationHandler {
                try await task.value
            } onCancel: {
                Task { await self.abandon(task, as: caller) }
            }
        } catch {
            // A failed or cancelled computation isn't kept: the next request starts afresh.
            entries.removeAll { $0.task == task }
            throw error
        }
    }

    /// The running or finished computation for `image`, or a new one when there is none (or
    /// only a cancelled one).
    private func join(_ image: CGImage, as caller: UUID) -> Task<LineArtInput, any Error> {
        var entry: Entry
        if let index = entries.firstIndex(where: { $0.image === image }), !entries[index].task.isCancelled {
            entry = entries.remove(at: index)
        } else {
            entries.removeAll { $0.image === image }
            entry = Entry(image: image, task: Task { try await LineArtInputs.compute(for: image) })
        }
        entry.waiting.insert(caller)
        entries.append(entry)
        trim()
        return entry.task
    }

    private func leave(_ task: Task<LineArtInput, any Error>, as caller: UUID) {
        guard let index = entries.firstIndex(where: { $0.task == task }) else { return }
        entries[index].waiting.remove(caller)
        entries[index].abandoned.remove(caller)
    }

    /// A caller's task was cancelled: the computation stops when nobody else waits for it.
    private func abandon(_ task: Task<LineArtInput, any Error>, as caller: UUID) {
        guard let index = entries.firstIndex(where: { $0.task == task }), entries[index].waiting.contains(caller) else { return }
        entries[index].abandoned.insert(caller)
        if entries[index].abandoned == entries[index].waiting { task.cancel() }
    }

    /// Drops the least recently requested photos beyond the capacity that nobody waits for,
    /// cancelling their computations if they are still running.
    private func trim() {
        var index = 0
        while entries.count > LineArtInputs.cacheCapacity, index < entries.count - 1 {
            if entries[index].waiting.isEmpty {
                entries.remove(at: index).task.cancel()
            } else {
                index += 1
            }
        }
    }
}
