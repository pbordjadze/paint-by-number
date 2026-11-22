#if UNRELEASED
import Combine
import Foundation
import os
import PaintCore
import SwiftUI
import UIKit

/// Tonight's Picture made before it is picked (painting-company row 361, its fourth wait): it is
/// known a day ahead, so once the app has settled with no painting open, the picture is decoded,
/// analyzed, its settings chosen and its template made as the create flow would make them when
/// it is picked (`CreateModel.makeAhead`), at background priority, and kept here in memory. A
/// flow loading that very picture, at the same Painting Length and line art, with the same
/// pipeline, takes it (`CreateModel.load(sample:)`), so the painting is ready at once and its
/// forming lines are drawn in straight away. Anything else (another picture, length, build of the
/// pipeline, a making not finished) makes it as ever, and a pick while it is still being made
/// stops it, so the two never run side by side.
///
/// What is kept is let go once taken, when another night's picture comes, and on a memory
/// warning; a painting opened stops what is being made. SideStore and Debug builds
/// (`UNRELEASED`); never in demo or test launches (`Preparing`), whose timings it would move.
final class TonightAhead {
    static let shared = TonightAhead()

    /// What a picture made ahead was made of, all of which a flow's own making would read: the
    /// picture and its file, the painter's Painting Length, the line art, a new painting's
    /// tuning and paint mix, the suggestion's candidate count (by the device's cores) and the
    /// pipeline's version.
    nonisolated struct Key: Hashable, Sendable {
        let sampleID: String
        let file: URL
        let paintingLength: PaintingLength
        let lineArt: LineArtSettings
        let tuning: PipelineTuning
        let paintMix: PaintMix?
        let candidates: Int
        let pipelineVersion: UInt32
    }

    /// The key of `sample` for a flow at `paintingLength` with `lineArt` (its `baseLineArt`); nil
    /// for a picture that can't be made yet (a night's whose full picture hasn't come).
    static func key(for sample: Sample, paintingLength: PaintingLength, lineArt: LineArtSettings) -> Key? {
        guard !sample.isThumbnailOnly, let url = sample.url else { return nil }
        return Key(
            sampleID: sample.id, file: url, paintingLength: paintingLength, lineArt: lineArt,
            tuning: CreateModel.newTuning, paintMix: CreateModel.newPaintMix, candidates: CreateModel.maxCandidates,
            pipelineVersion: TemplateGenerator.pipelineVersion)
    }

    /// How long the app has been settled (active, no painting open) before the making starts:
    /// nothing of a launch, or of a painting just closed, waits for it.
    static let settle: Duration = .seconds(3)

    private struct Kept {
        let key: Key
        let made: CreateModel.MadeAhead
    }

    private struct Making {
        let key: Key
        let task: Task<Void, Never>
    }

    private var kept: Kept?
    private var making: Making?
    /// The key a flow asked for last: that flow makes it (or took it), so it isn't made again
    /// beside it, even when the app comes back to the front mid-flow.
    private var taken: Key?

    /// The key of what is kept, made and ready to be taken.
    var keptKey: Key? { kept?.key }

    /// Makes the picture of `key` unless it is kept or being made already; what was kept or being
    /// made of another key goes. The task ends once it is kept, or stopped.
    @discardableResult
    func prepare(_ key: Key) -> Task<Void, Never>? {
        if let making, making.key == key { return making.task }
        if kept?.key == key || taken == key { return nil }
        cancel()
        kept = nil
        let task = Task(priority: .background) { [weak self] in
            let started = ContinuousClock.now
            do {
                let made = try await CreateModel.makeAhead(
                    of: key.file, preference: key.paintingLength, lineArt: key.lineArt, maxCandidates: key.candidates)
                guard !Task.isCancelled, let self, self.making?.key == key else { return }
                self.kept = Kept(key: key, made: made)
                self.making = nil
                Log.create.notice("Tonight's Picture made ahead in \(String(describing: ContinuousClock.now - started), privacy: .public)")
            } catch {
                if !(error is CancellationError) {
                    Log.create.notice("Tonight's Picture wasn't made ahead: \(String(describing: error), privacy: .public)")
                }
                if let self, self.making?.key == key { self.making = nil }
            }
        }
        making = Making(key: key, task: task)
        return task
    }

    /// What was made of `key`, let go here as it is taken; nil unless it is made and kept. A
    /// miss stops the same picture being made meanwhile (the flow makes it now) and lets go of
    /// one made of another length or line art.
    func take(_ key: Key) -> CreateModel.MadeAhead? {
        taken = key
        if let kept, kept.key == key {
            self.kept = nil
            return kept.made
        }
        if making?.key.sampleID == key.sampleID { cancel() }
        if kept?.key.sampleID == key.sampleID { kept = nil }
        return nil
    }

    /// Stops what is being made; what is kept stays.
    func cancel() {
        making?.task.cancel()
        making = nil
    }

    /// Stops what is being made and lets go of what is kept (a memory warning).
    func clear() {
        cancel()
        kept = nil
    }

    /// Makes Tonight's Picture ahead while the app is active and no painting is open (the gallery,
    /// the Paint page), and stops as one opens or the app goes; a memory warning lets it go. On
    /// the app's shell (`AppShellView`).
    struct Preparing: ViewModifier {
        /// A painting is open: nothing is made while it is painted.
        let isPainting: Bool
        @Environment(\.scenePhase) private var scenePhase
        @Environment(Library.self) private var library
        @AppStorage(SettingsKey.paintingLength) private var paintingLength = PaintingLength.default

        private struct Moment: Equatable {
            let isSettled: Bool
            let paintingLength: PaintingLength
            /// The nights' schedule refreshed: tonight's picture may be another, or here at last.
            let nights: Int
        }

        private var moment: Moment {
            Moment(isSettled: scenePhase == .active && !isPainting, paintingLength: paintingLength, nights: Nights.revision.value)
        }

        func body(content: Content) -> some View {
            content
                .task(id: moment) { await prepare() }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
                    TonightAhead.shared.clear()
                }
        }

        private func prepare() async {
            guard scenePhase == .active, !isPainting else {
                // In the background nothing is kept, so iOS has less reason to end the app.
                if scenePhase == .background { TonightAhead.shared.clear() } else { TonightAhead.shared.cancel() }
                return
            }
            #if DEBUG
            if DemoMode.isActive || DemoMode.isTestHost { return }
            #endif
            guard (try? await Task.sleep(for: TonightAhead.settle)) != nil, let tonight = Sample.tonight(),
                  // Painted already: it isn't made again.
                  !library.artworks.contains(where: { $0.sampleName == tonight.id }),
                  // The create flow's own model's line art (`CreateModel.baseLineArt`).
                  let key = TonightAhead.key(for: tonight, paintingLength: paintingLength, lineArt: LineArtSettings().normalized)
            else { return }
            TonightAhead.shared.prepare(key)
        }
    }
}
#endif
