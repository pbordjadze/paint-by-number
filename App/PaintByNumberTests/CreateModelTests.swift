import Foundation
import PaintCore
import Testing
@testable import PaintByNumber

@MainActor
struct CreateModelTests {
    /// A photo opens on settings chosen for it: the first candidate shows as a draft while the
    /// others are tried, then the winner is generated at full resolution.
    @Test func suggestsSettingsShowingADraftBeforeTheDecision() async throws {
        let model = CreateModel(paintingLength: .relaxed)
        model.load(sample: try #require(Sample.named("great-wave")))
        var sawSuggesting = false, sawDraftBeforeDecision = false
        try await waitUntil(polling: .milliseconds(5)) {
            if model.phase == .suggesting {
                sawSuggesting = true
                #expect(model.isChoosingSettings)
            }
            if model.decision == nil, model.preview?.isDraft == true { sawDraftBeforeDecision = true }
            return model.isFinal
        }
        #expect(sawSuggesting)
        #expect(sawDraftBeforeDecision, "The first candidate wasn't shown before the decision")
        let decision = try #require(model.decision)
        #expect(model.phase == .ready)
        #expect(model.settingsOrigin == .suggested)
        #expect(model.settings == decision.settings)
        #expect(model.preview?.settings == decision.settings)
        #expect(decision.preference == .relaxed)
        #expect((1...CreateModel.maxCandidates).contains(decision.candidates.count))
        #expect(decision.candidates.allSatisfy { $0.score != nil })
        #expect(PaintingLength.relaxed.colorBand.contains(decision.settings.colorCount))
        // The analysis saw the photo's own size, not the draft's.
        let source = try #require(model.source)
        #expect(decision.analysis.sourceWidth == source.image.width && decision.analysis.sourceHeight == source.image.height)

        let draft = try await model.makeDraft()
        #expect(draft.settings == decision.settings)
        #expect(draft.settingsOrigin == .suggested)
        #expect(draft.paintingLength == .relaxed)
    }

    /// Moving a slider makes the settings the painter's own; Reset to Suggested brings the
    /// decision's settings back without choosing again.
    @Test func sliderChangeMakesSettingsCustomAndResetRestoresTheSuggestion() async throws {
        let model = CreateModel()
        model.load(sample: try #require(Sample.named("red-fox")))
        try await waitUntil { model.isFinal }
        let decision = try #require(model.decision)
        let suggested = model.settings

        model.detail = suggested.detail < 0.75 ? Double(suggested.detail) + 0.25 : Double(suggested.detail) - 0.25
        model.settingsChanged()
        #expect(model.settingsOrigin == .custom)
        try await waitUntil { model.isFinal }
        #expect(model.settings != suggested)
        let custom = try await model.makeDraft()
        #expect(custom.settingsOrigin == .custom)
        #expect(custom.settings.detail != suggested.detail)

        model.resetToSuggested()
        #expect(model.settingsOrigin == .suggested)
        #expect(model.settings == suggested)
        var choseAgain = false
        try await waitUntil {
            if model.phase == .suggesting { choseAgain = true }
            return model.isFinal
        }
        #expect(!choseAgain, "Reset ran a new suggestion")
        #expect(model.preview?.settings == suggested)
        #expect(model.decision?.winner == decision.winner)
        #expect(model.decision?.candidates.map(\.settings) == decision.candidates.map(\.settings))
    }

    /// Starting a painting while settings are still being chosen waits for them.
    @Test func startingWhileChoosingUsesTheSuggestion() async throws {
        let model = CreateModel(paintingLength: .quick)
        model.load(sample: try #require(Sample.named("delicate-arch")))
        try await waitUntil { model.source != nil }
        let draft = try await model.makeDraft()
        let decision = try #require(model.decision)
        #expect(decision.preference == .quick)
        #expect(draft.settings == decision.settings)
        #expect(draft.settingsOrigin == .suggested && draft.paintingLength == .quick)
        #expect(PaintingLength.quick.colorBand.contains(draft.settings.colorCount))
    }

    /// Another photo, or closing the flow, stops a suggestion: nothing of it shows up later.
    @Test func changingThePhotoCancelsTheSuggestion() async throws {
        let model = CreateModel()
        model.load(sample: try #require(Sample.named("red-fuji")))
        try await waitUntil { model.phase == .suggesting }
        model.load(sample: try #require(Sample.named("morning-glories")))
        #expect(model.decision == nil && model.preview == nil && model.settingsOrigin == nil)
        try await waitUntil { model.isFinal }
        #expect(model.source?.sampleName == "morning-glories")
        #expect(model.decision?.analysis.sourceWidth == model.source?.image.width)

        model.load(sample: try #require(Sample.named("milkmaid")))
        try await waitUntil { model.phase == .suggesting }
        model.cancelAll()
        let shown = model.preview?.id
        try await Task.sleep(for: .seconds(3))
        #expect(model.decision == nil && model.settingsOrigin == nil)
        #expect(model.preview?.id == shown)
    }

    @Test func generatesDraftThenFinalAndFollowsSettings() async throws {
        let model = CreateModel()
        let sample = try #require(Sample.named("red-fox"))
        model.load(sample: sample)
        try await waitUntil { model.isFinal }
        let first = try #require(model.preview)
        #expect(!first.isDraft)
        #expect(model.phase == .ready)
        #expect((model.stats?.areas ?? 0) > 0)
        #expect(model.defaultTitle == sample.title)
        #expect(model.resolvedTitle == sample.title)

        // Dragging a slider: quick drafts at reduced size… The thumb keeps moving, as a drag
        // does: each change puts the full resolution off by `CreateModel.restDelay` again. Changed
        // once, a draft slower than that (CI's simulator, under the tests running beside it) was
        // overtaken by the full resolution and dropped, and the wait timed out.
        model.setAdjusting(true)
        model.colorCount = 8
        try await waitUntil {
            model.settingsChanged()
            return model.preview?.isDraft == true && model.preview?.settings?.colorCount == 8
        }
        #expect(model.preview.map { max($0.template.width, $0.template.height) } ?? 0 <= Int(AutoSettings.draftLongSide) + 1)

        // …and the full resolution once it is released.
        model.setAdjusting(false)
        try await waitUntil { model.isFinal }
        #expect(model.preview?.settings?.colorCount == 8)

        model.title = "  Winter Fox "
        let draft = try await model.makeDraft()
        #expect(draft.title == "Winter Fox")
        #expect(draft.template.palette.count <= 8)
        #expect(draft.sampleName == "red-fox")
        #expect(draft.photo != nil)
        #expect(draft.settingsOrigin == .custom)
    }

    @Test func startingPaintingGeneratesTheFinalTemplateIfNeeded() async throws {
        let model = CreateModel()
        model.load(sample: try #require(Sample.named("red-fuji")))
        try await waitUntil { model.decision != nil }
        // Change the settings and immediately start: the draft must match the new settings.
        model.colorCount = 7
        model.settingsChanged()
        let draft = try await model.makeDraft()
        #expect(draft.settings.colorCount == 7)
        #expect(draft.settingsOrigin == .custom)
        #expect(model.isFinal)
    }

    @Test func cameraFailureSurfacesAnError() async throws {
        let model = CreateModel()
        model.load(sample: try #require(Sample.named("great-wave")))
        try await waitUntil { model.source != nil }
        // The camera's shot couldn't be read: the earlier photo and its work are dropped.
        model.fail(.cameraCapture)
        #expect(model.phase == .failed(CreateModel.CreateError.cameraCapture.localizedDescription))
        #expect(model.source == nil && model.preview == nil && model.stats == nil)
        #expect(model.decision == nil && model.settingsOrigin == nil)
        try await Task.sleep(for: .milliseconds(300))
        #expect(model.preview == nil)
    }

    /// The typed name is trimmed; an empty one falls back to the sample's name or, for a
    /// photo, the date. A new photo starts over with its own default.
    @Test func titleFallsBackToTheDefault() throws {
        let model = CreateModel()
        let sample = try #require(Sample.named("red-fox"))
        model.load(sample: sample)
        #expect(model.title == "")
        #expect(model.defaultTitle == sample.title)
        model.title = "  Jungle \n"
        #expect(model.resolvedTitle == "Jungle")
        model.title = "   "
        #expect(model.resolvedTitle == sample.title)

        model.title = "Jungle"
        model.load(imageData: Data())
        #expect(model.title == "")
        #expect(model.defaultTitle == Date.now.formatted(.dateTime.month(.wide).day()))
        #expect(model.resolvedTitle == model.defaultTitle)
        model.cancelAll()
    }

    @Test func createModelMapsSliders() {
        let model = CreateModel()
        // The sliders wait at the generator's defaults until a photo's suggestion moves them.
        #expect(model.settings == GenerationSettings())
        #expect(model.settingsOrigin == nil && model.decision == nil && !model.isChoosingSettings)
        model.colorCount = 30
        model.detail = 0.25
        model.smoothness = 0.75
        #expect(model.settings == GenerationSettings(colorCount: 30, detail: 0.25, smoothness: 0.75))
        model.colorCount = 11.6
        #expect(model.settings.colorCount == 12)
        model.colorCount = 999
        #expect(model.settings.colorCount == GenerationSettings.colorCountRange.upperBound)
        #expect(model.preview == nil && !model.isFinal)
    }

    /// A thumb resting under the finger gets the full resolution without letting go, and
    /// letting go then keeps it.
    @Test func aRestingThumbShowsTheFullResolution() async throws {
        let model = CreateModel()
        model.load(sample: try #require(Sample.named("red-fox")))
        try await waitUntil { model.isFinal }
        model.setAdjusting(true)
        model.colorCount = 9
        model.settingsChanged()
        try await waitUntil { model.isFinal }
        #expect(model.isAdjusting && model.preview?.settings?.colorCount == 9)
        let shown = model.preview?.id
        model.setAdjusting(false)
        try await Task.sleep(for: .milliseconds(400))
        #expect(model.preview?.id == shown, "Letting go generated the same settings again")
        #expect(model.phase == .ready)
    }

    /// Back on the suggestion's values (the sliders' detents), the settings are the suggestion
    /// again; the Lines slider's middle is the base line art, and Reset brings it back.
    @Test func linesTuneTheDrawingAndTheSuggestionComesBack() async throws {
        let model = CreateModel()
        model.load(sample: try #require(Sample.named("red-fox")))
        try await waitUntil { model.isFinal }
        let suggested = model.settings
        #expect(model.lines == 0.5 && suggested.lineArt == model.baseLineArt)

        model.lines = 0.9
        model.settingsChanged()
        #expect(model.settingsOrigin == .custom)
        #expect(model.settings.lineArt.detailThreshold < suggested.lineArt.detailThreshold)
        try await waitUntil { model.isFinal }
        #expect(model.preview?.settings?.lineArt == model.settings.lineArt)

        model.lines = 0.5
        model.settingsChanged()
        #expect(model.settingsOrigin == .suggested && model.settings == suggested)

        model.lines = 0.2
        model.settingsChanged()
        model.resetToSuggested()
        #expect(model.lines == 0.5 && model.settings == suggested)
    }

    /// More lines lower the thresholds and shorten the shortest line, fewer raise and lengthen
    /// them; the middle and classic line art are left as they are.
    @Test func linesMapToTheLineArt() {
        let book = LineArtSettings(style: .coloringBook)
        #expect(CreateModel.lineArt(book, lines: 0.5) == book)
        let more = CreateModel.lineArt(book, lines: 1), fewer = CreateModel.lineArt(book, lines: 0)
        #expect(more.detailThreshold < book.detailThreshold && more.outlineThreshold < book.outlineThreshold)
        #expect(more.minimumStrokeLength < book.minimumStrokeLength)
        #expect(fewer.detailThreshold > book.detailThreshold && fewer.minimumStrokeLength > book.minimumStrokeLength)
        #expect(more == more.normalized && fewer == fewer.normalized)
        let classic = LineArtSettings(style: .classic)
        #expect(CreateModel.lineArt(classic, lines: 1) == classic)
    }

    /// Drafts draw from the reduced photo with the line art's lengths scaled to their smaller
    /// canvas; the full resolution keeps them.
    @Test func draftsScaleTheLineLengths() {
        let settings = GenerationSettings(detail: 0.5)
        let source = RGBAImage(width: 2000, height: 1500, pixels: [UInt8](repeating: 128, count: 2000 * 1500 * 4))
        let draft = AutoSettings.draftImage(from: source)
        let scaled = CreateModel.draftSettings(settings, draft: draft, source: source)
        let small = settings.workingSize(sourceWidth: draft.width, sourceHeight: draft.height)
        let scale = Float(max(small.width, small.height)) / Float(settings.workingLongSide)
        #expect(scale < 0.5)
        #expect(abs(scaled.lineArt.minimumStrokeLength - settings.lineArt.minimumStrokeLength * scale) < 0.01)
        #expect(abs(scaled.lineArt.gapBridging - settings.lineArt.gapBridging * scale) < 0.01)
        #expect(CreateModel.draftSettings(settings, draft: source, source: source) == settings)
    }
}
