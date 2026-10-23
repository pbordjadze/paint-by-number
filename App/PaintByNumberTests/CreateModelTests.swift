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

    /// A template made from a photo no longer there is not kept for the next one: the generation
    /// that finishes after the photo went finds `made` cleared and leaves it so.
    @Test func aGenerationFinishingAfterThePhotoWentKeepsNothing() async throws {
        let model = CreateModel()
        model.load(sample: try #require(Sample.named("red-fox")))
        try await waitUntil { model.phase == .generating }
        model.fail(.cameraCapture)
        try await Task.sleep(for: .seconds(3))
        #expect(model.rememberedBases == 0 && model.preview == nil)

        model.load(sample: try #require(Sample.named("red-fox")))
        try await waitUntil { model.isFinal }
        #expect(model.rememberedBases > 0)
        model.load(sample: try #require(Sample.named("great-wave")))
        #expect(model.rememberedBases == 0)
        model.cancelAll()
    }

    /// Refine opens only on the final template: not while the settings are chosen, on a draft, or
    /// on the template of settings the sliders have left.
    @Test func refineOpensOnlyOnTheFinalTemplate() async throws {
        let model = CreateModel()
        #expect(!model.canRefine)
        model.load(sample: try #require(Sample.named("red-fox")))
        try await waitUntil { model.phase == .suggesting }
        #expect(!model.canRefine)
        try await waitUntil { model.isFinal }
        #expect(model.canRefine)

        // The sliders moved: the template on screen is the earlier settings'.
        model.setAdjusting(true)
        model.colorCount = 9
        model.settingsChanged()
        #expect(!model.canRefine)
        try await waitUntil(polling: .milliseconds(5)) {
            model.settingsChanged()
            return model.preview?.isDraft == true && model.preview?.settings?.colorCount == 9
        }
        #expect(!model.canRefine)
        model.setAdjusting(false)
        try await waitUntil { model.isFinal }
        #expect(model.canRefine)
        model.cancelAll()
    }

    /// A touch on a slider that moves nothing, while the final template of the settings it let go
    /// on is being made, must not cost that template: the touch cancelled the job, and letting go
    /// took the cancelled job, still unwinding, for the one under way and made no other.
    @Test func touchingASliderWhileTheFinalIsBeingMadeStillGetsTheFinal() async throws {
        let model = CreateModel()
        model.load(sample: try #require(Sample.named("red-fox")))
        try await waitUntil { model.isFinal }

        // A slider moved and let go: the full resolution of the new settings starts.
        model.setAdjusting(true)
        model.colorCount = model.colorCount < 20 ? 28 : 12
        model.settingsChanged()
        model.setAdjusting(false)
        try await waitUntil(timeout: .seconds(60), polling: .milliseconds(2)) { model.refining != nil }
        #expect(!model.isFinal && !model.canRefine)

        // A touch that moves nothing, before it is done.
        model.setAdjusting(true)
        model.setAdjusting(false)
        try await waitUntil(timeout: .seconds(60)) { model.isFinal }
        #expect(model.canRefine && model.phase == .ready)
        model.cancelAll()
    }

    /// Refine tapped while the painting is still updating waits for the final template and opens
    /// by itself (`opensRefine`), which a full resolution on a phone takes tens of seconds to make;
    /// there is nothing to ask for while the photo's settings are chosen, and with the final
    /// template there it opens at once.
    @Test func refineTappedWhileUpdatingOpensOnceTheFinalIsMade() async throws {
        let model = CreateModel()
        model.load(sample: try #require(Sample.named("red-fox")))
        try await waitUntil { model.phase == .suggesting }
        model.askForRefine()
        #expect(!model.canAskForRefine && !model.isWaitingToRefine && !model.refineAsked)

        try await waitUntil { model.isFinal }
        model.askForRefine()
        #expect(model.canAskForRefine && model.canRefine && !model.refineAsked, "Asked for with the final template there")

        // A slider moved and let go: the template is made again, and Refine waits for it.
        model.colorCount = model.colorCount < 20 ? 28 : 12
        model.settingsChanged()
        #expect(!model.canRefine && model.canAskForRefine)
        model.askForRefine()
        #expect(model.isWaitingToRefine && !model.opensRefine)
        try await waitUntil(timeout: .seconds(60)) { model.opensRefine }
        #expect(model.isFinal && !model.isWaitingToRefine)
        model.withdrawRefine()
        #expect(!model.opensRefine)
        model.cancelAll()
    }

    /// A drag whose end was never heard leaves the model adjusting: a Refine asked for then still
    /// opens once the final template is made (the full resolution of a resting thumb comes anyway).
    @Test func aRefineAskedForOpensEvenIfTheLastDragNeverEnded() async throws {
        let model = CreateModel()
        model.load(sample: try #require(Sample.named("red-fox")))
        try await waitUntil { model.isFinal }

        model.setAdjusting(true)
        model.colorCount = model.colorCount < 20 ? 28 : 12
        model.settingsChanged()
        model.askForRefine()
        #expect(model.isWaitingToRefine && model.isAdjusting)
        try await waitUntil(timeout: .seconds(60)) { model.opensRefine }
        #expect(model.isFinal && model.isAdjusting)
        model.cancelAll()
    }

    /// Start Painting tapped before the painting is made waits for it and goes by itself
    /// (`startsNow`); a setting changed meanwhile calls it off, touch heard or not (VoiceOver's
    /// adjust, a key), and so do Reset to Suggested and a new photo.
    @Test func aStartAskedForEarlyGoesOnceMadeUnlessASettingChanges() async throws {
        let model = CreateModel()
        model.load(sample: try #require(Sample.named("red-fox")))
        try await waitUntil { model.phase == .suggesting }
        model.askForStart()
        #expect(model.startAsked && !model.startsNow, "Asked for while the settings are chosen")
        try await waitUntil(timeout: .seconds(60)) { model.startsNow }
        #expect(model.isFinal && !model.isChoosingSettings)
        model.withdrawStart()
        #expect(!model.startAsked && !model.startsNow)

        // A setting changed with no touch heard: the start it was asked on is off.
        model.colorCount = model.colorCount < 20 ? 28 : 12
        model.settingsChanged()
        model.askForStart()
        #expect(model.startAsked)
        model.colorCount = model.colorCount < 20 ? 28 : 12
        model.settingsChanged()
        #expect(!model.startAsked, "A changed setting left the start on")

        model.askForStart()
        model.resetToSuggested()
        #expect(!model.startAsked, "Reset to Suggested left the start on")
        model.askForStart()
        model.load(sample: try #require(Sample.named("great-wave")))
        #expect(!model.startAsked, "A new photo left the start on")
        model.cancelAll()
    }

    /// A setting changed after Refine was tapped calls the wait off, even when the slider's touch
    /// was never heard (CI, Oct 18: a drag's start never reached `setAdjusting`).
    @Test func aRefineWaitedForIsCalledOffByAChangedSetting() async throws {
        let model = CreateModel()
        model.load(sample: try #require(Sample.named("red-fox")))
        try await waitUntil { model.isFinal }

        model.colorCount = model.colorCount < 20 ? 28 : 12
        model.settingsChanged()
        model.askForRefine()
        #expect(model.isWaitingToRefine)
        model.colorCount = model.colorCount < 20 ? 28 : 12
        model.settingsChanged()
        #expect(!model.isWaitingToRefine, "A changed setting left the wait on")
        model.cancelAll()
    }

    /// A Refine waited for is called off by going back to the sliders, by Start and by another
    /// photo: it must not open over what the painter went on to.
    @Test func aRefineWaitedForIsCalledOffByTheSlidersStartAndAnotherPhoto() async throws {
        let model = CreateModel()
        model.load(sample: try #require(Sample.named("red-fox")))
        try await waitUntil { model.isFinal }

        model.colorCount = model.colorCount < 20 ? 28 : 12
        model.settingsChanged()
        model.askForRefine()
        #expect(model.isWaitingToRefine)
        model.setAdjusting(true)
        #expect(!model.isWaitingToRefine, "A touch on a slider left the wait on")
        model.setAdjusting(false)
        try await waitUntil(timeout: .seconds(60)) { model.isFinal }
        try await Task.sleep(for: .milliseconds(200))
        #expect(!model.opensRefine, "Refine opened by itself after the sliders were touched")

        model.colorCount = model.colorCount < 20 ? 28 : 12
        model.settingsChanged()
        model.askForRefine()
        #expect(model.isWaitingToRefine)
        _ = try await model.makeDraft()
        #expect(!model.refineAsked && !model.opensRefine, "Start left a Refine to open over the painting")

        model.colorCount = model.colorCount < 20 ? 28 : 12
        model.settingsChanged()
        model.askForRefine()
        #expect(model.isWaitingToRefine)
        model.load(sample: try #require(Sample.named("great-wave")))
        #expect(!model.refineAsked, "Another photo kept the last one's wait")
        model.cancelAll()
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

    /// Refining regenerates the template with the refinements (the preview isn't final until it
    /// has them), Start saves them with the painting, and a new photo starts unrefined.
    @Test func refiningRegeneratesAndTheDraftKeepsIt() async throws {
        let model = CreateModel()
        model.load(sample: try #require(Sample.named("red-fox")))
        try await waitUntil { model.isFinal }
        var refinements = TemplateRefinements()
        refinements.strokes = [TemplateRefinements.Stroke(kind: .less, radius: 0.2, points: [SIMD2(0.5, 0.5)])]
        model.refine(refinements)
        #expect(model.refinements == refinements && !model.isFinal)
        try await waitUntil { model.isFinal }
        #expect(model.preview?.refinements == refinements)
        let draft = try await model.makeDraft()
        #expect(draft.refinements == refinements)

        model.load(sample: try #require(Sample.named("great-wave")))
        #expect(model.refinements.isEmpty)
        model.cancelAll()
    }

    /// Lines refined through the generator (a painting or a draft made by an earlier build) still
    /// regenerate the template at full resolution, never a draft that would coarsen the drawing
    /// meanwhile; taking them back brings the template they had again.
    @Test func legacyLinesRegenerateAtFullResolutionAndUndoBringsTheTemplateBack() async throws {
        let model = CreateModel()
        model.load(sample: try #require(Sample.named("red-fox")))
        try await waitUntil { model.isFinal }
        #expect(model.hasLineArtInput)
        let before = try #require(model.preview?.template)
        var refinements = TemplateRefinements()
        refinements.lines = [.init(kind: .draw, radius: 0, points: [SIMD2(0.05, 0.5), SIMD2(0.5, 0.45), SIMD2(0.95, 0.5)])]
        model.refine(refinements)
        var sawDraft = false
        try await waitUntil(polling: .milliseconds(5)) {
            if model.preview?.isDraft == true { sawDraft = true }
            return model.isFinal
        }
        #expect(!sawDraft, "Refining showed a draft")
        #expect(model.preview?.refinements == refinements && model.preview?.template != before)

        model.refine(TemplateRefinements())
        try await waitUntil { model.isFinal }
        #expect(model.preview?.template == before)
        model.cancelAll()
    }

    // MARK: Refine's edits

    /// A short line in the middle of a canvas, in canvas units.
    private func line(in template: Template) -> TemplateEditor.Edit {
        let w = Float(template.width), h = Float(template.height)
        return .draw(points: [SIMD2(0.42 * w, 0.5 * h), SIMD2(0.5 * w, 0.46 * h), SIMD2(0.58 * w, 0.5 * h)])
    }

    /// Waits for the template on screen to have the edits refined so far.
    private func waitForEdits(_ model: CreateModel, _ serial: Int) async throws {
        try await waitUntil(polling: .milliseconds(2)) { model.settledEdits >= serial && model.isFinal }
    }

    /// An edit is laid on the template on screen as it is (a drawn line with the photo's colors
    /// for what it cuts, `TemplateEditor.painted`): nothing is generated and no draft shows, the
    /// paints are the ones it had, and every region away from the line is bit for bit what it was.
    @Test func anEditIsLaidOnTheTemplateOnScreenAlone() async throws {
        let model = CreateModel()
        model.load(sample: try #require(Sample.named("red-fox")))
        try await waitUntil { model.isFinal }
        let before = try #require(model.preview?.template)
        let edit = line(in: before)

        var generated = false
        let serial = model.edit(edit)
        try await waitUntil(polling: .milliseconds(2)) {
            if model.phase == .generating || model.preview?.isDraft == true { generated = true }
            return model.settledEdits >= serial && model.isFinal
        }
        #expect(!generated, "An edit generated the template again")
        let laid = TemplateEditor.painted(edit, on: before, photo: try #require(model.source?.image))
        guard case .draw(_, _, .some(_)) = laid else { Issue.record("the line has no paints"); return }
        #expect(model.refinements.edits == [laid] && model.preview?.refinements == model.refinements)
        #expect(model.canUndo && !model.canRedo && model.note == nil)

        let (expected, outcome) = try TemplateEditor.apply(laid, to: before)
        #expect(outcome.declined == nil && outcome.changed)
        let after = try #require(model.preview?.template)
        #expect(after == expected, "The template on screen isn't the editor's result")
        #expect(after.palette == before.palette)
        #expect(model.stats?.areas == after.regions.count)

        let w = Float(before.width), h = Float(before.height)
        let box = (x: 0.42 * w - 8, y: 0.46 * h - 8, x2: 0.58 * w + 8, y2: 0.5 * h + 8)
        let away = before.regions.indices.filter { r in
            let b = before.regions[r].bounds
            return Float(b.maxX) < box.x || Float(b.minX) > box.x2 || Float(b.maxY) < box.y || Float(b.minY) > box.y2
        }
        #expect(away.count > 5, "No region lies away from the line")
        for r in away {
            let now = outcome.continued[r]
            #expect(before.polygons(ofRegion: r) == after.polygons(ofRegion: now), "region \(r)")
            #expect(before.labels(ofRegion: r).map { SIMD3($0.position.x, $0.position.y, $0.radius) }
                == after.labels(ofRegion: now).map { SIMD3($0.position.x, $0.position.y, $0.radius) })
            #expect(before.regions[r].colorIndex == after.regions[now].colorIndex)
        }

        // Start takes the template on screen, edits and all.
        let draft = try await model.makeDraft()
        #expect(draft.template == after && draft.refinements.edits == [laid])
        model.cancelAll()
    }

    /// A shape drawn closed takes the photo's colors for the pieces it cuts, kept in its edit, so
    /// the edit lays the same way without the photo.
    @Test func aClosedShapeTakesThePhotosColors() async throws {
        let model = CreateModel()
        model.load(sample: try #require(Sample.named("red-fox")))
        try await waitUntil { model.isFinal }
        let before = try #require(model.preview?.template)
        let w = Float(before.width), h = Float(before.height)
        let box = TemplateEditor.Edit.draw(
            points: [SIMD2(0.4 * w, 0.4 * h), SIMD2(0.6 * w, 0.4 * h), SIMD2(0.6 * w, 0.6 * h), SIMD2(0.4 * w, 0.6 * h)], closed: true)
        try await waitForEdits(model, model.edit(box))
        let laid = try #require(model.refinements.edits.first)
        guard case .draw(_, true, let paints?) = laid else { Issue.record("the shape has no paints: \(laid)"); return }
        #expect(!paints.isEmpty)
        #expect(laid == TemplateEditor.painted(box, on: before, photo: try #require(model.source?.image)))
        #expect(try TemplateEditor.apply(laid, to: before).template == model.preview?.template)
        model.cancelAll()
    }

    /// A Color Splitter stroke across the picture divides its color with no line: the edit keeps
    /// the photo's colors for its pieces, and the template on screen is the editor's result.
    @Test func aSplitDividesTheColorWithNoLine() async throws {
        let model = CreateModel()
        model.load(sample: try #require(Sample.named("red-fox")))
        try await waitUntil { model.isFinal }
        let before = try #require(model.preview?.template)
        let w = Float(before.width), h = Float(before.height)
        let split = TemplateEditor.Edit.split(points: [SIMD2(0, 0.2 * h), SIMD2(w, 0.25 * h)])
        try await waitForEdits(model, model.edit(split))
        let laid = try #require(model.refinements.edits.first)
        guard case .split(_, false, let paints) = laid else { Issue.record("not a split: \(laid)"); return }
        #expect(!paints.isEmpty)
        #expect(laid == TemplateEditor.painted(split, on: before, photo: try #require(model.source?.image)))
        let (expected, outcome) = try TemplateEditor.apply(laid, to: before)
        #expect(outcome.regionsSplit > 0 && outcome.strokes == 0)
        #expect(model.preview?.template == expected)
        // A stroke the split's boundary cuts becomes two as long as it was (its cut on the lattice,
        // a fraction of a unit off): no ink is added.
        func ink(_ t: Template) -> Float {
            guard let art = t.lineArt else { return 0 }
            return art.strokes.reduce(Float(0)) { sum, stroke in
                let points = art.strokePoints[Int(stroke.pointStart)..<Int(stroke.pointStart + stroke.pointCount)]
                return sum + zip(points, points.dropFirst()).reduce(Float(0)) { length, step in
                    let d = step.1 - step.0
                    return length + (d * d).sum().squareRoot()
                }
            }
        }
        #expect(abs(ink(expected) - ink(before)) < 1, "a split draws no line")
        model.cancelAll()
    }

    /// Undo brings the previous template back exactly, from the templates kept; Redo puts the edit
    /// back; Cancel puts back what Refine opened with.
    @Test func undoRestoresThePreviousTemplateExactly() async throws {
        let model = CreateModel()
        model.load(sample: try #require(Sample.named("red-fox")))
        try await waitUntil { model.isFinal }
        let before = try #require(model.preview?.template)
        model.beginRefining()
        let photo = try #require(model.source?.image)
        try await waitForEdits(model, model.edit(line(in: before)))
        let once = try #require(model.preview?.template)
        let first = TemplateEditor.painted(line(in: before), on: before, photo: photo)
        let w = Float(before.width), h = Float(before.height)
        let drawn = TemplateEditor.Edit.draw(points: [SIMD2(0.2 * w, 0.2 * h), SIMD2(0.3 * w, 0.25 * h)])
        try await waitForEdits(model, model.edit(drawn))
        let second = TemplateEditor.painted(drawn, on: once, photo: photo)
        let twice = try #require(model.preview?.template)
        #expect(model.refinements.edits == [first, second] && twice != once)

        model.undo()
        try await waitUntil { model.refinements.edits == [first] && model.isFinal }
        #expect(model.preview?.template == once)
        #expect(model.canUndo && model.canRedo)
        model.redo()
        try await waitUntil { model.refinements.edits == [first, second] && model.isFinal }
        #expect(model.preview?.template == twice)

        model.undo()
        model.undo()
        try await waitUntil { model.refinements.edits.isEmpty && model.isFinal }
        #expect(model.preview?.template == before)
        #expect(!model.canUndo && model.canRedo)

        // Cancel goes back to what Refine opened with, whatever came after.
        model.redo()
        try await waitUntil { model.refinements.edits == [first] && model.isFinal }
        model.cancelRefining()
        try await waitUntil { model.refinements.edits.isEmpty && model.isFinal }
        #expect(model.preview?.template == before)
        model.cancelAll()
    }

    /// An edit that cannot be made changes nothing: the template, the edits and the steps of Undo
    /// are as they were, and the painter is told.
    @Test func aDeclinedEditLeavesTheTemplateAsItWas() async throws {
        let model = CreateModel()
        model.load(sample: try #require(Sample.named("red-fox")))
        try await waitUntil { model.isFinal }
        let before = try #require(model.preview?.template)
        let shown = model.preview?.id

        // A tap off the canvas has no shape to fill.
        let serial = model.edit(.fill(at: SIMD2(1e9, -1e9), color: SIMD3(0.5, 0, 0)))
        try await waitUntil(polling: .milliseconds(2)) { model.settledEdits >= serial }
        #expect(model.refinements.edits.isEmpty && !model.canUndo)
        #expect(model.preview?.id == shown && model.preview?.template == before)
        #expect(model.note?.kind == .notFilled)
        #expect(model.isFinal)

        // An eraser over nothing does nothing and says nothing.
        model.dismissNote()
        let nothing = model.edit(.erase(path: [SIMD2(0.5, 0.5)], radius: 0.01))
        try await waitUntil(polling: .milliseconds(2)) { model.settledEdits >= nothing }
        #expect(model.refinements.edits.isEmpty && model.note == nil && model.preview?.template == before)
        model.cancelAll()
    }

    /// A tap of Fill makes the shape under it an area, and a tap in that area takes the fill out
    /// again: the template is the one it was.
    @Test func aTapInAFilledAreaClearsTheFill() async throws {
        let model = CreateModel()
        model.load(sample: try #require(Sample.named("red-fox")))
        try await waitUntil { model.isFinal }
        let before = try #require(model.preview?.template)
        let point = SIMD2(0.5 * Float(before.width), 0.5 * Float(before.height))
        let color = SIMD3<Float>(0.6, 0.05, 0.05)

        try await waitForEdits(model, model.fill(at: point, color: color))
        let filled = try #require(model.preview?.template)
        #expect(model.refinements.edits == [.fill(at: point, color: color)])
        #expect(filled.detailRegions.count == before.detailRegions.count + 1)

        try await waitForEdits(model, model.fill(at: point, color: color))
        #expect(model.refinements.edits.isEmpty)
        #expect(model.preview?.template == before)
        model.undo()
        try await waitUntil { model.refinements.edits.count == 1 && model.isFinal }
        #expect(model.preview?.template == filled)
        model.cancelAll()
    }

    /// Refine's Colors: a look is laid on the template on screen alone, as the editor lays it; its
    /// strength takes its place; a color the picker moves on is one step of the history; and the
    /// photo's colors take them all out, back to the template it was.
    @Test func colorsLayLooksAndRepaintsOnTheTemplateOnScreen() async throws {
        let model = CreateModel()
        model.load(sample: try #require(Sample.named("red-fox")))
        try await waitUntil { model.isFinal }
        let before = try #require(model.preview?.template)
        func shows(_ edits: [TemplateEditor.Edit]) -> Bool {
            model.refinements.edits == edits && model.preview?.refinements == model.refinements && model.isFinal
        }

        var generated = false
        model.recolor(.look(.moonlit, strength: 1))
        let look = TemplateEditor.look(.moonlit, strength: 1, on: before)
        try await waitUntil(polling: .milliseconds(2)) {
            if model.phase == .generating { generated = true }
            return shows([look])
        }
        #expect(!generated, "A look generated the template again")
        #expect(model.preview?.template == (try TemplateEditor.apply(look, to: before).template))

        model.recolor(.look(.moonlit, strength: 0.5))
        let softer = TemplateEditor.look(.moonlit, strength: 0.5, on: before)
        try await waitUntil { shows([softer]) }

        let from = try #require(model.preview?.template.palette.first?.oklab)
        let first = TemplateEditor.Edit.repaint(from: from, to: SIMD3(0.5, 0.1, -0.1), family: true)
        let moved = TemplateEditor.Edit.repaint(from: from, to: SIMD3(0.5, -0.1, -0.1), family: true)
        model.recolor(.repaint(from: from, to: SIMD3(0.5, 0.1, -0.1), family: true))
        try await waitUntil { shows([softer, first]) }
        model.recolor(.repaint(from: from, to: SIMD3(0.5, -0.1, -0.1), family: true))
        try await waitUntil { shows([softer, moved]) }
        model.undo()
        try await waitUntil { shows([softer]) }

        model.recolor(.photo)
        try await waitUntil { shows([]) }
        #expect(model.preview?.template == before)
        model.cancelAll()
    }

    /// The sliders make the template again and the edits are laid on the new one, as the editor
    /// lays them: the painter's lines survive.
    @Test func aSliderChangeLaysTheEditsOnTheNewTemplate() async throws {
        let model = CreateModel()
        model.load(sample: try #require(Sample.named("red-fox")))
        try await waitUntil { model.isFinal }
        let first = try #require(model.preview?.template)
        let settings = model.settings
        try await waitForEdits(model, model.edit(line(in: first)))
        let drawn = try #require(model.preview?.template)
        let edit = TemplateEditor.painted(line(in: first), on: first, photo: try #require(model.source?.image))
        #expect(model.refinements.edits == [edit])

        model.detail = settings.detail < 0.75 ? Double(settings.detail) + 0.25 : Double(settings.detail) - 0.25
        model.settingsChanged()
        try await waitUntil { model.isFinal }
        #expect(model.preview?.settings != settings && model.preview?.settings == model.settings)
        #expect(model.preview?.refinements.edits == [edit] && model.refinements.edits == [edit])
        let shown = try #require(model.preview?.template)
        #expect(shown != drawn)

        // Taking the edit back shows the new template without it: the edit was laid on that one.
        model.undo()
        try await waitUntil { model.refinements.edits.isEmpty && model.isFinal }
        let base = try #require(model.preview?.template)
        #expect(try TemplateEditor.apply(edit, to: base).template == shown)
        model.cancelAll()
    }

    /// Edits sent while the template is being made again are laid on it before it shows (a drawn
    /// line as drawn: there was no template to read its pieces' colors on).
    @Test func editsSentWhileTheTemplateIsMadeAgainAreNotLost() async throws {
        let model = CreateModel()
        model.load(sample: try #require(Sample.named("red-fox")))
        try await waitUntil { model.isFinal }
        let edit = line(in: try #require(model.preview?.template))

        model.detail = model.detail < 0.75 ? model.detail + 0.25 : model.detail - 0.25
        model.settingsChanged()
        let serial = model.edit(edit)
        try await waitUntil { model.settledEdits >= serial && model.isFinal }
        #expect(model.preview?.settings == model.settings)
        #expect(model.refinements.edits == [edit] && model.preview?.refinements.edits == [edit])
        let shown = try #require(model.preview?.template)
        model.undo()
        try await waitUntil { model.refinements.edits.isEmpty && model.isFinal }
        let base = try #require(model.preview?.template)
        #expect(try TemplateEditor.apply(edit, to: base).template == shown)
        model.cancelAll()
    }

    /// A split sent while the template is being made again takes its paints from the template on
    /// screen: without them it could never be made.
    @Test func aSplitSentWhileTheTemplateIsMadeAgainKeepsItsPaints() async throws {
        let model = CreateModel()
        model.load(sample: try #require(Sample.named("red-fox")))
        try await waitUntil { model.isFinal }
        let before = try #require(model.preview?.template)
        let w = Float(before.width), h = Float(before.height)
        let split = TemplateEditor.Edit.split(points: [SIMD2(0, 0.2 * h), SIMD2(w, 0.25 * h)])

        model.lines = 0.7
        model.settingsChanged()
        let serial = model.edit(split)
        try await waitUntil { model.settledEdits >= serial && model.isFinal }
        let kept = try #require(model.refinements.edits.first)
        #expect(kept == TemplateEditor.painted(split, on: before, photo: try #require(model.source?.image)))
        guard case .split(_, _, let paints) = kept else { Issue.record("not a split: \(kept)"); return }
        #expect(!paints.isEmpty)
        model.cancelAll()
    }

    // MARK: Start From

    /// A blank start makes the template the photo as one area on the canvas the generator would
    /// make, before any edit; a Pen line across it cuts it in two, each side in the photo's color
    /// there; Undo takes the line back, and then the blank start, back to the generator's template.
    @Test func aBlankStartIsOneAreaThatAPenLineSplits() async throws {
        let model = CreateModel()
        model.load(sample: try #require(Sample.named("red-fox")))
        try await waitUntil { model.isFinal }
        #expect(model.hasLineArtInput && model.refinements.start == .generated)
        let generated = try #require(model.preview?.template)
        model.beginRefining()

        model.start(from: .blank)
        try await waitUntil { model.refinements.start == .blank && model.isFinal }
        #expect(model.canUndo && model.refinements.changeCount == 0)
        let blank = try #require(model.preview?.template)
        let photo = try #require(model.source?.image)
        #expect(blank.regions.count == 1 && blank.palette.count == 1)
        #expect(blank.width == generated.width && blank.height == generated.height)
        #expect(blank == (try TemplateEditor.blank(width: blank.width, height: blank.height, photo: photo, colorSpace: photo.colorSpace)))

        let w = Float(blank.width), h = Float(blank.height)
        let pen = TemplateEditor.Edit.draw(points: [SIMD2(0.5 * w, -6), SIMD2(0.5 * w, h + 6)])
        try await waitForEdits(model, model.edit(pen))
        let cut = try #require(model.preview?.template)
        #expect(cut.regions.count == 2, "The line didn't cut the blank in two")
        let laid = TemplateEditor.painted(pen, on: blank, photo: photo)
        #expect(model.refinements.edits == [laid] && model.refinements.start == .blank)
        #expect(cut == (try TemplateEditor.apply(laid, to: blank).template))
        #expect(model.closedShape != nil)
        // Start saves it as it shows; the making-of has no steps of the generator's to play.
        let made = try await model.makeDraft()
        #expect(made.template == cut && made.refinements.start == .blank)
        #expect(model.makingOfSource(for: made, artworkID: UUID()) == nil)

        model.undo()
        try await waitUntil { model.refinements.edits.isEmpty && model.isFinal }
        #expect(model.preview?.template == blank)
        model.undo()
        try await waitUntil { model.refinements.start == .generated && model.isFinal }
        #expect(model.preview?.template == generated && model.refinements.isEmpty && !model.canUndo)
        model.cancelAll()
    }

    /// Cancel puts back what Refine opened with: a blank start chosen in it goes, and the
    /// generator's template shows again.
    @Test func cancelTakesABlankStartBack() async throws {
        let model = CreateModel()
        model.load(sample: try #require(Sample.named("red-fox")))
        try await waitUntil { model.isFinal }
        let generated = try #require(model.preview?.template)
        model.beginRefining()

        model.start(from: .blank)
        try await waitUntil { model.refinements.start == .blank && model.isFinal }
        model.cancelRefining()
        try await waitUntil { model.refinements.start == .generated && model.isFinal }
        #expect(model.preview?.template == generated && model.refinements.isEmpty && !model.canUndo)
        model.cancelAll()
    }

    /// Start From picks the base only before the first edit: picked with an edit on its way (sent
    /// before its turn came) or made, it leaves the base as it is.
    @Test func startFromDoesNothingOnceAnEditIsSent() async throws {
        let model = CreateModel()
        model.load(sample: try #require(Sample.named("red-fox")))
        try await waitUntil { model.isFinal }
        let generated = try #require(model.preview?.template)
        let before = model.settings
        model.beginRefining()

        model.start(from: .blank)
        try await waitForEdits(model, model.edit(line(in: generated)))
        #expect(model.refinements.start == .generated && model.refinements.edits.count == 1)

        model.start(from: .blank)
        // Start Painting waits for the changes sent before it.
        let made = try await model.makeDraft()
        #expect(made.refinements.start == .generated && made.refinements.edits.count == 1 && made.settings == before)
        model.cancelAll()
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
