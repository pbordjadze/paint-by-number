import Foundation
import Observation
import os
import PaintCore

/// The length chip's other Painting Lengths, cut ahead (painting-company row 361, "Instant"):
/// once a painting not begun has settled on screen, its other lengths are cut quietly, one at a
/// time and nearest first, at utility priority, so a length picked is there at once. The photo's
/// analysis (Vision's findings, the line art's inputs: `ArtworkFactory.Analysis`) is found once
/// for all of them, and each cut is the one `Library.recut` would make
/// (`ArtworkFactory.cut`), kept in memory: nothing reaches the painting's folder until a length
/// is picked, and then it is put in as a cut the painting had (`Library.restoreCut`). A length
/// picked while its cut is still under way waits for that cut (`claim`), raised to the
/// painter's priority, rather than starting again. It all stops when the painter begins, a re-cut
/// or ✎ Change starts, or the screen goes; the analysis is let go when the painting is begun or
/// closed (`forget`). Every build from 1.5.
@MainActor
@Observable
final class LengthPrecuts {
    /// A length's cut, made and not saved.
    nonisolated struct Cut: Sendable {
        let length: PaintingLength
        let template: Template
        let settings: GenerationSettings
    }

    /// The progress (0…1) of the cut the painter picked and is waiting for (`claim`); nil when
    /// none is awaited. The only thing here a view reads: work made ahead never redraws it.
    private(set) var awaitedProgress: Double?

    /// How long the painting is left alone after it opens (or after a re-cut) before the cuts
    /// start: its screen builds and its first frames draw undisturbed.
    static let settle: Duration = .seconds(1.5)

    /// The photo's analysis and the refinements every cut is made with, for one painting.
    private nonisolated struct Inputs: Sendable {
        let analysis: ArtworkFactory.Analysis
        let refinements: TemplateRefinements
    }

    private struct Running {
        let length: PaintingLength
        let task: Task<Cut, any Error>
        let progress: CutProgress
        var claimed = false
    }

    @ObservationIgnored private var inputs: (lineArt: LineArtSettings, task: Task<Inputs, any Error>)?
    /// The one cut under way.
    @ObservationIgnored private var running: Running?
    /// The cuts made ahead, in turn (`resume`).
    @ObservationIgnored private var turn: Task<Void, Never>?
    /// Moves on with each `forget`: a cut made of what was forgotten is never handed over.
    @ObservationIgnored private var era = 0

    /// The lengths to cut ahead from `current`, nearest first and the shorter of two as near
    /// (it is the quicker cut): `current` itself first when `includingCurrent` (a painting of
    /// the painter's own settings, whose length picked is cut afresh), and none of `skipping`.
    nonisolated static func order(
        from current: PaintingLength?, includingCurrent: Bool, skipping: Set<PaintingLength> = []
    ) -> [PaintingLength] {
        let all = PaintingLength.allCases
        guard let current, let place = all.firstIndex(of: current) else {
            return all.filter { !skipping.contains($0) }
        }
        return all.enumerated()
            .filter { (includingCurrent || $0.element != current) && !skipping.contains($0.element) }
            .sorted { (abs($0.offset - place), $0.offset) < (abs($1.offset - place), $1.offset) }
            .map(\.element)
    }

    /// Starts cutting ahead, after `settle`, the lengths of `order(from:includingCurrent:skipping:)`
    /// for `artwork` (its settings kept as `Library.recut` keeps them), handing each to `made`;
    /// a cut under way already is waited for, not started again. Stops what came before.
    func resume(
        artwork: Artwork, current: PaintingLength?, includingCurrent: Bool, skipping: Set<PaintingLength>, library: Library,
        made: @escaping @MainActor (Cut) -> Void
    ) {
        stop()
        let lengths = Self.order(from: current, includingCurrent: includingCurrent, skipping: skipping)
        guard !lengths.isEmpty else { return }
        let era = era
        turn = Task(priority: .utility) { [weak self] in
            try? await Task.sleep(for: LengthPrecuts.settle)
            for length in lengths {
                guard let self, !Task.isCancelled, self.era == era else { return }
                let running = self.running?.length == length ? self.running! : self.start(length, of: artwork, library: library)
                self.running = running
                let cut = try? await running.task.value
                if self.running?.task == running.task, !self.running!.claimed { self.running = nil }
                // Stopped meanwhile (the cut may be the painter's now): nothing more here.
                guard !Task.isCancelled, self.era == era else { return }
                guard let cut else { return }
                made(cut)
            }
        }
    }

    /// The cut at `length` for the painter, who has picked it: the one under way, raised to
    /// the painter's priority by being waited for, else one started now (on the analysis
    /// found already, when it was). Whatever else was being cut ahead stops. Call `finished`
    /// once the cut is in the painting.
    func claim(_ length: PaintingLength, of artwork: Artwork, library: Library) -> Task<Cut, any Error> {
        turn?.cancel()
        turn = nil
        var claimed: Running
        if let running, running.length == length {
            claimed = running
        } else {
            running?.task.cancel()
            claimed = start(length, of: artwork, library: library, priority: .userInitiated)
        }
        claimed.claimed = true
        running = claimed
        awaitedProgress = claimed.progress.claim()
        return claimed.task
    }

    /// The claimed cut is in the painting, or failed: the chip no longer reads its progress.
    func finished() {
        if running?.claimed == true { running = nil }
        awaitedProgress = nil
    }

    /// Stops cutting ahead: the cut under way is cancelled unless the painter is waiting for it.
    /// What was found and made stays for when it resumes.
    func stop() {
        turn?.cancel()
        turn = nil
        if let running, !running.claimed {
            running.task.cancel()
            self.running = nil
        }
    }

    /// Lets go of the photo's analysis and of anything under way: the painting was begun or
    /// closed, or changed (Fine-Tune, ✎ Change: its refinements and line art may be others).
    func forget() {
        stop()
        era += 1
        inputs?.task.cancel()
        inputs = nil
    }

    private func start(
        _ length: PaintingLength, of artwork: Artwork, library: Library, priority: TaskPriority = .utility
    ) -> Running {
        let pending = found(for: artwork, library: library)
        let progress = CutProgress()
        let report: @Sendable (Float) -> Void = { [weak self] value in
            guard progress.report(value) else { return }
            Task { @MainActor [weak self] in self?.show(progress) }
        }
        let kept = artwork.settings, maxCandidates = CreateModel.maxCandidates
        let task = Task(priority: priority) {
            let inputs = try await pending.value
            try Task.checkCancellation()
            let made = try await ArtworkFactory.cut(
                of: inputs.analysis, keeping: kept, length: length, refinements: inputs.refinements,
                maxCandidates: maxCandidates, progress: report)
            return Cut(length: length, template: made.template, settings: made.settings)
        }
        return Running(length: length, task: task, progress: progress)
    }

    /// The photo's analysis and the painting's refinements, found once (again when the line
    /// art reads other inputs). A failure isn't kept: the next cut tries again.
    private func found(for artwork: Artwork, library: Library) -> Task<Inputs, any Error> {
        if let inputs, ArtworkFactory.Analysis.sameInputs(inputs.lineArt, artwork.settings.lineArt) { return inputs.task }
        inputs?.task.cancel()
        let id = artwork.id, lineArt = artwork.settings.lineArt
        let task = Task(priority: .utility) { () async throws -> Inputs in
            let read = try await library.cutInputs(for: id)
            try Task.checkCancellation()
            return Inputs(analysis: try await ArtworkFactory.analysis(of: read.photo, lineArt: lineArt), refinements: read.refinements)
        }
        inputs = (lineArt, task)
        Task { [weak self] in
            if case .failure = await task.result, self?.inputs?.task == task { self?.inputs = nil }
        }
        return task
    }

    private func show(_ progress: CutProgress) {
        guard let running, running.claimed, running.progress === progress else { return }
        awaitedProgress = progress.shown
    }

    /// A cut's progress, kept off the main actor until the painter waits for it: only then does
    /// each step reach the chip (`report` says when it should).
    nonisolated final class CutProgress: Sendable {
        private let state = OSAllocatedUnfairLock(initialState: (claimed: false, value: Float(0)))

        /// Records `value`; true when the painter is waiting for this cut.
        func report(_ value: Float) -> Bool {
            state.withLock { state in
                state.value = value
                return state.claimed
            }
        }

        /// Marks the cut as awaited, and gives the progress to show now.
        func claim() -> Double {
            state.withLock { state in
                state.claimed = true
                return Self.fraction(state.value)
            }
        }

        var shown: Double { Self.fraction(state.withLock { $0.value }) }

        /// The last 5 % are the saving's, as `Library.regenerate` reports it.
        private static func fraction(_ value: Float) -> Double { 0.95 * Double(value) }
    }
}
